<#
  Scheduler (jobs service) helpers for schedule_job.ps1. Dot-source it:
      . (Join-Path $PSScriptRoot "_jobs_common.ps1")

  NO param() block on purpose (gotcha G60): a dot-sourced param block re-binds
  the caller's variables. tests/dotsource.Tests.ps1 enforces it.

  !! An EMPTY job-id list on POST /rest_v2/jobs/pause or /jobs/resume acts on
  !! EVERY job in the scheduler (REST ref 10.0.0 p.229-231). Invoke-JrsJobBatch
  !! therefore refuses an empty list before sending anything, and "all jobs" is
  !! always expanded client-side (Resolve-JrsJobTargets -All) into explicit ids.
  Resume never re-runs triggers missed while a job was paused (ref p.230).

  Get-JrsJobList      - GET /rest_v2/jobs[?reportUnitURI=] -> @( { Id; Label;
                        ReportUnitURI; Owner } ); 204 -> @(). Body key: jobsummary
                        (verified on STAGE 10.0.0, 2026-11-18).
  Get-JrsJobState     - GET /rest_v2/jobs/{id}/state -> { Id; Value;
                        NextFireTime; PreviousFireTime }; Value is NORMAL |
                        EXECUTING | PAUSED | <error state>, or MISSING on 404.
  Resolve-JrsJobTargets - -Ids or -All (mutually exclusive) -> [int[]]; an empty
                        selection without -All throws.
  Get-JrsJobTransitionPlan - pure: state rows + pause|resume -> rows { Id; From;
                        Act (pause|resume|skip); Reason }.
  ConvertTo-JrsJobIdBody - [int[]] -> '{"jobId":[..]}' (one id stays an array).
  Invoke-JrsJobBatch  - POST /rest_v2/jobs/<pause|resume|restart> with explicit
                        ids -> [int[]] the ids the server echoed. Goes through
                        Invoke-JrsRest, so PLAN MODE / PROD GUARD apply.
#>

if (-not (Get-Command Invoke-JrsRest -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot "_jrs_common.ps1")
}

function Get-JrsJobList {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Jrs, [string]$ReportUri)
    $q = if ($ReportUri) { "?reportUnitURI=$ReportUri" } else { "" }
    $r = Invoke-JrsRest -Jrs $Jrs -Method GET -Path "/rest_v2/jobs$q"
    if ("$($r.Code)".Trim() -eq "204" -or -not $r.Body) { return @() }
    Assert-JrsOk -Response $r -Operation "job list failed" | Out-Null
    $items = @(($r.Body | ConvertFrom-Json).jobsummary)
    return @($items | Where-Object { $_ } | ForEach-Object {
        [pscustomobject]@{ Id = [int]$_.id; Label = $_.label; ReportUnitURI = $_.reportUnitURI; Owner = $_.owner }
    })
}

function Get-JrsJobState {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Jrs, [Parameter(Mandatory)][int]$Id)
    $r = Invoke-JrsRest -Jrs $Jrs -Method GET -Path "/rest_v2/jobs/$Id/state"
    $code = "$($r.Code)".Trim()
    if ($code -eq "404") { return [pscustomobject]@{ Id = $Id; Value = "MISSING"; NextFireTime = $null; PreviousFireTime = $null } }
    Assert-JrsOk -Response $r -Operation "job $Id state failed" | Out-Null
    $s = $r.Body | ConvertFrom-Json
    return [pscustomobject]@{ Id = $Id; Value = "$($s.value)"; NextFireTime = $s.nextFireTime; PreviousFireTime = $s.previousFireTime }
}

function Resolve-JrsJobTargets {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Jrs, [int[]]$Ids = @(), [switch]$All)
    $ids = @($Ids | Where-Object { $_ -ne $null })
    if ($All -and $ids.Count) { throw "-Id and -All are mutually exclusive" }
    if ($All) { return [int[]]@(Get-JrsJobList -Jrs $Jrs | ForEach-Object { $_.Id }) }
    if (-not $ids.Count) { throw "refusing to act on every job without -All (pass -Id <ids> or -All)" }
    return [int[]]$ids
}

function Get-JrsJobTransitionPlan {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$States, [Parameter(Mandatory)][ValidateSet("pause", "resume")][string]$Action)
    foreach ($s in $States) {
        $v = "$($s.Value)"
        $act = "skip"; $why = ""
        if ($Action -eq "pause") {
            switch ($v) {
                "NORMAL"    { $act = "pause" }
                "EXECUTING" { $act = "pause"; $why = "current run finishes; future triggers paused" }
                "PAUSED"    { $why = "already paused" }
                "MISSING"   { $why = "job not found" }
                default     { $why = "state $v" }
            }
        } else {
            switch ($v) {
                "PAUSED"    { $act = "resume" }
                "MISSING"   { $why = "job not found" }
                default     { $why = "not paused ($v)" }
            }
        }
        [pscustomobject]@{ Id = $s.Id; From = $v; Act = $act; Reason = $why }
    }
}

function ConvertTo-JrsJobIdBody {
    param([Parameter(Mandatory)][AllowEmptyCollection()][int[]]$Ids)
    return (ConvertTo-Json -InputObject @{ jobId = [int[]]$Ids } -Compress)
}

function Invoke-JrsJobBatch {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Jrs,
        [Parameter(Mandatory)][ValidateSet("pause", "resume", "restart")][string]$Action,
        [Parameter(Mandatory)][AllowEmptyCollection()][int[]]$Ids
    )
    # An empty list would act on EVERY job server-side: never send one.
    if (-not $Ids -or $Ids.Count -eq 0) { throw "empty job list: refusing POST /rest_v2/jobs/$Action (an empty list acts on every job)" }
    $f = [IO.Path]::GetTempFileName()
    try {
        [IO.File]::WriteAllText($f, (ConvertTo-JrsJobIdBody -Ids $Ids), (New-Object Text.UTF8Encoding($false)))
        $r = Invoke-JrsRest -Jrs $Jrs -Method POST -Path "/rest_v2/jobs/$Action" -ContentType "application/json" -JsonFile $f
    } finally { Remove-Item $f -ErrorAction SilentlyContinue }
    Assert-JrsOk -Response $r -Operation "jobs $Action failed" | Out-Null
    $echo = @()
    if ($r.Body) { try { $echo = @(($r.Body | ConvertFrom-Json).jobId) } catch { $echo = @() } }
    return [int[]]@($echo | Where-Object { $_ -ne $null })
}
