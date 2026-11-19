<#
.SYNOPSIS
  Schedule (or list / get / delete) a JasperReports Server report job via the
  REST v2 `jobs` service -- recurring, triggered, or one-off report delivery to
  the repository and/or by email.

.DESCRIPTION
  Wraps the verified `/rest_v2/jobs` recipe. Creating a job PUTs a job
  descriptor; BOTH Content-Type AND Accept must be `application/job+json` (a
  plain application/json Accept gives 406 Not Acceptable). The descriptor is
  passed from a file so PowerShell->curl quoting can't mangle it.

  Server URL and credentials resolve in this order (first wins):
    1. -ServerUrl / -User / -Password parameters
    2. environment variables JRS_URL / JRS_USER / JRS_PASS
    3. jrs.config.json in the skill root (gitignored)

  Scheduler control (1.4.0): pause | resume | restart act on explicit job ids
  (-Id) or on every job (-All, expanded client-side into an explicit id list:
  an EMPTY list sent to /jobs/pause or /jobs/resume acts on every job in the
  scheduler, REST ref 10.0.0 p.229-231, so the script never sends one). These
  PLAN by default and write only with -Apply, journaled under out\runs so
  recover_run.ps1 -RunId <id> -Rollback -Apply undoes them (pause <-> resume of
  exactly the jobs the run changed; restart is irreversible). Resume does not
  re-run triggers missed while a job was paused. `state` is read-only.
  A prod profile additionally needs $env:JRS_ALLOW_PROD_WRITE = '1'.

  Upgrade windows: `snapshot` (read-only, PROD-safe) saves every job's state to
  out\job-snapshots\; `restore -Snapshot <file>` puts those states back (plan by
  default): re-pauses jobs an upgrade resumed (7.5.1 -> 7.9.2+ does, KB) and
  resumes jobs that were running. Jobs are matched by id, else by label + report
  URI; unmatched ones are listed and make the exit code 2 (review by hand).

.PARAMETER Action
  create (default) | list | get | delete | pause | resume | restart | state |
  snapshot | restore.

.PARAMETER Snapshot
  restore: the snapshot file written by -Action snapshot.

.PARAMETER Out
  snapshot: output file (default out\job-snapshots\<env|host-port>-<timestamp>.json).

.PARAMETER ReportUri
  Repository URI of the report unit to schedule, e.g.
  /reports/geocoder/county_summary. Required for create; optional filter for list.

.PARAMETER Id
  Job id(s). Exactly one for get/delete; one or more for pause/resume/restart/
  state (an array, or one comma-separated string such as "101,103").

.PARAMETER All
  pause/resume/restart/state: every job on the server (mutually exclusive with -Id).

.PARAMETER Apply
  pause/resume/restart: actually write. Without it the plan is printed only.

.PARAMETER Env
  Named profile in jrs.config.json "environments".

.PARAMETER Label
  Job label (create). Defaults to "<report leaf> scheduled".

.PARAMETER StartType
  now | at. Default: "at" when -StartDate is given, else "now".

.PARAMETER StartDate
  Fire time for StartType=at, "yyyy-MM-dd HH:mm:ss" (local to -Timezone).

.PARAMETER Timezone
  Olson timezone for the trigger. Default America/Chicago.

.PARAMETER OccurrenceCount
  Number of fires. 1 = once (default). For a recurring job set this to -1 (or any
  count > 1) AND pass -RecurrenceInterval/-RecurrenceIntervalUnit.

.PARAMETER RecurrenceInterval
  Interval count for a recurring simpleTrigger (e.g. 1).

.PARAMETER RecurrenceIntervalUnit
  MINUTE | HOUR | DAY | WEEK. Pair with -RecurrenceInterval.

.PARAMETER OutputFormats
  One or more of PDF, HTML, XLSX, CSV, DOCX, PPTX, RTF, ODS, ODT, XML.
  Default: PDF.

.PARAMETER BaseOutputFilename
  Output file base name (no extension). Default: the report leaf name.

.PARAMETER DestinationFolder
  Repository folder the output is written to. Default: the report's parent folder.

.PARAMETER MailTo
  One or more email addresses; adds a mailNotification (SEND_ATTACHMENT).

.PARAMETER Parameters
  Hashtable of report parameter/input-control values to bake into the job.

.EXAMPLE
  # one-off PDF saved to the repo at a future date
  .\schedule_job.ps1 -ReportUri /reports/geocoder/county_summary `
      -Label "County summary monthly" -StartDate "2026-12-01 09:00:00"

.EXAMPLE
  # every day forever, emailed
  .\schedule_job.ps1 -ReportUri /reports/geocoder/county_summary `
      -StartType now -OccurrenceCount -1 -RecurrenceInterval 1 -RecurrenceIntervalUnit DAY `
      -OutputFormats PDF,XLSX -MailTo ops@example.com

.EXAMPLE
  .\schedule_job.ps1 -Action list -ReportUri /reports/geocoder/county_summary
  .\schedule_job.ps1 -Action delete -Id 42

.EXAMPLE
  # pause two jobs: plan first, then apply; undo with recover_run.ps1
  .\schedule_job.ps1 -Action pause -Id 101,103
  .\schedule_job.ps1 -Action pause -Id 101,103 -Apply
  .\schedule_job.ps1 -Action state -Id 101,103
#>
[CmdletBinding()]
param(
    [ValidateSet("create", "list", "get", "delete", "pause", "resume", "restart", "state", "snapshot", "restore")]
    [string]$Action = "create",
    [string]$ReportUri,
    [string[]]$Id,
    [switch]$All,
    [switch]$Apply,
    [string]$Env,
    [string]$Snapshot,
    [string]$Out,
    [string]$Label,
    [ValidateSet("now", "at")]
    [string]$StartType,
    [string]$StartDate,
    [string]$Timezone = "America/Chicago",
    [int]$OccurrenceCount = 1,
    [int]$RecurrenceInterval,
    [ValidateSet("MINUTE", "HOUR", "DAY", "WEEK")]
    [string]$RecurrenceIntervalUnit,
    [string[]]$OutputFormats = @("PDF"),
    [string]$BaseOutputFilename,
    [string]$DestinationFolder,
    [string[]]$MailTo,
    [hashtable]$Parameters,
    [string]$ServerUrl,
    [string]$User,
    [string]$Password
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "_jrs_common.ps1")
$jrs = Resolve-JrsConfig -ServerUrl $ServerUrl -User $User -Password $Password -Env $Env
$JOB_MEDIA = "application/job+json"

function leaf($uri) { $uri.Substring($uri.LastIndexOf("/") + 1) }
function parent($uri) { $uri.Substring(0, $uri.LastIndexOf("/")) }

# -Id arrives as strings (also "101,103" through powershell -File): parse to ints
$ids = [int[]]@($Id | ForEach-Object { "$_" -split "," } | ForEach-Object { $_.Trim() } | Where-Object { $_ } | ForEach-Object {
    $n = 0; if (-not [int]::TryParse($_, [ref]$n)) { throw "-Id '$_' is not a job id" }; $n })
if ($Action -in "get", "delete" -and $ids.Count -ne 1) { throw "-Id takes one id for get/delete" }
$Id1 = if ($ids.Count) { $ids[0] } else { 0 }

if ($Action -eq "snapshot") {
    $path = New-JrsJobSnapshot -Jrs $jrs -Path $Out
    $n = @((Get-Content $path -Raw | ConvertFrom-Json).jobs).Count
    Write-Host "OK: snapshot of $n job(s) -> $path"
    Write-Output $path
    return
}

if ($Action -eq "restore") {
    if (-not $Snapshot) { throw "-Snapshot <file> is required for restore" }
    if (-not (Test-Path $Snapshot)) { throw "snapshot not found: $Snapshot" }
    $snap = Get-Content $Snapshot -Raw | ConvertFrom-Json
    $where = "$($jrs.ServerUrl)$(if ($jrs.Env) { " [env $($jrs.Env)]" })"
    $current = @(Get-JrsJobList -Jrs $jrs | ForEach-Object {
        [pscustomobject]@{ Id = $_.Id; Label = $_.Label; ReportUnitURI = $_.ReportUnitURI; Value = (Get-JrsJobState -Jrs $jrs -Id $_.Id).Value } })
    $plan = @(Get-JrsJobRestorePlan -Snapshot $snap -Current $current)
    Write-Host ""
    Write-Host "JOBS RESTORE PLAN from $Snapshot (taken $($snap.takenAt) on $($snap.server)) to $where"
    foreach ($row in $plan) {
        Write-Host ("  [{0,-6}] {1,-10} was {2,-8} now {3,-9} -> {4,-10} {5}" -f $row.Id, "$($row.Label)", $row.Was, $row.Now, $row.Act, $(if ($row.MatchedBy -and $row.MatchedBy -ne "id") { "(matched by $($row.MatchedBy))" } else { "" }))
    }
    $unresolved = @($plan | Where-Object { $_.Act -eq "unresolved" })
    $batches = @(
        @{ Action = "pause";  Ids = [int[]]@($plan | Where-Object { $_.Act -eq "pause" }  | ForEach-Object { $_.Id }) },
        @{ Action = "resume"; Ids = [int[]]@($plan | Where-Object { $_.Act -eq "resume" } | ForEach-Object { $_.Id }) }
    ) | Where-Object { $_.Ids.Count -gt 0 }
    if (@($batches | Where-Object { $_.Action -eq "resume" }).Count) { Write-Host "  note: resume does not re-run triggers missed while a job was paused (REST ref p.230)" }
    Write-Host ""
    $exitCode = 0
    if (@($batches).Count -eq 0) {
        Write-Host "nothing to do: every matched job already has its snapshot state"
    } else {
        $prevMode = Enter-JrsPlanMode -Apply:$Apply
        try {
            if (-not $Apply) {
                Write-Host "[plan] nothing was written to $($jrs.ServerUrl); pass -Apply to restore (undo later with recover_run.ps1 -RunId <id> -Rollback -Apply)"
            } else {
                Assert-JrsWriteAllowed -Jrs $jrs -Method APPLY -Url $jrs.ServerUrl
                $run = New-JrsRun -Operation "jobs-restore" -Target $jrs -Mode apply `
                    -Plan @($batches | ForEach-Object { [pscustomobject]@{ Order = 1; Kind = "jobs-$($_.Action)"; Uri = "/rest_v2/jobs/$($_.Action)"; Action = "$($_.Action) jobs $($_.Ids -join ',')" } }) `
                    -Arguments @{ Snapshot = $Snapshot }
                try {
                    foreach ($b in $batches) {
                        $step = "jobs-$($b.Action):" + ($b.Ids -join ",")
                        $inverse = if ($b.Action -eq "pause") { "jobs-resume" } else { "jobs-pause" }
                        Write-JrsStep -Run $run -Step $step -State RUNNING -Compensation @{ type = $inverse; ids = @($b.Ids) }
                        $echo = @(Invoke-JrsJobBatch -Jrs $jrs -Action $b.Action -Ids $b.Ids)
                        Write-JrsStep -Run $run -Step $step -State SUCCEEDED -Detail "server acted on $($echo -join ',')"
                        Write-Host "OK: $($b.Action) $($echo -join ',')"
                    }
                    Complete-JrsRun -Run $run -Status SUCCEEDED
                    Write-Host "OK: restored job states (run $($run.RunId))"
                } catch {
                    Complete-JrsRun -Run $run -Status FAILED -ExitCode 4 -Error "$_"
                    Write-Host "FAILED (run $($run.RunId)): $_"
                    Write-Host "undo what was done with: recover_run.ps1 -RunId $($run.RunId) -Rollback -Apply"
                    $exitCode = 4
                }
            }
        } finally { Restore-JrsPlanMode $prevMode }
    }
    if ($unresolved.Count -and $exitCode -eq 0) {
        Write-Host "REVIEW BY HAND: $($unresolved.Count) snapshot job(s) could not be matched: $(($unresolved | ForEach-Object { "$($_.Id) $($_.Label) ($($_.Now))" }) -join '; ')"
        $exitCode = 2
    }
    exit $exitCode
}

if ($Action -in "pause", "resume", "restart", "state") {
    $where = "$($jrs.ServerUrl)$(if ($jrs.Env) { " [env $($jrs.Env)]" })"
    $targets = Resolve-JrsJobTargets -Jrs $jrs -Ids $ids -All:$All
    $labels = @{}
    foreach ($j in @(Get-JrsJobList -Jrs $jrs)) { $labels[[int]$j.Id] = $j.Label }
    $states = @($targets | ForEach-Object { Get-JrsJobState -Jrs $jrs -Id $_ })

    if ($Action -eq "state") {
        foreach ($s in $states) { Write-Output ("{0,-8} {1,-10} {2,-27} {3}" -f $s.Id, $s.Value, "$($s.NextFireTime)", "$($labels[[int]$s.Id])") }
        return
    }

    if ($Action -eq "restart") {
        $plan = @($states | ForEach-Object {
            if ($_.Value -eq "MISSING") { [pscustomobject]@{ Id = $_.Id; From = $_.Value; Act = "skip"; Reason = "job not found" } }
            else { [pscustomobject]@{ Id = $_.Id; From = $_.Value; Act = "restart"; Reason = "fires the job now" } } })
    } else {
        $plan = @(Get-JrsJobTransitionPlan -States $states -Action $Action)
    }
    Write-Host ""
    Write-Host "JOBS PLAN ($Action) on $where"
    foreach ($row in $plan) {
        Write-Host ("  [{0,-6}] {1,-10} -> {2,-8} {3}{4}" -f $row.Id, $row.From, $row.Act, "$($labels[[int]$row.Id])", $(if ($row.Reason) { "  ($($row.Reason))" } else { "" }))
    }
    if ($Action -eq "resume") { Write-Host "  note: resume does not re-run triggers missed while a job was paused (REST ref p.230)" }
    Write-Host ""
    $acting = [int[]]@($plan | Where-Object { $_.Act -eq $Action } | ForEach-Object { $_.Id })
    if ($acting.Count -eq 0) { Write-Host "nothing to do: no job needs to $Action"; return }

    $exitCode = 0
    $prevMode = Enter-JrsPlanMode -Apply:$Apply
    try {
        if (-not $Apply) {
            Write-Host "[plan] nothing was written to $($jrs.ServerUrl); pass -Apply to $Action $($acting.Count) job(s) (undo later with recover_run.ps1 -RunId <id> -Rollback -Apply)"
        } else {
            Assert-JrsWriteAllowed -Jrs $jrs -Method APPLY -Url $jrs.ServerUrl
            $run = New-JrsRun -Operation "jobs-$Action" -Target $jrs -Mode apply `
                -Plan @([pscustomobject]@{ Order = 1; Kind = "jobs-$Action"; Uri = "/rest_v2/jobs/$Action"; Action = "$Action jobs $($acting -join ',')" }) `
                -Arguments @{ Action = $Action; Id = ($acting -join ","); All = [bool]$All }
            $step = "jobs-${Action}:" + ($acting -join ",")
            try {
                if ($Action -eq "restart") {
                    Write-JrsStep -Run $run -Step $step -State RUNNING -Irreversible "restart fires the job now"
                } else {
                    $inverse = if ($Action -eq "pause") { "jobs-resume" } else { "jobs-pause" }
                    Write-JrsStep -Run $run -Step $step -State RUNNING -Compensation @{ type = $inverse; ids = @($acting) }
                }
                $echo = @(Invoke-JrsJobBatch -Jrs $jrs -Action $Action -Ids $acting)
                Write-JrsStep -Run $run -Step $step -State SUCCEEDED -Detail "server acted on $($echo -join ',')"
                Complete-JrsRun -Run $run -Status SUCCEEDED
                Write-Host "OK: $Action $($echo -join ',') (run $($run.RunId))"
            } catch {
                Write-JrsStep -Run $run -Step $step -State FAILED -Detail "$_"
                Complete-JrsRun -Run $run -Status FAILED -ExitCode 4 -Error "$_"
                Write-Host "FAILED (run $($run.RunId)): $_"
                Write-Host "undo what was done with: recover_run.ps1 -RunId $($run.RunId) -Rollback -Apply"
                $exitCode = 4
            }
        }
    } finally { Restore-JrsPlanMode $prevMode }
    exit $exitCode
}

switch ($Action) {
    "list" {
        $q = if ($ReportUri) { "?reportUnitURI=$ReportUri" } else { "" }
        $r = Invoke-JrsRest -Jrs $jrs -Method GET -Path "/rest_v2/jobs$q"
        if ($r.Code -eq "204") { Write-Host "No jobs found."; return }
        Assert-JrsOk -Response $r -Operation "list failed" | Out-Null
        Write-Output $r.Body          # to the output stream so callers can capture/pipe
        return
    }
    "get" {
        if (-not $Id1) { throw "-Id is required for get" }
        $r = Invoke-JrsRest -Jrs $jrs -Method GET -Path "/rest_v2/jobs/$Id1" -Accept $JOB_MEDIA
        Assert-JrsOk -Response $r -Operation "get failed" | Out-Null
        Write-Output $r.Body
        return
    }
    "delete" {
        if (-not $Id1) { throw "-Id is required for delete" }
        $r = Invoke-JrsRest -Jrs $jrs -Method DELETE -Path "/rest_v2/jobs/$Id1"
        Assert-JrsOk -Response $r -Operation "delete failed" | Out-Null
        Write-Host "OK ($($r.Code)): deleted job $Id1"
        return
    }
}

# --- create ---------------------------------------------------------------
if (-not $ReportUri) { throw "-ReportUri is required for create" }
if (-not $ReportUri.StartsWith("/")) { $ReportUri = "/$ReportUri" }
if (-not $Label) { $Label = "$(leaf $ReportUri) scheduled" }
if (-not $BaseOutputFilename) { $BaseOutputFilename = leaf $ReportUri }
if (-not $DestinationFolder) { $DestinationFolder = parent $ReportUri }
if (-not $StartType) { $StartType = if ($StartDate) { "at" } else { "now" } }
if ($StartType -eq "at" -and -not $StartDate) { throw "-StartDate is required when -StartType is 'at'" }

$simple = [ordered]@{
    timezone        = $Timezone
    startType       = if ($StartType -eq "now") { 1 } else { 2 }
    occurrenceCount = $OccurrenceCount
}
if ($StartType -eq "at") { $simple.startDate = $StartDate }
if ($RecurrenceInterval) {
    if (-not $RecurrenceIntervalUnit) { throw "-RecurrenceInterval needs -RecurrenceIntervalUnit (MINUTE|HOUR|DAY|WEEK)" }
    $simple.recurrenceInterval = $RecurrenceInterval
    $simple.recurrenceIntervalUnit = $RecurrenceIntervalUnit
}

$desc = [ordered]@{
    label   = $Label
    source  = [ordered]@{
        reportUnitURI = $ReportUri
        parameters    = if ($Parameters) { $Parameters } else { @{} }
    }
    trigger = [ordered]@{ simpleTrigger = $simple }
    baseOutputFilename    = $BaseOutputFilename
    outputFormats         = [ordered]@{ outputFormat = @($OutputFormats | ForEach-Object { $_.ToUpper() }) }
    repositoryDestination = [ordered]@{
        folderURI        = $DestinationFolder
        saveToRepository = $true
        overwriteFiles   = $true
    }
}
if ($MailTo) {
    $desc.mailNotification = [ordered]@{
        toAddresses    = @($MailTo)
        subject        = $Label
        messageText    = "Scheduled report: $Label"
        resultSendType = "SEND_ATTACHMENT"
    }
}

$jsonFile = [IO.Path]::GetTempFileName()
($desc | ConvertTo-Json -Depth 8) | Set-Content -Path $jsonFile -Encoding utf8
try {
    $r = Invoke-JrsRest -Jrs $jrs -Method PUT -Path "/rest_v2/jobs" `
        -ContentType $JOB_MEDIA -Accept $JOB_MEDIA -JsonFile $jsonFile
} finally {
    Remove-Item $jsonFile -ErrorAction SilentlyContinue
}

if ($r.Code -match '^2\d\d$') {
    $newId = try { ($r.Body | ConvertFrom-Json).id } catch { $null }
    Write-Host "OK ($($r.Code)): scheduled job '$Label' on $ReportUri$(if ($newId) { " (id $newId)" })"
    if ($r.Body) { Write-Host $r.Body }
} else {
    Write-Host "FAILED ($($r.Code))"
    if ($r.Body) { Write-Host $r.Body }
    throw "schedule failed with HTTP $($r.Code): $($r.Body)"
}
