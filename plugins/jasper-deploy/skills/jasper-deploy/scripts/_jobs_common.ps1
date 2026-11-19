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
  New-JrsJobSnapshot  - read-only: every job + state to JSON (default
                        out/job-snapshots/<env|host-port>-<ts>.json) -> path.
  Get-JrsJobRestorePlan - pure: snapshot vs current -> rows { Id; Label;
                        CurrentLabel; Was; Now; Act (pause|resume|none|unresolved);
                        MatchedBy }. An id match needs the label + report to agree.
  Get-JrsJobRestartPlan - pure: restart only jobs in an error state (the
                        endpoint makes a one-shot copy of each failed job).
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
    # Fire times are taken from the raw body: pwsh's ConvertFrom-Json turns
    # ISO-8601 strings into DateTime (dropping the server's offset), while
    # Windows PowerShell 5.1 keeps them as text. The raw text is identical on both.
    return [pscustomobject]@{ Id = $Id; Value = "$($s.value)"; NextFireTime = (Get-JrsJsonRawString $r.Body "nextFireTime"); PreviousFireTime = (Get-JrsJsonRawString $r.Body "previousFireTime") }
}

function Get-JrsJsonRawString([string]$Json, [string]$Name) {
    # The string value of the first "<Name>": "..." in $Json exactly as sent, or
    # $null when absent / not a string. For flat bodies only (no nested match).
    $m = [regex]::Match("$Json", '"' + [regex]::Escape($Name) + '"\s*:\s*"((?:[^"\\]|\\.)*)"')
    if ($m.Success) { return $m.Groups[1].Value }
    return $null
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
    # Never trust the echo alone: on STAGE (JRS 10.0, 2026-11-19) /jobs/resume
    # answered 200 {"jobId":[id]} while the job stayed PAUSED. Re-read every
    # job's state; pause must end PAUSED, resume must end not-PAUSED (and the
    # job must still exist). restart is not checked: it creates one-shot copies
    # and leaves the original jobs' states alone.
    if ($Action -in "pause", "resume") {
        $bad = @()
        foreach ($id in $Ids) {
            $v = "$((Get-JrsJobState -Jrs $Jrs -Id $id).Value)"
            $ok = if ($Action -eq "pause") { $v -eq "PAUSED" } else { $v -notin "PAUSED", "MISSING", "" }
            if (-not $ok) { $bad += "$id ($v)" }
        }
        if ($bad.Count) { throw "jobs $Action did not take effect for $($bad.Count) of $($Ids.Count) job(s): $($bad -join ', ') -- the server answered HTTP $($r.Code) and echoed the ids, but the state did not change" }
    }
    return [int[]]@($echo | Where-Object { $_ -ne $null })
}

function New-JrsJobSnapshot {
    # Read-only (allowed on PROD): every job's id/label/report/owner/state to a
    # JSON file. No credentials are written. Returns the path.
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Jrs, [string]$Path)
    if (-not $Path) {
        $u = [uri]$Jrs.ServerUrl
        $tag = if ($Jrs.Env) { "$($Jrs.Env)" } else { "$($u.Host)-$($u.Port)" }
        $dir = Join-Path $PSScriptRoot "../out/job-snapshots"
        $Path = Join-Path $dir ("{0}-{1}.json" -f ($tag -replace '[^0-9A-Za-z_.-]', '_'), (Get-Date -Format "yyyyMMdd-HHmmss"))
    }
    $parent = Split-Path -Parent $Path
    if ($parent) { New-Item -ItemType Directory -Force $parent | Out-Null }
    $jobs = @(Get-JrsJobList -Jrs $Jrs | ForEach-Object {
        $s = Get-JrsJobState -Jrs $Jrs -Id $_.Id
        [ordered]@{ id = $_.Id; label = $_.Label; reportUnitURI = $_.ReportUnitURI; owner = $_.Owner; state = $s.Value; nextFireTime = $s.NextFireTime }
    })
    $doc = [ordered]@{ server = $Jrs.ServerUrl; env = $Jrs.Env; takenAt = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ"); jobs = $jobs }
    [IO.File]::WriteAllText($Path, (ConvertTo-Json -InputObject $doc -Depth 6), (New-Object Text.UTF8Encoding($false)))
    return $Path
}

function Get-JrsJobRestorePlan {
    # Pure. Compare a snapshot with the current jobs ({ Id; Label; ReportUnitURI;
    # Value }). An id match counts only when the label AND reportUnitURI agree
    # too (after an export/import rebuild an id can belong to another job);
    # otherwise match by label + reportUnitURI, only when exactly one current job
    # matches. EXECUTING counts as running (NORMAL). Snapshot PAUSED / now running
    # -> pause (the 7.5.1 -> 7.9.2+ upgrade resumes paused jobs, KB); snapshot
    # running / now PAUSED -> resume. Current jobs absent from the snapshot are
    # left alone and not listed.
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Snapshot, [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Current)
    function norm([string]$v) { if ($v -eq "EXECUTING") { "NORMAL" } else { $v } }
    foreach ($s in @($Snapshot.jobs | Where-Object { $_ })) {
        $by = "id"
        $c = @($Current | Where-Object { [int]$_.Id -eq [int]$s.id -and $_.Label -eq $s.label -and $_.ReportUnitURI -eq $s.reportUnitURI })
        if ($c.Count -ne 1) {
            $by = "label+uri"
            $c = @($Current | Where-Object { $_.Label -eq $s.label -and $_.ReportUnitURI -eq $s.reportUnitURI })
        }
        if ($c.Count -ne 1) {
            [pscustomobject]@{ Id = [int]$s.id; Label = $s.label; CurrentLabel = $null; Was = "$($s.state)"; Now = $(if ($c.Count) { "AMBIGUOUS" } else { "MISSING" }); Act = "unresolved"; MatchedBy = "" }
            continue
        }
        $now = "$($c[0].Value)"; $was = "$($s.state)"
        $act = if ((norm $was) -eq "PAUSED" -and (norm $now) -eq "NORMAL") { "pause" } elseif ((norm $was) -eq "NORMAL" -and (norm $now) -eq "PAUSED") { "resume" } else { "none" }
        [pscustomobject]@{ Id = [int]$c[0].Id; Label = $s.label; CurrentLabel = $c[0].Label; Was = $was; Now = $now; Act = $act; MatchedBy = $by }
    }
}

function Get-JrsJobRestartPlan {
    # Pure. POST /jobs/restart is "Restarting Failed Jobs" (REST ref p.231-232):
    # each listed job gets an immediate one-shot copy. Only jobs in an error
    # state qualify; NORMAL / EXECUTING / PAUSED / MISSING are skipped.
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$States)
    foreach ($st in $States) {
        $v = "$($st.Value)"
        if ($v -in "NORMAL", "EXECUTING", "PAUSED") { [pscustomobject]@{ Id = $st.Id; From = $v; Act = "skip"; Reason = "not failed ($v); restart is for failed jobs" } }
        elseif ($v -eq "MISSING") { [pscustomobject]@{ Id = $st.Id; From = $v; Act = "skip"; Reason = "job not found" } }
        else { [pscustomobject]@{ Id = $st.Id; From = $v; Act = "restart"; Reason = "creates a one-shot copy that runs now" } }
    }
}
