# Pester 3.x/4.x (legacy `Should Be` syntax) tests for scripts\relocate_resource.ps1
# prechecks and the 'move' compensation in scripts\_jrs_run.ps1. No live server:
# the script is dot-sourced (its main block is guarded) and every server-facing
# helper is mocked. The end-to-end copy/move/rollback runs in harness.Tests.ps1.

. "$PSScriptRoot/../scripts/relocate_resource.ps1"   # also dot-sources _jrs_common.ps1 (+ _jrs_run.ps1)
$ErrorActionPreference = 'Continue'

$script:Dead = [pscustomobject]@{ ServerUrl = "http://127.0.0.1:9/jasperserver-pro"; User = "u"; Password = "p"; Env = $null; IsProd = $false }

Describe "Get-JrsRelocatePlan prechecks" {
    Mock Test-JrsIsFolder { $false }

    It "refuses a move onto an existing target without -Overwrite" {
        Mock Test-JrsResource { $true }                      # source, target and folder all exist
        Mock Get-JrsDashboardsReferencing { @() }
        $p = Get-JrsRelocatePlan -Jrs $script:Dead -Source "/reports/a/r" -TargetFolder "/reports/b" -Move
        $p.Ok | Should Be $false
        ($p.Problems -join ";") | Should Match "already exists"
    }
    It "refuses moving a report a dashboard uses" {
        Mock Test-JrsResource { param($Jrs, $Uri) $Uri -ne "/reports/b/r" }
        Mock Get-JrsDashboardsReferencing { @("/reports/a/dash") }
        $p = Get-JrsRelocatePlan -Jrs $script:Dead -Source "/reports/a/r" -TargetFolder "/reports/b" -Move
        $p.Ok | Should Be $false
        ($p.Problems -join ";") | Should Match "/reports/a/dash"
    }
    It "refuses a same-folder relocate as a no-op, after normalizing" {
        Mock Test-JrsResource { $true }
        $p = Get-JrsRelocatePlan -Jrs $script:Dead -Source "reports/a/r" -TargetFolder "/reports/a/"
        $p.Ok | Should Be $false
        ($p.Problems -join ";") | Should Match "no-op"
    }
    It "refuses -Move with -Overwrite" {
        Mock Test-JrsResource { $true }
        Mock Get-JrsDashboardsReferencing { @() }
        $p = Get-JrsRelocatePlan -Jrs $script:Dead -Source "/reports/a/r" -TargetFolder "/reports/b" -Move -Overwrite
        $p.Ok | Should Be $false
        ($p.Problems -join ";") | Should Match "not supported"
    }
    It "refuses a missing source" {
        Mock Test-JrsResource { param($Jrs, $Uri) $Uri -ne "/reports/a/r" }
        $p = Get-JrsRelocatePlan -Jrs $script:Dead -Source "/reports/a/r" -TargetFolder "/reports/b"
        $p.Ok | Should Be $false
        ($p.Problems -join ";") | Should Match "not found"
    }
    Context "folder source" {   # own Context: under Pester 3.4 a Mock inside an It persists for the rest of its block
        It "refuses a folder source (v1 relocates single resources only)" {
            Mock Test-JrsResource { param($Jrs, $Uri) $Uri -ne "/reports/b/f" }
            Mock Test-JrsIsFolder { $true }
            $p = Get-JrsRelocatePlan -Jrs $script:Dead -Source "/reports/a/f" -TargetFolder "/reports/b"
            $p.Ok | Should Be $false
            ($p.Problems -join ";") | Should Match "is a folder"
        }
    }
    It "refuses a missing target folder unless -CreateFolders" {
        Mock Test-JrsResource { param($Jrs, $Uri) $Uri -eq "/reports/a/r" }
        $p = Get-JrsRelocatePlan -Jrs $script:Dead -Source "/reports/a/r" -TargetFolder "/reports/new"
        ($p.Problems -join ";") | Should Match "does not exist"
        (Get-JrsRelocatePlan -Jrs $script:Dead -Source "/reports/a/r" -TargetFolder "/reports/new" -CreateFolders).Ok | Should Be $true
    }
    It "plans a copy to <folder>/<leaf>" {
        Mock Test-JrsResource { param($Jrs, $Uri) $Uri -ne "/reports/b/r" }
        $p = Get-JrsRelocatePlan -Jrs $script:Dead -Source "/reports/a/r" -TargetFolder "/reports/b"
        $p.Ok | Should Be $true
        $p.Target | Should Be "/reports/b/r"
        $p.TargetExists | Should Be $false
    }
    It "allows a copy over an existing target with -Overwrite and reports TargetExists" {
        Mock Test-JrsResource { $true }
        $p = Get-JrsRelocatePlan -Jrs $script:Dead -Source "/reports/a/r" -TargetFolder "/reports/b" -Overwrite
        $p.Ok | Should Be $true
        $p.TargetExists | Should Be $true
    }
}

Describe "move compensation" {
    It "replays as a move back to the source folder" {
        Mock Invoke-JrsRelocate { [pscustomobject]@{ Code = "201"; Body = "{}" } }
        Invoke-JrsCompensation -Jrs $script:Dead -Comp ([pscustomobject]@{ type = "move"; from = "/reports/b/r"; toFolder = "/reports/a" }) | Out-Null
        Assert-MockCalled Invoke-JrsRelocate -Times 1 -ParameterFilter { $Mode -eq "move" -and $Source -eq "/reports/b/r" -and $TargetFolder -eq "/reports/a" }
    }
    It "throws when the move back fails" {
        Mock Invoke-JrsRelocate { [pscustomobject]@{ Code = "404"; Body = "{}" } }
        { Invoke-JrsCompensation -Jrs $script:Dead -Comp ([pscustomobject]@{ type = "move"; from = "/reports/b/r"; toFolder = "/reports/a" }) } | Should Throw "HTTP 404"
    }
}
