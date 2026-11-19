<#
.SYNOPSIS
  Copy or move ONE repository resource into another folder. Plans by default;
  -Apply writes.

.DESCRIPTION
  Uses the resources service copy/move calls (REST ref 10.0.0 p.78-79): copy is
  POST, move is PUT, to /rest_v2/resources/<TargetFolder> with the header
  Content-Location: <Source>. The result keeps the source's name:
  <TargetFolder>/<leaf of Source>.

  Prechecks (plan and apply alike; any failure exits 2 and writes nothing):
    * the source exists and is not a folder (v1 relocates single resources)
    * the target folder is not the source's own folder (a no-op)
    * the target does not exist yet, unless -Overwrite (copy only)
    * -Move -Overwrite is refused (its rollback would need a move plus a reimport)
    * -Move of a resource a dashboard references is refused (dashboards store
      URIs, so the dashboard would break)
    * the target folder exists, unless -CreateFolders

  SAFETY MODEL (1.3.0):
    * Without -Apply the plan is printed and nothing is written. Plan mode is
      enforced below the script by _jrs_common.ps1's write guard.
    * With -Apply the run is journaled under out\runs\<runId>. A move carries a
      'move' (move back) compensation; a copy carries 'delete' of the new
      target, or -- when -Overwrite replaced an existing target -- 'reimport' of
      a backup exported first. Undo with:
          recover_run.ps1 -RunId <id> -Rollback -Apply
    * A prod profile additionally needs $env:JRS_ALLOW_PROD_WRITE = '1'.

  Exit codes: 0 ok (or plan printed), 2 precheck failed / nothing written,
  4 the write failed (see the recover_run hint).

.PARAMETER Source
  Repository URI of the resource to copy/move, e.g. /reports/a/county_summary.

.PARAMETER TargetFolder
  Destination folder URI, e.g. /reports/b. The resource keeps its name.

.PARAMETER Move
  Move instead of copy (the source is removed).

.PARAMETER Overwrite
  Copy over an existing target (backed up first). Not allowed with -Move.

.PARAMETER CreateFolders
  Create a missing target folder. Off by default so a typo fails the precheck.

.PARAMETER Apply
  Actually write. Without it the plan is printed and nothing is written.

.EXAMPLE
  .\relocate_resource.ps1 -Source /reports/a/county_summary -TargetFolder /reports/b
  .\relocate_resource.ps1 -Source /reports/a/county_summary -TargetFolder /reports/b -Move -Apply
#>
[CmdletBinding()]
param(
    [string]$Source,
    [string]$TargetFolder,
    [switch]$Move,
    [switch]$Overwrite,
    [switch]$CreateFolders,
    [switch]$Apply,
    [string]$BackupDir,
    [string]$ServerUrl,
    [string]$User,
    [string]$Password,
    [string]$Env
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "_jrs_common.ps1")

function Get-JrsParentUri([string]$Uri) {
    $i = $Uri.LastIndexOf("/")
    if ($i -le 0) { return "/" }
    return $Uri.Substring(0, $i)
}

function Test-JrsIsFolder {
    # $true when $Uri is a folder: a non-recursive search of its parent for
    # folders lists it (first 1000 sub-folders). Any non-200 (204 none, 404,
    # unreachable) counts as "not a folder".
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Jrs, [Parameter(Mandatory)][string]$Uri)
    $parent = Get-JrsParentUri $Uri
    $r = Invoke-JrsRest -Jrs $Jrs -Method GET -Path ("/rest_v2/resources?folderUri=" + $parent + "&type=folder&recursive=false&limit=1000")
    if ("$($r.Code)".Trim() -ne "200" -or -not $r.Body) { return $false }
    try { $items = @(($r.Body | ConvertFrom-Json).resourceLookup) } catch { return $false }
    return [bool](@($items | Where-Object { $_.uri -eq $Uri }).Count)
}

function Get-JrsRelocatePlan {
    # Reads only. Returns { Ok; Target; TargetExists; Problems; Lines }.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Jrs,
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$TargetFolder,
        [switch]$Move,
        [switch]$Overwrite,
        [switch]$CreateFolders
    )
    $src = ConvertTo-JrsRepoUri $Source
    $dst = ConvertTo-JrsRepoUri $TargetFolder
    $leaf = $src.Substring($src.LastIndexOf("/") + 1)
    $target = if ($dst -eq "/") { "/$leaf" } else { "$dst/$leaf" }
    $problems = @()
    $targetExists = $false

    if ($Move -and $Overwrite) { $problems += "-Move with -Overwrite is not supported (its rollback would need a move plus a reimport); copy with -Overwrite, or remove the target first" }
    if ((Get-JrsParentUri $src) -eq $dst) { $problems += "target folder $dst is the source's own folder (no-op)" }
    if (-not (Test-JrsResource -Jrs $Jrs -Uri $src)) {
        $problems += "source $src not found on $($Jrs.ServerUrl)"
    } else {
        if (Test-JrsIsFolder -Jrs $Jrs -Uri $src) { $problems += "source $src is a folder; v1 relocates single resources only" }
        if ($Move) {
            $dash = @(Get-JrsDashboardsReferencing -Jrs $Jrs -Uri $src)
            if ($dash.Count) { $problems += "dashboard(s) reference $src and would break if it moved: $($dash -join ', ')" }
        }
    }
    if ($target -ne $src -and (Test-JrsResource -Jrs $Jrs -Uri $target)) {
        $targetExists = $true
        if (-not $Overwrite) { $problems += "target $target already exists$(if (-not $Move) { ' (pass -Overwrite to replace it)' })" }
    }
    if ($dst -ne "/" -and -not $CreateFolders -and -not (Test-JrsResource -Jrs $Jrs -Uri $dst)) {
        $problems += "target folder $dst does not exist (pass -CreateFolders to create it)"
    }

    $verb = if ($Move) { "MOVE" } else { "COPY" }
    $lines = @("  $verb $src -> $target$(if ($targetExists -and $Overwrite) { ' (overwrites the existing target; backed up first)' })")
    return [pscustomobject]@{ Ok = ($problems.Count -eq 0); Target = $target; TargetExists = $targetExists; Problems = $problems; Lines = $lines }
}

if ($MyInvocation.InvocationName -eq ".") { return }   # dot-sourced by tests: functions only

if (-not $Source -or -not $TargetFolder) { throw "-Source and -TargetFolder are required" }
$exitCode = 0
$prevMode = Enter-JrsPlanMode -Apply:$Apply
try {
    $jrs = Resolve-JrsConfig -ServerUrl $ServerUrl -User $User -Password $Password -Env $Env
    $src = ConvertTo-JrsRepoUri $Source
    $dst = ConvertTo-JrsRepoUri $TargetFolder
    $p = Get-JrsRelocatePlan -Jrs $jrs -Source $src -TargetFolder $dst -Move:$Move -Overwrite:$Overwrite -CreateFolders:$CreateFolders
    $where = "$($jrs.ServerUrl)$(if ($jrs.Env) { " [env $($jrs.Env)]" })"
    Write-Host ""
    Write-Host "RELOCATE PLAN  on $where"
    $p.Lines | ForEach-Object { Write-Host $_ }
    Write-Host ""
    if (-not $p.Ok) {
        foreach ($x in $p.Problems) { Write-Host "  PRECHECK FAILED: $x" }
        Write-Host "nothing was written"
        $exitCode = 2
    } elseif (-not $Apply) {
        Write-Host "[plan] nothing was written to $($jrs.ServerUrl); pass -Apply to write (undo later with recover_run.ps1 -RunId <id> -Rollback -Apply)"
    } else {
        Assert-JrsWriteAllowed -Jrs $jrs -Method APPLY -Url $jrs.ServerUrl   # refuse an unconfirmed prod target before any backup
        $op = if ($Move) { "move" } else { "copy" }
        $plan = @([pscustomobject]@{ Order = 1; Kind = $op; Uri = $src; Action = "$op -> $($p.Target)" })
        $run = New-JrsRun -Operation "relocate" -Target $jrs -Mode apply -Plan $plan -Arguments @{
            Source = $src; TargetFolder = $dst; Move = [bool]$Move; Overwrite = [bool]$Overwrite; CreateFolders = [bool]$CreateFolders }
        $step = "${op}:$src -> $($p.Target)"
        try {
            $comp = $null; $irrev = $null
            if ($Move) {
                $comp = @{ type = "move"; from = $p.Target; toFolder = (Get-JrsParentUri $src) }
            } elseif ($p.TargetExists) {
                $zip = Export-JrsBackup -Jrs $jrs -Uri $p.Target -BackupDir $BackupDir
                if ($zip) { $comp = @{ type = "reimport"; zip = $zip; uri = $p.Target }; Write-Host "backup $($p.Target) -> $zip" }
                else { $irrev = "no backup of overwritten target" }
            } else {
                $comp = @{ type = "delete"; uri = $p.Target }
            }
            Write-JrsStep -Run $run -Step $step -State RUNNING -Compensation $comp -Irreversible $irrev
            $r = Invoke-JrsRelocate -Jrs $jrs -Mode $op -Source $src -TargetFolder $dst -Overwrite:$Overwrite -CreateFolders:$CreateFolders
            Write-Host "$($op.ToUpper()) $src -> $($p.Target): HTTP $($r.Code)"
            if ("$($r.Code)" -notmatch '^2\d\d$') {
                Write-JrsStep -Run $run -Step $step -State FAILED -Detail "HTTP $($r.Code) $($r.Body)"
                throw "$op failed: HTTP $($r.Code) $($r.Body)"
            }
            Write-JrsStep -Run $run -Step $step -State SUCCEEDED -Detail "HTTP $($r.Code)"
            Complete-JrsRun -Run $run -Status SUCCEEDED
            Write-Host "OK: ${op} $src -> $($p.Target) (run $($run.RunId))"
        } catch {
            Complete-JrsRun -Run $run -Status FAILED -ExitCode 4 -Error "$_"
            Write-Host "FAILED (run $($run.RunId)): $_"
            Write-Host "undo what was done with: recover_run.ps1 -RunId $($run.RunId) -Rollback -Apply"
            $exitCode = 4
        }
    }
} finally { Restore-JrsPlanMode $prevMode }
exit $exitCode
