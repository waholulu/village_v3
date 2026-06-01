param(
	[string]$Preset = "default",
	[string]$GodotPath = "",
	[string]$OutputDir = ".godot/headless_audit",
	[int]$MaxFinalStrategicFood = 220,
	[double]$MaxNegativeClaimRate = 0.05,
	[int]$MaxDailyCancellationBurst = 40,
	[int]$SweepStartSeed = 4312,
	[int]$SweepSeedCount = 10,
	[int]$RequiredSweepWins = 7,
	[double]$MinWinningAverageDeathRate = 0.20,
	[double]$MaxWinningAverageDeathRate = 0.40,
	[switch]$Strict
)

$ErrorActionPreference = "Stop"

function Resolve-GodotPath {
	param([string]$RequestedPath)
	if ($RequestedPath -and (Test-Path -LiteralPath $RequestedPath)) {
		return (Resolve-Path -LiteralPath $RequestedPath).Path
	}
	if ($env:GODOT_BIN -and (Test-Path -LiteralPath $env:GODOT_BIN)) {
		return (Resolve-Path -LiteralPath $env:GODOT_BIN).Path
	}
	$fromPath = Get-Command godot -ErrorAction SilentlyContinue
	if ($fromPath) {
		return $fromPath.Source
	}
	$repoParent = Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")
	$candidates = @(
		(Join-Path $repoParent "Godot_v4.6.3-stable_win64_console.exe"),
		(Join-Path $repoParent "Godot_v4.6.3-stable_win64.exe")
	)
	foreach ($candidate in $candidates) {
		if (Test-Path -LiteralPath $candidate) {
			return (Resolve-Path -LiteralPath $candidate).Path
		}
	}
	throw "Godot executable not found. Pass -GodotPath or set GODOT_BIN."
}

function Get-EventGroups {
	param($Items, [string]$Property)
	$groups = [ordered]@{}
	foreach ($item in $Items) {
		$value = $item.$Property
		if ($null -eq $value -or "$value" -eq "") {
			$value = "<none>"
		}
		$key = "$value"
		if (-not $groups.Contains($key)) {
			$groups[$key] = 0
		}
		$groups[$key] += 1
	}
	return $groups
}

function Invoke-HeadlessRun {
	param(
		[string]$RepoRoot,
		[string]$Godot,
		[string]$Preset,
		[string]$RunDir,
		[string]$LogName,
		[int]$Seed = 0
	)
	$args = @("--headless", "--path", ".", "-s", "res://scripts/core/headless_runner.gd")
	$userArgs = @()
	if ($Preset -ne "default") {
		$userArgs += "preset=$Preset"
	}
	if ($Seed -gt 0) {
		$userArgs += "seed=$Seed"
	}
	if ($userArgs.Count -gt 0) {
		$args += "--"
		$args += $userArgs
	}

	Push-Location $RepoRoot
	try {
		$output = & $Godot @args 2>&1
		$exitCode = $LASTEXITCODE
	} finally {
		Pop-Location
	}

	$logPath = Join-Path $RunDir $LogName
	$output | Set-Content -LiteralPath $logPath
	$text = ($output -join "`n")
	$jsonlPath = $null
	if ($text -match "local path:\s*(.*?\.jsonl)") {
		$jsonlPath = $Matches[1].Trim()
	}
	$events = @()
	if ($jsonlPath -and (Test-Path -LiteralPath $jsonlPath)) {
		$events = Get-Content -LiteralPath $jsonlPath | Where-Object { $_.Trim() -ne "" } | ForEach-Object { $_ | ConvertFrom-Json }
	}

	$snapshots = @()
	foreach ($line in $output) {
		if ($line -match "^(START|DAY_STARTED|NIGHT_RESOLVED|FINAL) \| day=(\d+).*strategic\(pop=(\d+) food=(\d+) security=(\d+) morale=(\d+) zero=(\d+)\/(\d+)\/(\d+)\).*legacy\(wood=(\d+) food=(\d+)\+(\d+) visible=(\d+)\/(\d+) dead=(\d+) hungry=(\d+) campfire_out=(\d+)\).*tasks\(open=(\d+) claimed=(\d+) done=(\d+) cancelled=(\d+)\) anomalies=(\d+)") {
			$snapshots += [pscustomobject]@{
				label = $Matches[1]
				day = [int]$Matches[2]
				population = [int]$Matches[3]
				strategic_food = [int]$Matches[4]
				security = [int]$Matches[5]
				morale = [int]$Matches[6]
				zero_food_days = [int]$Matches[7]
				zero_morale_days = [int]$Matches[8]
				zero_security_days = [int]$Matches[9]
				wood = [int]$Matches[10]
				fresh_food = [int]$Matches[11]
				stored_food = [int]$Matches[12]
				visible_population = [int]$Matches[13]
				population_capacity = [int]$Matches[14]
				dead_population = [int]$Matches[15]
				hungry = [int]$Matches[16]
				campfire_out = [int]$Matches[17]
				open_tasks = [int]$Matches[18]
				claimed_tasks = [int]$Matches[19]
				done_tasks = [int]$Matches[20]
				cancelled_tasks = [int]$Matches[21]
				anomalies = [int]$Matches[22]
			}
		}
	}

	$result = "UNKNOWN"
	if ($text -match "RESULT:\s*([^\r\n]+)") {
		$result = $Matches[1].Trim()
	}

	$taskClaims = @($events | Where-Object { $_.event -eq "task_claimed" })
	$negativeClaims = @($taskClaims | Where-Object { $null -ne $_.score -and [double]$_.score -lt 0.0 })
	$claimRate = if ($taskClaims.Count -gt 0) { [math]::Round($negativeClaims.Count / [double]$taskClaims.Count, 4) } else { 0.0 }
	$cancelEvents = @($events | Where-Object { $_.event -eq "task_cancelled" })
	$cancelByDay = Get-EventGroups $cancelEvents "day"
	$maxCancelBurst = 0
	foreach ($count in $cancelByDay.Values) {
		$maxCancelBurst = [math]::Max($maxCancelBurst, [int]$count)
	}

	$finalSnapshot = if ($snapshots.Count -gt 0) { $snapshots[-1] } else { $null }
	$finalSummary = @($events | Where-Object { $_.event -eq "run_summary" } | Select-Object -Last 1)
	$deathRate = $null
	if ($finalSummary.Count -gt 0 -and $null -ne $finalSummary[0].death_rate) {
		$deathRate = [double]$finalSummary[0].death_rate
	} elseif ($finalSnapshot) {
		$startingPopulation = [math]::Max(1, $finalSnapshot.population + $finalSnapshot.dead_population)
		$deathRate = [math]::Round($finalSnapshot.dead_population / [double]$startingPopulation, 4)
	}

	return [pscustomobject]@{
		preset = $Preset
		seed = $Seed
		exit_code = $exitCode
		result = $result
		log_path = $logPath
		jsonl_log = $jsonlPath
		events = $events
		snapshots = $snapshots
		final = $finalSnapshot
		task_claims = $taskClaims
		negative_claims = $negativeClaims
		negative_claim_rate = $claimRate
		task_cancellations = $cancelEvents
		max_daily_cancellation_burst = $maxCancelBurst
		death_rate = $deathRate
	}
}

$godot = Resolve-GodotPath $GodotPath
$repoRoot = Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$runName = "$timestamp`_$Preset"
$runDir = Join-Path (Resolve-Path -LiteralPath $repoRoot).Path (Join-Path $OutputDir $runName)
New-Item -ItemType Directory -Force -Path $runDir | Out-Null

$primaryRun = Invoke-HeadlessRun -RepoRoot $repoRoot -Godot $godot -Preset $Preset -RunDir $runDir -LogName "godot.log"
$primaryEvents = $primaryRun.events
$primarySnapshots = $primaryRun.snapshots
$finalSnapshot = $primaryRun.final
$foodValues = @($primarySnapshots | ForEach-Object { $_.strategic_food })
$woodValues = @($primarySnapshots | ForEach-Object { $_.wood })
$anomalyValues = @($primarySnapshots | ForEach-Object { $_.anomalies })
$securityValues = @($primarySnapshots | ForEach-Object { $_.security } | Select-Object -Unique)
$moraleValues = @($primarySnapshots | ForEach-Object { $_.morale } | Select-Object -Unique)
$populationMismatch = $false
if ($finalSnapshot) {
	$populationMismatch = $finalSnapshot.population -ne $finalSnapshot.visible_population
}

$gates = [ordered]@{
	godot_exit_zero = ($primaryRun.exit_code -eq 0)
	result_is_win = $primaryRun.result.StartsWith("WIN")
	monitor_clean = (($anomalyValues | Measure-Object -Maximum).Maximum -eq 0)
	final_food_not_runaway = ($finalSnapshot -and $finalSnapshot.strategic_food -le $MaxFinalStrategicFood)
	negative_claim_rate_ok = ($primaryRun.negative_claim_rate -le $MaxNegativeClaimRate)
	cancel_burst_ok = ($primaryRun.max_daily_cancellation_burst -le $MaxDailyCancellationBurst)
}

$seedSweep = @()
$winningAverageDeathRate = $null
$sweepWins = $null
if ($Preset -eq "default") {
	for ($offset = 0; $offset -lt $SweepSeedCount; $offset++) {
		$seed = $SweepStartSeed + $offset
		$seedSweep += Invoke-HeadlessRun -RepoRoot $repoRoot -Godot $godot -Preset $Preset -RunDir $runDir -LogName ("seed_{0}.log" -f $seed) -Seed $seed
	}
	$winningSweepRuns = @($seedSweep | Where-Object { $_.result.StartsWith("WIN") -and $null -ne $_.death_rate })
	$sweepWins = $winningSweepRuns.Count
	if ($winningSweepRuns.Count -gt 0) {
		$winningAverageDeathRate = [math]::Round((($winningSweepRuns | Measure-Object -Property death_rate -Average).Average), 4)
	}
	$gates["sweep_win_count_ok"] = ($sweepWins -ge $RequiredSweepWins)
	$gates["winning_average_death_rate_ok"] = (
		$null -ne $winningAverageDeathRate `
		-and $winningAverageDeathRate -ge $MinWinningAverageDeathRate `
		-and $winningAverageDeathRate -le $MaxWinningAverageDeathRate
	)
}

$report = [ordered]@{
	preset = $Preset
	godot = $godot
	exit_code = $primaryRun.exit_code
	result = $primaryRun.result
	godot_log = $primaryRun.log_path
	jsonl_log = $primaryRun.jsonl_log
	total_events = $primaryEvents.Count
	event_counts = Get-EventGroups $primaryEvents "event"
	final = if ($finalSnapshot) { $finalSnapshot } else { $null }
	food = [ordered]@{
		min = if ($foodValues.Count) { ($foodValues | Measure-Object -Minimum).Minimum } else { $null }
		max = if ($foodValues.Count) { ($foodValues | Measure-Object -Maximum).Maximum } else { $null }
		final = if ($finalSnapshot) { $finalSnapshot.strategic_food } else { $null }
	}
	wood = [ordered]@{
		min = if ($woodValues.Count) { ($woodValues | Measure-Object -Minimum).Minimum } else { $null }
		max = if ($woodValues.Count) { ($woodValues | Measure-Object -Maximum).Maximum } else { $null }
		final = if ($finalSnapshot) { $finalSnapshot.wood } else { $null }
	}
	security_unique = $securityValues
	morale_unique = $moraleValues
	population_mismatch = $populationMismatch
	death_rate = $primaryRun.death_rate
	task_claims = [ordered]@{
		total = $primaryRun.task_claims.Count
		negative = $primaryRun.negative_claims.Count
		negative_rate = $primaryRun.negative_claim_rate
		by_type = Get-EventGroups $primaryRun.task_claims "task"
	}
	task_cancellations = [ordered]@{
		total = $primaryRun.task_cancellations.Count
		max_daily_burst = $primaryRun.max_daily_cancellation_burst
		by_reason = Get-EventGroups $primaryRun.task_cancellations "reason"
		by_type = Get-EventGroups $primaryRun.task_cancellations "task"
	}
	seed_sweep = @(
		$seedSweep | ForEach-Object {
			[ordered]@{
				seed = $_.seed
				result = $_.result
				exit_code = $_.exit_code
				death_rate = $_.death_rate
				dead_population = if ($_.final) { $_.final.dead_population } else { $null }
				final_day = if ($_.final) { $_.final.day } else { $null }
			}
		}
	)
	sweep_summary = if ($Preset -eq "default") {
		[ordered]@{
			seed_start = $SweepStartSeed
			seed_count = $SweepSeedCount
			wins = $sweepWins
			required_wins = $RequiredSweepWins
			winning_average_death_rate = $winningAverageDeathRate
			target_range = @($MinWinningAverageDeathRate, $MaxWinningAverageDeathRate)
		}
	} else { $null }
	gates = $gates
}

$reportPath = Join-Path $runDir "audit_report.json"
$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $reportPath

Write-Host "Headless audit: preset=$Preset result=$($primaryRun.result) exit=$($primaryRun.exit_code)"
Write-Host "  report: $reportPath"
Write-Host "  godot log: $($primaryRun.log_path)"
if ($primaryRun.jsonl_log) {
	Write-Host "  jsonl: $($primaryRun.jsonl_log)"
}
if ($finalSnapshot) {
	Write-Host ("  final: day={0} food={1} wood={2} security={3} morale={4} pop={5}/{6} dead={7}" -f `
		$finalSnapshot.day, $finalSnapshot.strategic_food, $finalSnapshot.wood, `
		$finalSnapshot.security, $finalSnapshot.morale, `
		$finalSnapshot.visible_population, $finalSnapshot.population_capacity, $finalSnapshot.dead_population)
}
Write-Host ("  task claims: total={0} negative={1} rate={2}" -f $primaryRun.task_claims.Count, $primaryRun.negative_claims.Count, $primaryRun.negative_claim_rate)
Write-Host ("  cancellations: total={0} max_daily_burst={1}" -f $primaryRun.task_cancellations.Count, $primaryRun.max_daily_cancellation_burst)
if ($Preset -eq "default") {
	Write-Host ("  sweep: wins={0}/{1} avg_death_rate={2}" -f $sweepWins, $SweepSeedCount, $winningAverageDeathRate)
}
Write-Host "  gates:"
foreach ($key in $gates.Keys) {
	$status = if ($gates[$key]) { "PASS" } else { "FAIL" }
	Write-Host "    $status $key"
}

if ($Strict) {
	foreach ($value in $gates.Values) {
		if (-not $value) {
			exit 1
		}
	}
	exit $primaryRun.exit_code
}
exit 0
