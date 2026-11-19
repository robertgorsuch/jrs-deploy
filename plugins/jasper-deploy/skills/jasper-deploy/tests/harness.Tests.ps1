# Recorded-server harness (Pester 3.x/4.x legacy syntax). Ported from jrsctl's
# ADR-0011: the scripts under test are the real ones, run in a SEPARATE
# PowerShell process against tests/mock_jrs.py replaying a recording taken from
# STAGE (tests/recordings/10.0.0-PRO). The mock logs every request, so a test can
# prove what the 2026-08-28 incident lacked: a plan-mode run issues no
# PUT/POST/DELETE, an apply-mode run journals compensations, and a rollback
# replays them. Needs python 3 and curl on PATH; no live server.

$here     = Split-Path -Parent $MyInvocation.MyCommand.Path
$scripts  = Join-Path (Split-Path -Parent $here) "scripts"
$mock     = Join-Path $here "mock_jrs.py"
$rec      = Join-Path $here "recordings/10.0.0-PRO"
$fixture  = Join-Path $here "fixtures/harness/harness_dashboard.json"
$jobsFix  = Join-Path $here "fixtures/jobs/jobs.json"      # synthetic scheduler: 101-104, 103 starts PAUSED
$dashUri  = "/reports/_smoke/harness/harness_dash"
. (Join-Path $scripts "_jrs_common.ps1")

$script:py  = Get-JrsPython
$script:exe = if (Get-Command pwsh -ErrorAction SilentlyContinue) { "pwsh" } else { "powershell" }
$script:haveTools = [bool](Get-Command $script:py -ErrorAction SilentlyContinue) -and (Test-Path $rec)

function Get-FreePort {
    $l = New-Object Net.Sockets.TcpListener([Net.IPAddress]::Loopback, 0); $l.Start()
    $p = $l.LocalEndpoint.Port; $l.Stop(); return $p
}
function Invoke-Skill([string]$Name, [string[]]$Arguments) {
    # a caller (smoke_test.ps1) may run Pester under $ErrorActionPreference = 'Stop';
    # with 2>&1 PS 5.1 would then turn the child's stderr into a terminating error
    $ErrorActionPreference = 'Continue'
    $out = & $script:exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $scripts $Name) @Arguments 2>&1 | Out-String
    return [pscustomobject]@{ Exit = $LASTEXITCODE; Out = $out }
}
function Read-Log { @(Get-Content $script:log -ErrorAction SilentlyContinue | Where-Object { "$_".Trim() } | ForEach-Object { $_ | ConvertFrom-Json }) }
function Clear-Log { Set-Content $script:log -Value "" -Encoding ascii -NoNewline }
function Get-Writes { @(Read-Log | Where-Object { $_.method -ne "GET" }) }

Describe "recorded-server harness (mock_jrs.py + STAGE recording)" {
    $script:port = Get-FreePort
    $script:tmp  = Join-Path ([IO.Path]::GetTempPath()) ("jrs_harness_" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force $script:tmp | Out-Null
    $script:log  = Join-Path $script:tmp "requests.jsonl"
    $script:runs = Join-Path $script:tmp "runs"
    $script:work = Join-Path $script:tmp "work"
    $script:src  = "http://127.0.0.1:$($script:port)/jasperserver-pro"   # same mock, two spellings:
    $script:dst  = "http://localhost:$($script:port)/jasperserver-pro"   # promote refuses identical URLs
    $script:proc = $null
    if ($script:haveTools) {
        [Environment]::SetEnvironmentVariable("JRS_RUNS_DIR", $script:runs)
        [Environment]::SetEnvironmentVariable("JRS_ALLOW_PROD_WRITE", $null)
        $sp = @{ FilePath = $script:py; ArgumentList = @("`"$mock`"", "--port", $script:port, "--recording", "`"$rec`"", "--log", "`"$($script:log)`"", "--jobs", "`"$jobsFix`"")
                 PassThru = $true; RedirectStandardOutput = (Join-Path $script:tmp "mock.out"); RedirectStandardError = (Join-Path $script:tmp "mock.err") }
        if (Test-JrsWindows) { $sp.WindowStyle = "Hidden" }   # -WindowStyle is not supported by pwsh on Linux/macOS
        $script:proc = Start-Process @sp
        $up = $false
        foreach ($i in 1..40) {
            try { $r = Invoke-WebRequest -UseBasicParsing -Uri "$($script:src)/rest_v2/serverInfo" -TimeoutSec 2; if ($r.StatusCode -eq 200) { $up = $true; break } } catch { Start-Sleep -Milliseconds 250 }
        }
        $script:haveTools = $up
    }
    $common = @("-ToServerUrl", $script:dst, "-ToUser", "u", "-ToPassword", "p", "-FromServerUrl", $script:src, "-FromUser", "u", "-FromPassword", "p", "-WorkDir", $script:work)
    $tgt = @("-ServerUrl", $script:dst, "-User", "u", "-Password", "p")

    It "mock replays the STAGE recording (serverInfo 10.0.0 PRO, dashboard present)" -Skip:(-not $script:haveTools) {
        $i = (Invoke-WebRequest -UseBasicParsing -Uri "$($script:src)/rest_v2/serverInfo").Content | ConvertFrom-Json
        $i.version | Should Be "10.0.0"
        (Invoke-WebRequest -UseBasicParsing -Uri "$($script:dst)/rest_v2/resources$dashUri").StatusCode | Should Be 200
    }

    It "promote.ps1 -Manifest (plan mode) exits 0 and issues GETs only" -Skip:(-not $script:haveTools) {
        Clear-Log
        $r = Invoke-Skill "promote.ps1" (@("-Manifest", $fixture) + $common)
        $r.Exit | Should Be 0
        $r.Out | Should Match 'PROMOTION PLAN'
        $r.Out | Should Match '\[plan\] nothing was written'
        (Get-Writes).Count | Should Be 0
        @(Read-Log).Count | Should BeGreaterThan 3
    }

    It "promote.ps1 -Manifest -WhatIf (legacy) also issues GETs only" -Skip:(-not $script:haveTools) {
        Clear-Log
        $r = Invoke-Skill "promote.ps1" (@("-Manifest", $fixture, "-WhatIf") + $common)
        $r.Exit | Should Be 0
        (Get-Writes).Count | Should Be 0
    }

    It "teardown_dashboard.ps1 (plan mode) issues GETs only" -Skip:(-not $script:haveTools) {
        Clear-Log
        $r = Invoke-Skill "teardown_dashboard.ps1" (@("-Uri", $dashUri, "-IncludeReports") + $tgt)
        $r.Exit | Should Be 0
        $r.Out | Should Match 'TEARDOWN PLAN'
        (Get-Writes).Count | Should Be 0
    }

    It "compose_dashboard.ps1 (plan mode) issues GETs only" -Skip:(-not $script:haveTools) {
        Clear-Log
        $r = Invoke-Skill "compose_dashboard.ps1" (@("-Manifest", $fixture, "-Replace", "-WorkDir", (Join-Path $script:work "compose_plan")) + $tgt)
        $r.Exit | Should Be 0
        $r.Out | Should Match 'COMPOSE PLAN'
        (Get-Writes).Count | Should Be 0
    }

    It "promote.ps1 -Manifest -Apply writes, journals compensations for every mutating step and exits 0" -Skip:(-not $script:haveTools) {
        Clear-Log
        $r = Invoke-Skill "promote.ps1" (@("-Manifest", $fixture, "-Apply") + $common)
        if ($r.Exit -ne 0) {   # diagnostics for CI: the child's tail + the mock's stderr
            Write-Host "    --- promote -Apply exit $($r.Exit); output tail ---"
            ($r.Out -split "`n" | Select-Object -Last 45) | ForEach-Object { Write-Host "    | $_" }
            Write-Host "    --- mock.err ---"; Get-Content (Join-Path $script:tmp "mock.err") -ErrorAction SilentlyContinue | Select-Object -Last 15 | ForEach-Object { Write-Host "    | $_" }
        }
        $r.Exit | Should Be 0
        $r.Out | Should Match 'OK: promoted 1 dashboard'
        $w = @(Get-Writes)
        Write-Host ("    writes: {0} -> {1}" -f $w.Count, (($w | ForEach-Object { $_.method + ' ' + $_.path + ' ' + $_.status }) -join '; '))
        @($w | Where-Object { $_.method -eq "DELETE" -and $_.path -like "*$dashUri" }).Count | Should BeGreaterThan 0
        @($w | Where-Object { $_.method -eq "POST" -and $_.path -like "/rest_v2/import*" }).Count | Should BeGreaterThan 0
        $runDir = Get-ChildItem $script:runs -Directory | Sort-Object Name -Descending | Select-Object -First 1
        $runDir | Should Not BeNullOrEmpty
        $run = Get-Content (Join-Path $runDir.FullName "run.json") -Raw | ConvertFrom-Json
        $run.operation | Should Be "promote"
        $run.status | Should Be "SUCCEEDED"
        $run.target.serverUrl | Should Be $script:dst
        (Get-Content (Join-Path $runDir.FullName "run.json") -Raw) | Should Not Match '"p"'
        $tr = @(Get-Content (Join-Path $runDir.FullName "transitions.jsonl") | Where-Object { $_ } | ForEach-Object { $_ | ConvertFrom-Json })
        # teardown (reimport), two tiles (reimport), compose delete (reimport): 4 compensations
        @($tr | Where-Object { $_.PSObject.Properties.Name -contains "compensation" -and $_.compensation }).Count | Should BeGreaterThan 3
        @($tr | Where-Object { $_.state -eq "FAILED" }).Count | Should Be 0
        $script:runId = $run.runId
    }

    It "recover_run.ps1 -Rollback (plan) lists the compensations and writes nothing" -Skip:(-not $script:haveTools) {
        Clear-Log
        $r = Invoke-Skill "recover_run.ps1" (@("-RunId", "latest", "-Rollback") + $tgt)
        $r.Exit | Should Be 0
        $r.Out | Should Match 'ROLLBACK PLAN'
        $r.Out | Should Match 'RE-IMPORT'
        (Get-Writes).Count | Should Be 0
    }

    It "recover_run.ps1 -Rollback -Apply replays them newest-first and exits 3 (ROLLED_BACK)" -Skip:(-not $script:haveTools) {
        Clear-Log
        $r = Invoke-Skill "recover_run.ps1" (@("-RunId", "latest", "-Rollback", "-Apply") + $tgt)
        $r.Exit | Should Be 3
        $r.Out | Should Match 'rollback ROLLED_BACK'
        $w = @(Get-Writes)
        $w.Count | Should BeGreaterThan 0
        @($w | Where-Object { $_.method -eq "POST" -and $_.path -like "/rest_v2/import*" }).Count | Should BeGreaterThan 2
        $run = Get-Content (Join-Path (Join-Path $script:runs $script:runId) "run.json") -Raw | ConvertFrom-Json
        $run.status | Should Be "ROLLED_BACK"
        $run.exitCode | Should Be 3
    }

    It "deploy_report.ps1 -Overwrite without -Apply never PUTs (plan) " -Skip:(-not $script:haveTools) {
        Clear-Log
        $jrxml = Join-Path $here "fixtures/harness/src/tile_a.jrxml"
        $r = Invoke-Skill "deploy_report.ps1" (@("-Jrxml", $jrxml, "-TargetUri", "/reports/_smoke/harness/tile_a", "-Overwrite", "-SkipLint") + $tgt)
        # compile needs the JR libs; without them the script throws BEFORE any request, which is also a pass for "no writes"
        ($r.Out -match 'DEPLOY PLAN' -or $r.Out -match 'jrLibDir|compile') | Should Be $true
        (Get-Writes).Count | Should Be 0
    }

    # --- relocate_resource.ps1 (copy / move) ------------------------------------
    $relSrc = "/reports/_smoke/relocate/src/r"; $relDstFolder = "/reports/_smoke/relocate/dst"
    function Set-MockResource([string]$Uri, [string]$Json) {
        Invoke-WebRequest -UseBasicParsing -Method Put -Uri "$($script:dst)/rest_v2/resources$Uri" -Body $Json -ContentType "application/json" | Out-Null
    }
    function Get-MockStatus([string]$Uri) {
        try { (Invoke-WebRequest -UseBasicParsing -Uri "$($script:dst)/rest_v2/resources$Uri").StatusCode } catch { [int]$_.Exception.Response.StatusCode }
    }
    $relArgs = @("-Source", $relSrc, "-TargetFolder", $relDstFolder) + $tgt

    It "relocate_resource.ps1 (plan mode) exits 0 and issues GETs only" -Skip:(-not $script:haveTools) {
        Set-MockResource $relSrc '{"label":"r"}'
        Set-MockResource $relDstFolder '{"label":"dst"}'
        Clear-Log
        $r = Invoke-Skill "relocate_resource.ps1" ($relArgs + "-Move")
        $r.Exit | Should Be 0
        $r.Out | Should Match 'RELOCATE PLAN'
        $r.Out | Should Match '\[plan\] nothing was written'
        (Get-Writes).Count | Should Be 0
    }

    It "relocate_resource.ps1 -Move -Apply moves the resource and journals a move-back" -Skip:(-not $script:haveTools) {
        Clear-Log
        $r = Invoke-Skill "relocate_resource.ps1" ($relArgs + @("-Move", "-Apply"))
        $r.Exit | Should Be 0
        @(Get-Writes | Where-Object { $_.method -eq "PUT" -and $_.path -like "/rest_v2/resources$relDstFolder*" }).Count | Should Be 1
        Get-MockStatus "$relDstFolder/r" | Should Be 200
        Get-MockStatus $relSrc | Should Be 404
        $runDir = Get-ChildItem $script:runs -Directory | Sort-Object Name -Descending | Select-Object -First 1
        (Get-Content (Join-Path $runDir.FullName "run.json") -Raw | ConvertFrom-Json).operation | Should Be "relocate"
        (Get-Content (Join-Path $runDir.FullName "transitions.jsonl") -Raw) | Should Match '"type":"move"'
    }

    It "relocate_resource.ps1 refuses a target that already exists (exit 2, no writes)" -Skip:(-not $script:haveTools) {
        Set-MockResource $relSrc '{"label":"r"}'          # "$relDstFolder/r" exists after the move above
        Clear-Log
        $r = Invoke-Skill "relocate_resource.ps1" ($relArgs + @("-Move", "-Apply"))
        $r.Exit | Should Be 2
        $r.Out | Should Match 'already exists'
        (Get-Writes).Count | Should Be 0
    }

    It "recover_run.ps1 -Rollback -Apply moves it back (exit 3)" -Skip:(-not $script:haveTools) {
        Invoke-WebRequest -UseBasicParsing -Method Delete -Uri "$($script:dst)/rest_v2/resources$relSrc" | Out-Null   # clear the re-seeded source
        Clear-Log
        $r = Invoke-Skill "recover_run.ps1" (@("-RunId", "latest", "-Rollback", "-Apply") + $tgt)
        $r.Exit | Should Be 3
        $r.Out | Should Match 'MOVE'
        Get-MockStatus $relSrc | Should Be 200
        Get-MockStatus "$relDstFolder/r" | Should Be 404
    }

    # --- schedule_job.ps1 pause / resume (mock scheduler from fixtures/jobs) -----
    function Get-MockJobState([int]$JobId) {
        try { ((Invoke-WebRequest -UseBasicParsing -Uri "$($script:dst)/rest_v2/jobs/$JobId/state").Content | ConvertFrom-Json).value } catch { "HTTP-ERR" }
    }
    function Get-JobBatchWrites { @(Get-Writes | Where-Object { $_.path -match '^/rest_v2/jobs/(pause|resume|restart)' }) }

    It "schedule_job.ps1 -Action pause (plan mode) issues GETs only" -Skip:(-not $script:haveTools) {
        Clear-Log
        $r = Invoke-Skill "schedule_job.ps1" (@("-Action", "pause", "-Id", "101,103") + $tgt)
        $r.Exit | Should Be 0
        $r.Out | Should Match 'JOBS PLAN'
        $r.Out | Should Match '\[plan\] nothing was written'
        (Get-Writes).Count | Should Be 0
    }

    It "schedule_job.ps1 -Action pause -Apply pauses only the NORMAL job" -Skip:(-not $script:haveTools) {
        Clear-Log
        $r = Invoke-Skill "schedule_job.ps1" (@("-Action", "pause", "-Id", "101,103", "-Apply") + $tgt)
        $r.Exit | Should Be 0
        $w = @(Get-Writes)
        $w.Count | Should Be 1
        $w[0].path | Should Match '^/rest_v2/jobs/pause'
        $w[0].jobIds | Should Be 1                          # 103 was already PAUSED
        Get-MockJobState 101 | Should Be "PAUSED"
    }

    It "schedule_job.ps1 -Action pause -Apply on an already-paused job sends nothing" -Skip:(-not $script:haveTools) {
        Clear-Log
        $r = Invoke-Skill "schedule_job.ps1" (@("-Action", "pause", "-Id", "103", "-Apply") + $tgt)
        $r.Exit | Should Be 0
        $r.Out | Should Match 'nothing to do'
        (Get-Writes).Count | Should Be 0
    }

    It "schedule_job.ps1 -Action pause -Apply without -Id or -All fails and sends nothing" -Skip:(-not $script:haveTools) {
        Clear-Log
        $r = Invoke-Skill "schedule_job.ps1" (@("-Action", "pause", "-Apply") + $tgt)
        $r.Exit | Should Not Be 0
        $r.Out | Should Match 'without -All'
        (Get-Writes).Count | Should Be 0
    }

    It "schedule_job.ps1 -Action resume -Id 101 -Apply resumes it" -Skip:(-not $script:haveTools) {
        Clear-Log
        $r = Invoke-Skill "schedule_job.ps1" (@("-Action", "resume", "-Id", "101", "-Apply") + $tgt)
        $r.Exit | Should Be 0
        $r.Out | Should Match 'missed'
        Get-MockJobState 101 | Should Be "NORMAL"
    }

    It "schedule_job.ps1 -Action pause -All -Apply sends an explicit list (never empty)" -Skip:(-not $script:haveTools) {
        Clear-Log
        $r = Invoke-Skill "schedule_job.ps1" (@("-Action", "pause", "-All", "-Apply") + $tgt)
        $r.Exit | Should Be 0
        $w = @(Get-JobBatchWrites)
        $w.Count | Should Be 1
        $w[0].jobIds | Should Be 3                          # 101, 102, 104 (103 already paused)
        foreach ($j in 101, 102, 103, 104) { Get-MockJobState $j | Should Be "PAUSED" }
    }

    It "recover_run.ps1 -Rollback -Apply resumes only what the pause run paused" -Skip:(-not $script:haveTools) {
        Clear-Log
        $r = Invoke-Skill "recover_run.ps1" (@("-RunId", "latest", "-Rollback", "-Apply") + $tgt)
        $r.Exit | Should Be 3
        $r.Out | Should Match 'RESUME'
        foreach ($j in 101, 102, 104) { Get-MockJobState $j | Should Be "NORMAL" }
        Get-MockJobState 103 | Should Be "PAUSED"           # paused before the run: rollback leaves it paused
    }

    It "schedule_job.ps1 -Action state prints states and writes nothing" -Skip:(-not $script:haveTools) {
        Clear-Log
        $r = Invoke-Skill "schedule_job.ps1" (@("-Action", "state", "-Id", "101,103") + $tgt)
        $r.Exit | Should Be 0
        $r.Out | Should Match '101\s+NORMAL'
        $r.Out | Should Match '103\s+PAUSED'
        (Get-Writes).Count | Should Be 0
    }

    It "schedule_job.ps1 -Action snapshot writes a file and nothing to the server" -Skip:(-not $script:haveTools) {
        Clear-Log
        $script:snap = Join-Path $script:tmp "jobs-snapshot.json"
        $r = Invoke-Skill "schedule_job.ps1" (@("-Action", "snapshot", "-Out", $script:snap) + $tgt)
        $r.Exit | Should Be 0
        (Get-Writes).Count | Should Be 0
        $doc = Get-Content $script:snap -Raw | ConvertFrom-Json
        @($doc.jobs).Count | Should Be 4
        (Get-Content $script:snap -Raw) | Should Not Match '"p"'
    }

    It "schedule_job.ps1 -Action restore -Apply puts the snapshot states back" -Skip:(-not $script:haveTools) {
        Invoke-Skill "schedule_job.ps1" (@("-Action", "pause", "-All", "-Apply") + $tgt) | Out-Null
        foreach ($j in 101, 102, 103, 104) { Get-MockJobState $j | Should Be "PAUSED" }
        Clear-Log
        $r = Invoke-Skill "schedule_job.ps1" (@("-Action", "restore", "-Snapshot", $script:snap, "-Apply") + $tgt)
        $r.Exit | Should Be 0
        $w = @(Get-JobBatchWrites)
        $w.Count | Should Be 1
        $w[0].path | Should Match '^/rest_v2/jobs/resume'
        $w[0].jobIds | Should Be 3
        foreach ($j in 101, 102, 104) { Get-MockJobState $j | Should Be "NORMAL" }
        Get-MockJobState 103 | Should Be "PAUSED"
    }

    It "schedule_job.ps1 restore refuses a snapshot from another server (exit 2, no writes)" -Skip:(-not $script:haveTools) {
        $other = Join-Path $script:tmp "jobs-snapshot-other.json"
        $doc = Get-Content $script:snap -Raw | ConvertFrom-Json
        $doc.server = "http://elsewhere.example:8080/jasperserver-pro"
        [IO.File]::WriteAllText($other, ($doc | ConvertTo-Json -Depth 6))
        Invoke-Skill "schedule_job.ps1" (@("-Action", "pause", "-Id", "101", "-Apply") + $tgt) | Out-Null
        Clear-Log
        $r = Invoke-Skill "schedule_job.ps1" (@("-Action", "restore", "-Snapshot", $other, "-Apply") + $tgt)
        $r.Exit | Should Be 2
        $r.Out | Should Match 'AllowOtherServer'
        (Get-Writes).Count | Should Be 0
        Invoke-Skill "schedule_job.ps1" (@("-Action", "resume", "-Id", "101", "-Apply") + $tgt) | Out-Null
    }

    It "schedule_job.ps1 -Action restart -All is refused and sends nothing" -Skip:(-not $script:haveTools) {
        Clear-Log
        $r = Invoke-Skill "schedule_job.ps1" (@("-Action", "restart", "-All", "-Apply") + $tgt)
        $r.Exit | Should Not Be 0
        $r.Out | Should Match 'restart -All'
        (Get-Writes).Count | Should Be 0
    }

    if ($script:proc) { try { Stop-Process -Id $script:proc.Id -Force -ErrorAction SilentlyContinue } catch { } }
    [Environment]::SetEnvironmentVariable("JRS_RUNS_DIR", $null)
    Remove-Item $script:tmp -Recurse -Force -ErrorAction SilentlyContinue
}
