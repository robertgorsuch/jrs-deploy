# Pester 3.x/4.x (legacy `Should Be` syntax) tests for scripts\_jobs_common.ps1.
# No live server: Invoke-JrsRest is mocked, or the request targets 127.0.0.1:9.
# Under Pester 3.4 a Mock inside an It persists for the rest of its Describe /
# Context, so tests that need different mock bodies sit in their own Context.

. "$PSScriptRoot/../scripts/_jobs_common.ps1"     # dot-sources _jrs_common.ps1 when needed
$ErrorActionPreference = 'Continue'

$script:Dead = [pscustomobject]@{ ServerUrl = "http://127.0.0.1:9/jasperserver-pro"; User = "u"; Password = "p"; Env = $null; IsProd = $false }
$script:Prod = [pscustomobject]@{ ServerUrl = "http://127.0.0.1:9/jasperserver-pro"; User = "u"; Password = "p"; Env = "prod"; IsProd = $true }

Describe "job-id body" {
    It "keeps a single id as an array" { ConvertTo-JrsJobIdBody -Ids @(5) | Should Be '{"jobId":[5]}' }
    It "keeps order"                   { ConvertTo-JrsJobIdBody -Ids @(7,3) | Should Be '{"jobId":[7,3]}' }
}

Describe "Invoke-JrsJobBatch" {
    Context "empty list" {
        It "never sends an empty list (an empty body pauses ALL jobs server-side)" {
            Mock Invoke-JrsRest { throw "must not be called" }
            { Invoke-JrsJobBatch -Jrs $script:Dead -Action pause -Ids @() } | Should Throw "empty job list"
            Assert-MockCalled Invoke-JrsRest -Times 0
        }
    }
    Context "one id" {
        It "POSTs to /rest_v2/jobs/pause" {
            Mock Invoke-JrsRest { [pscustomobject]@{ Code = "200"; Body = '{"jobId":[5]}' } }
            (Invoke-JrsJobBatch -Jrs $script:Dead -Action pause -Ids @(5)) | Should Be 5
            Assert-MockCalled Invoke-JrsRest -Times 1 -ParameterFilter { $Method -eq "POST" -and $Path -eq "/rest_v2/jobs/pause" }
        }
    }
    Context "server error" {
        It "throws on a non-2xx answer" {
            Mock Invoke-JrsRest { [pscustomobject]@{ Code = "500"; Body = 'boom' } }
            { Invoke-JrsJobBatch -Jrs $script:Dead -Action resume -Ids @(5) } | Should Throw
        }
    }
    Context "write guard" {
        It "refuses a prod target without JRS_ALLOW_PROD_WRITE (PROD GUARD, no request)" {
            [Environment]::SetEnvironmentVariable("JRS_ALLOW_PROD_WRITE", $null)
            $Global:JrsPlanMode = $null
            { Invoke-JrsJobBatch -Jrs $script:Prod -Action pause -Ids @(5) } | Should Throw "PROD GUARD"
        }
        It "is refused in plan mode" {
            $Global:JrsPlanMode = $true
            try { { Invoke-JrsJobBatch -Jrs $script:Dead -Action pause -Ids @(5) } | Should Throw "PLAN MODE" }
            finally { $Global:JrsPlanMode = $null }
        }
    }
}

Describe "Resolve-JrsJobTargets" {
    It "refuses an empty selection without -All" { { Resolve-JrsJobTargets -Jrs $script:Dead -Ids @() } | Should Throw "without -All" }
    It "rejects -Id together with -All"          { { Resolve-JrsJobTargets -Jrs $script:Dead -Ids @(1) -All } | Should Throw "mutually exclusive" }
    It "passes explicit ids through"             { (Resolve-JrsJobTargets -Jrs $script:Dead -Ids @(4, 2)) -join "," | Should Be "4,2" }
    Context "-All" {
        It "expands -All to every listed job id" {
            Mock Get-JrsJobList { @([pscustomobject]@{ Id = 101 }, [pscustomobject]@{ Id = 102 }) }
            (Resolve-JrsJobTargets -Jrs $script:Dead -All) -join "," | Should Be "101,102"
        }
    }
}

Describe "Get-JrsJobTransitionPlan" {
    $s = @([pscustomobject]@{Id=1;Value="NORMAL"}, [pscustomobject]@{Id=2;Value="PAUSED"},
           [pscustomobject]@{Id=3;Value="EXECUTING"}, [pscustomobject]@{Id=4;Value="MISSING"})
    It "pauses NORMAL and EXECUTING only; skips already-paused" {
        $p = Get-JrsJobTransitionPlan -States $s -Action pause
        (@($p | Where-Object Act -eq "pause").Id -join ",") | Should Be "1,3"
        ($p | Where-Object Id -eq 2).Reason | Should Be "already paused"
        ($p | Where-Object Id -eq 4).Act | Should Be "skip"
    }
    It "resumes PAUSED only" {
        (@(Get-JrsJobTransitionPlan -States $s -Action resume | Where-Object Act -eq "resume").Id -join ",") | Should Be "2"
    }
}

Describe "Get-JrsJobList" {
    Context "204" {
        It "returns an empty array when there are no jobs" {
            Mock Invoke-JrsRest { [pscustomobject]@{ Code = "204"; Body = "" } }
            @(Get-JrsJobList -Jrs $script:Dead).Count | Should Be 0
        }
    }
    Context "one job" {
        It "returns one item for a single-job body (PS 5.1 unwrap)" {
            Mock Invoke-JrsRest { [pscustomobject]@{ Code = "200"; Body = '{"jobsummary":[{"id":7,"label":"t_job_a","reportUnitURI":"/reports/t/r1","owner":"u|org","state":{"value":"NORMAL"}}]}' } }
            $l = @(Get-JrsJobList -Jrs $script:Dead)
            $l.Count | Should Be 1
            $l[0].Id | Should Be 7
            $l[0].ReportUnitURI | Should Be "/reports/t/r1"
        }
        It "filters by report when -ReportUri is given" {
            Mock Invoke-JrsRest { [pscustomobject]@{ Code = "204"; Body = "" } }
            Get-JrsJobList -Jrs $script:Dead -ReportUri "/reports/t/r1" | Out-Null
            Assert-MockCalled Invoke-JrsRest -Times 1 -ParameterFilter { $Path -eq "/rest_v2/jobs?reportUnitURI=/reports/t/r1" }
        }
    }
}

Describe "Get-JrsJobState" {
    Context "found" {
        It "maps the state body" {
            Mock Invoke-JrsRest { [pscustomobject]@{ Code = "200"; Body = '{"nextFireTime":"2030-01-01T00:00:00-08:00","value":"PAUSED"}' } }
            $s = Get-JrsJobState -Jrs $script:Dead -Id 7
            $s.Id | Should Be 7
            $s.Value | Should Be "PAUSED"
            $s.NextFireTime | Should Be "2030-01-01T00:00:00-08:00"
        }
    }
    Context "missing" {
        It "reports MISSING on 404" {
            Mock Invoke-JrsRest { [pscustomobject]@{ Code = "404"; Body = '{"errorCode":"resource.not.found"}' } }
            (Get-JrsJobState -Jrs $script:Dead -Id 7).Value | Should Be "MISSING"
        }
    }
}

Describe "Get-JrsJobRestorePlan" {
    function Snap($jobs) { [pscustomobject]@{ jobs = @($jobs) } }
    function SJ($id, $state, $label = "t_job_a", $uri = "/reports/t/r1") { [pscustomobject]@{ id = $id; label = $label; reportUnitURI = $uri; state = $state } }
    function CJ($id, $value, $label = "t_job_a", $uri = "/reports/t/r1") { [pscustomobject]@{ Id = $id; Label = $label; ReportUnitURI = $uri; Value = $value } }

    It "re-pauses a job that was PAUSED and is NORMAL now (matched by id)" {
        $p = @(Get-JrsJobRestorePlan -Snapshot (Snap (SJ 101 "PAUSED")) -Current @(CJ 101 "NORMAL"))
        $p.Count | Should Be 1
        $p[0].Act | Should Be "pause"
        $p[0].MatchedBy | Should Be "id"
    }
    It "resumes a job that was NORMAL and is PAUSED now" {
        (@(Get-JrsJobRestorePlan -Snapshot (Snap (SJ 101 "NORMAL")) -Current @(CJ 101 "PAUSED")))[0].Act | Should Be "resume"
    }
    It "leaves a job alone when its state already matches" {
        (@(Get-JrsJobRestorePlan -Snapshot (Snap (SJ 101 "PAUSED")) -Current @(CJ 101 "PAUSED")))[0].Act | Should Be "none"
    }
    It "falls back to label + report uri when the id changed" {
        $p = @(Get-JrsJobRestorePlan -Snapshot (Snap (SJ 101 "PAUSED")) -Current @(CJ 555 "NORMAL"))
        $p[0].Act | Should Be "pause"
        $p[0].Id | Should Be 555
        $p[0].MatchedBy | Should Be "label+uri"
    }
    It "marks an ambiguous label + uri match unresolved" {
        $p = @(Get-JrsJobRestorePlan -Snapshot (Snap (SJ 101 "PAUSED")) -Current @((CJ 555 "NORMAL"), (CJ 556 "NORMAL")))
        $p[0].Act | Should Be "unresolved"
    }
    It "marks a job that no longer exists unresolved" {
        (@(Get-JrsJobRestorePlan -Snapshot (Snap (SJ 101 "PAUSED")) -Current @()))[0].Act | Should Be "unresolved"
    }
    It "does not list current jobs that are not in the snapshot" {
        $p = @(Get-JrsJobRestorePlan -Snapshot (Snap (SJ 101 "NORMAL")) -Current @((CJ 101 "NORMAL"), (CJ 999 "PAUSED" "other" "/reports/x")))
        $p.Count | Should Be 1
        $p[0].Id | Should Be 101
    }
}

Describe "final-review fixes: restore matching" {
    function Snap($jobs) { [pscustomobject]@{ jobs = @($jobs) } }
    function SJ($id, $state, $label = "t_job_a", $uri = "/reports/t/r1") { [pscustomobject]@{ id = $id; label = $label; reportUnitURI = $uri; state = $state } }
    function CJ($id, $value, $label = "t_job_a", $uri = "/reports/t/r1") { [pscustomobject]@{ Id = $id; Label = $label; ReportUnitURI = $uri; Value = $value } }

    It "does not trust an id match whose label/report differ (id reused after a rebuild)" {
        $p = @(Get-JrsJobRestorePlan -Snapshot (Snap (SJ 101 "PAUSED")) -Current @(CJ 101 "NORMAL" "other" "/reports/x"))
        $p[0].Act | Should Be "unresolved"
    }
    It "falls back to label + report when the id now belongs to another job" {
        $p = @(Get-JrsJobRestorePlan -Snapshot (Snap (SJ 101 "PAUSED")) -Current @((CJ 101 "NORMAL" "other" "/reports/x"), (CJ 555 "NORMAL")))
        $p[0].Id | Should Be 555
        $p[0].Act | Should Be "pause"
        $p[0].MatchedBy | Should Be "label+uri"
    }
    It "reports the current job's label" {
        $p = @(Get-JrsJobRestorePlan -Snapshot (Snap (SJ 101 "PAUSED")) -Current @((CJ 555 "NORMAL")))
        $p[0].CurrentLabel | Should Be "t_job_a"
    }
    It "treats EXECUTING as running (re-pauses a job the upgrade resumed and that is running now)" {
        (@(Get-JrsJobRestorePlan -Snapshot (Snap (SJ 101 "PAUSED")) -Current @(CJ 101 "EXECUTING")))[0].Act | Should Be "pause"
    }
}

Describe "final-review fixes: restart only failed jobs" {
    $s = @([pscustomobject]@{Id=1;Value="NORMAL"}, [pscustomobject]@{Id=2;Value="PAUSED"}, [pscustomobject]@{Id=3;Value="EXECUTING"},
           [pscustomobject]@{Id=4;Value="MISSING"}, [pscustomobject]@{Id=5;Value="ERROR"})
    It "plans a restart only for jobs in an error state" {
        $p = @(Get-JrsJobRestartPlan -States $s)
        (@($p | Where-Object Act -eq "restart").Id -join ",") | Should Be "5"
        ($p | Where-Object Id -eq 1).Reason | Should Match "not failed"
    }
}
