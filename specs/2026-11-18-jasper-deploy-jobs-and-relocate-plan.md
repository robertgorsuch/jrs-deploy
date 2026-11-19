# jasper-deploy 1.4.0: scheduler pause/resume + repository copy/move -- Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add (1) scheduler job pause / resume / restart / state / snapshot / restore to `schedule_job.ps1`, and (2) a new `relocate_resource.ps1` that copies or moves one repository resource. Both use the 1.3.0 safety model: plan by default, `-Apply` to write, PROD GUARD, run journal + `recover_run.ps1` rollback.

**Architecture:** The REST calls live in dot-sourced helpers (`_jrs_common.ps1` for relocate, a new `_jobs_common.ps1` for jobs), so Pester can test them without a server. The two entry scripts stay thin. Every write goes through `Invoke-JrsRest`, which already calls `Assert-JrsWriteAllowed`. Two new compensation-record families (`move`, `jobs-pause` / `jobs-resume`) are added to `Invoke-JrsCompensation`, so a journaled run can be rolled back. `tests/mock_jrs.py` gains stateful jobs and copy/move endpoints for the harness tests.

**Tech Stack:** Windows PowerShell 5.1 + pwsh 7, curl, Pester 4 (legacy `Should Be` syntax), Python 3 (`mock_jrs.py`), JRS REST v2 (10.0.0 reference).

**Spec / sources:** There is no separate design doc. This plan argues from:
- JRS REST API Reference 10.0.0 (`docs/JasperReportsServerRESTAPIReferencev10.0.0.pdf`): jobs service p.225-233 (`/jobs/{id}/state`, `/jobs/pause`, `/jobs/resume`, `/jobs/restart`); resources service p.78-79 (copy = `POST`, move = `PUT`, both with a `Content-Location` header).
- Community KB (Wayback captures, list in the session scratchpad): *how-batch-disable-all-active-scheduled-report-jobs-prior-upgrade*, *paused-scheduled-jobs-restarted-after-upgrade* (7.5.1 or earlier to 7.9.2+ resumes paused jobs: the Quartz `instanceName` changed from `quartzScheduler` to `JasperServerScheduler`), *moving-a-resource-using-rest-api*, *copying-a-resource-using-rest-api*.
- The 1.3.0 safety model: `specs/2026-09-28-jasper-deploy-safety-model-design.md`.

All skill paths below are relative to `plugins/jasper-deploy/skills/jasper-deploy/` unless they start with `plugins/` or `specs/`.

## Global Constraints

- **Never send an empty job-ID list.** Per REST ref p.229-231, an empty `/jobs/pause` or `/jobs/resume` body acts on EVERY job in the scheduler. "All jobs" is always expanded client-side into an explicit ID list and needs `-All`.
- Resume does not run triggers missed while a job was paused (ref p.230). This is printed in every resume plan.
- New write actions plan by default; nothing is written without `-Apply`. Existing `schedule_job.ps1` `create` / `delete` behaviour stays unchanged (backward compatible).
- PROD: no agent `-Apply` against PROD, ever (incident 2026-08-28). PROD writes need `$env:JRS_ALLOW_PROD_WRITE='1'` set by a human. Reads (`list`, `state`, `snapshot`) are allowed on PROD.
- Dot-sourced helper files have NO `param()` block (gotcha G60; enforced by `tests/dotsource.Tests.ps1`).
- The repo is PUBLIC. Test fixtures are synthetic: no real job labels, report URIs, hostnames, users or credentials from STAGE/PROD.
- ASCII-only in new docs and script output (no em dashes, arrows or curly quotes).
- Exit codes follow the run-journal table: 0 ok, 2 precheck failed / nothing written, 3 rolled back, 4 failed or rollback incomplete.
- PS 5.1 compatible: no `?.`, `??` or ternary. Build JSON with `ConvertTo-Json -InputObject` so a one-element array stays an array.
- Pester 4 syntax (`Should Be`, `Should Throw`), matching the existing tests.

## Review Focus

1. **Every requested job is already paused (or missing).** Pause must issue NO POST at all, not a POST with `{"jobId":[]}`. Pinned in Task 3 (`Invoke-JrsJobBatch` throws on empty) and Task 4 (harness: zero writes).
2. **A single job ID** (`-Id 5`) must serialize as `{"jobId":[5]}`, not `{"jobId":5}` (PS 5.1 unwrap). Pinned in Task 3.
3. **Rollback after a pause must not resume jobs that were paused before the run.** The compensation carries only the IDs this run paused. Pinned in Task 3 (plan) and Task 4 (harness rollback).
4. **Move or copy onto an existing target, or a move of a resource a dashboard references.** Both refuse with exit 2 and write nothing. Pinned in Task 2.
5. **Sloppy URIs** (`reports/x/`, `//reports//x`, target folder = source's own folder) are normalized, and a same-folder relocate is refused as a no-op. Pinned in Tasks 1 and 2.

---

### Task 0: STAGE spike -- confirm the four behaviours the plan depends on (human-run, no code merged)

Goal: settle what the reference leaves open before writing code. Run only against STAGE (`localhost:8081`), only under `/reports/_smoke/relocate_spike`, and delete everything afterwards.

**Files:**
- Modify: `references/jrs-rest-api.md` (record findings under `## jobs` and a new `## resources: copy / move` subsection, tagged **[verified]** with the date)
- Create: `tests/fixtures/jobs/jobs.json` (SYNTHETIC, shaped like the captured `GET /rest_v2/jobs` body)

- [ ] **Step 1:** `GET /rest_v2/jobs` (Accept `application/json`). Record the exact top-level key (expected `jobsummary`) and which fields each summary carries (`id`, `label`, `reportUnitURI`, `owner`, `state`?). If `state` is in the summary, note it; Task 3 still reads `/jobs/{id}/state` as the source of truth.
- [ ] **Step 2:** On one throwaway job created with `schedule_job.ps1 -Action create -ReportUri /reports/_smoke/relocate_spike/r -StartType at -StartDate <future>`: `POST /jobs/pause` with `{"jobId":[<id>]}`, then `GET /jobs/<id>/state` (expect `PAUSED`), then `POST /jobs/resume` (expect `NORMAL`). Record the response bodies. **Do NOT send an empty body.**
- [ ] **Step 3:** Copy then move: `POST /rest_v2/resources/reports/_smoke/relocate_spike/dst?createFolders=false` with `Content-Location: /reports/_smoke/relocate_spike/src/r`. Record the URI of the result (expected `.../dst/r`, the leaf name kept). Then `PUT` (move) a second resource and confirm the source is gone (404). Try a target that already exists without `overwrite=true` and record the status code.
- [ ] **Step 4:** Move a report unit whose datasource is a repository reference, then run it to PDF. Record whether it still runs. Create a one-tile dashboard on a report, move the report, and record whether the dashboard still renders (expected: it breaks, because dashboards store URIs).
- [ ] **Step 5: Decision gate.** If Step 3 shows the target URL is NOT "destination folder + source leaf", stop and revise Tasks 1-2 before continuing. If Step 4 shows a moved report's datasource reference breaks, add that to the Task 2 move precheck (refuse when the source is a datasource referenced by any report) before implementing.
- [ ] **Step 6:** Write `tests/fixtures/jobs/jobs.json`: four synthetic jobs (ids 101-104, labels `t_job_a`..`t_job_d`, `reportUnitURI` `/reports/t/r1`..`r4`), states `NORMAL, NORMAL, PAUSED, NORMAL`, in the schema `[{ "id", "label", "reportUnitURI", "owner", "state" }]`.
- [ ] **Step 7:** Clean up STAGE (delete the job and `/reports/_smoke/relocate_spike`), then commit.

```bash
git add plugins/jasper-deploy/skills/jasper-deploy/references/jrs-rest-api.md plugins/jasper-deploy/skills/jasper-deploy/tests/fixtures/jobs/jobs.json
git commit -m "docs(jasper-deploy): verify jobs pause/resume/state and resources copy/move on STAGE"
```

---

### Task 1: Shared plumbing -- extra headers in `Invoke-JrsRest`, URI normalization, `Invoke-JrsRelocate`, mock copy/move

**Files:**
- Modify: `scripts/_jrs_common.ps1` (`Invoke-JrsRest` at ~line 434; add two functions after `Invoke-JrsRest`; header comment block lines 1-90)
- Modify: `tests/mock_jrs.py` (`_dispatch` resources branch ~line 188; module docstring)
- Test: `tests/_jrs_common.Tests.ps1`, `tests/write_guard.Tests.ps1`

**Interfaces:**
- Produces:
  - `Invoke-JrsRest ... [-Headers <string[]>]`: each entry is passed as `-H "<entry>"`. Behaviour is otherwise unchanged.
  - `ConvertTo-JrsRepoUri([string]$Uri) -> string`: adds a leading `/`, collapses repeated `/`, strips any trailing `/`. `"/"` stays `"/"`.
  - `Invoke-JrsRelocate -Jrs <cfg> -Mode copy|move -Source <uri> -TargetFolder <uri> [-Overwrite] [-CreateFolders] -> [pscustomobject]@{ Code; Body }`. Copy = `POST`, move = `PUT`, to `/rest_v2/resources<TargetFolder>?createFolders=<true|false>[&overwrite=true]`, with header `Content-Location: <Source>`. `createFolders` defaults to **false** (a typo should not create stray folders).
  - Mock: a `POST`/`PUT` on `/rest_v2/resources<folder>` that carries `Content-Location` copies or moves the known source to `<folder>/<leaf>` and returns 201 + the descriptor. It returns 404 `resource.not.found` when the source is unknown, and a move also forgets the source.

- [ ] **Step 1: Write the failing tests**

```powershell
# tests/_jrs_common.Tests.ps1
Describe "ConvertTo-JrsRepoUri" {
    It "adds a leading slash and strips a trailing one" { ConvertTo-JrsRepoUri "reports/x/" | Should Be "/reports/x" }
    It "collapses doubled slashes"                       { ConvertTo-JrsRepoUri "//reports//x" | Should Be "/reports/x" }
    It "keeps the root"                                  { ConvertTo-JrsRepoUri "/" | Should Be "/" }
}
Describe "Invoke-JrsRelocate request shape" {
    It "copy POSTs to the folder with Content-Location and createFolders=false" {
        Mock Invoke-JrsRest { [pscustomobject]@{ Code = "201"; Body = "{}" } }
        Invoke-JrsRelocate -Jrs $script:Dead -Mode copy -Source "/reports/a/r" -TargetFolder "/reports/b" | Out-Null
        Assert-MockCalled Invoke-JrsRest -Times 1 -ParameterFilter {
            $Method -eq "POST" -and $Path -eq "/rest_v2/resources/reports/b?createFolders=false" -and ($Headers -contains "Content-Location: /reports/a/r") }
    }
    It "move PUTs and adds overwrite=true only when asked" {
        Mock Invoke-JrsRest { [pscustomobject]@{ Code = "201"; Body = "{}" } }
        Invoke-JrsRelocate -Jrs $script:Dead -Mode move -Source "/reports/a/r" -TargetFolder "/reports/b" -Overwrite -CreateFolders | Out-Null
        Assert-MockCalled Invoke-JrsRest -Times 1 -ParameterFilter {
            $Method -eq "PUT" -and $Path -eq "/rest_v2/resources/reports/b?createFolders=true&overwrite=true" }
    }
}
# tests/write_guard.Tests.ps1 (inside the existing plan-mode Describe)
It "Invoke-JrsRelocate is refused in plan mode before any request" {
    Enter-JrsPlanMode -Apply:$false | Out-Null
    { Invoke-JrsRelocate -Jrs $script:Dead -Mode move -Source "/a/r" -TargetFolder "/b" } | Should Throw "PLAN MODE"
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `pwsh -NoProfile -Command "Invoke-Pester tests/_jrs_common.Tests.ps1, tests/write_guard.Tests.ps1"` (from the skill dir)
Expected: FAIL, `ConvertTo-JrsRepoUri` / `Invoke-JrsRelocate` not recognized.

- [ ] **Step 3: Implement.** Add `[string[]]$Headers` to `Invoke-JrsRest` and append `-H $h` for each entry before `$url`. Add `ConvertTo-JrsRepoUri` and `Invoke-JrsRelocate`; `Invoke-JrsRelocate` normalizes both URIs and delegates to `Invoke-JrsRest`, so the existing write guard applies unchanged. Document all three in the header comment block. In `mock_jrs.py`, read `self.headers.get("Content-Location")` in the resources `POST`/`PUT` branch before the existing create logic, and update the docstring.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `pwsh -NoProfile -Command "Invoke-Pester tests/_jrs_common.Tests.ps1, tests/write_guard.Tests.ps1, tests/dotsource.Tests.ps1"`
Expected: PASS, 0 failed.

- [ ] **Step 5: Commit**

```bash
git add plugins/jasper-deploy/skills/jasper-deploy/scripts/_jrs_common.ps1 plugins/jasper-deploy/skills/jasper-deploy/tests/mock_jrs.py plugins/jasper-deploy/skills/jasper-deploy/tests/_jrs_common.Tests.ps1 plugins/jasper-deploy/skills/jasper-deploy/tests/write_guard.Tests.ps1
git commit -m "feat(jasper-deploy): Invoke-JrsRelocate + -Headers on Invoke-JrsRest; mock copy/move"
```

---

### Task 2: `relocate_resource.ps1` + `move` compensation

**Files:**
- Create: `scripts/relocate_resource.ps1`
- Modify: `scripts/_jrs_run.ps1` (`Invoke-JrsCompensation` switch ~line 222; `Invoke-JrsRollback` description switch ~line 262; compensation list in the header comment lines 28-31)
- Test: create `tests/relocate_resource.Tests.ps1` (unit, mocked); add a `Describe` block to `tests/harness.Tests.ps1`

**Interfaces:**
- Consumes: `ConvertTo-JrsRepoUri`, `Invoke-JrsRelocate` (Task 1); the existing `Test-JrsResource`, `Get-JrsDashboardsReferencing`, `Export-JrsBackup`, `Enter-JrsPlanMode`/`Restore-JrsPlanMode`, `New-JrsRun`/`Write-JrsStep`/`Complete-JrsRun`.
- Produces:
  - CLI: `relocate_resource.ps1 -Source <uri> -TargetFolder <uri> [-Move] [-Overwrite] [-CreateFolders] [-Apply] [-Env <name> | -ServerUrl/-User/-Password]`
  - `Get-JrsRelocatePlan -Jrs -Source -TargetFolder [-Move] [-Overwrite] -> [pscustomobject]@{ Ok [bool]; Target [string]; TargetExists [bool]; Problems [string[]]; Lines [string[]] }`: reads only. Defined in the script; the main block is guarded with `if ($MyInvocation.InvocationName -ne '.')` so the tests can dot-source it.
  - Compensation record `@{ type = 'move'; from = '<target uri>'; toFolder = '<source parent folder>' }`, replayed as `Invoke-JrsRelocate -Mode move -Source from -TargetFolder toFolder`.

Prechecks (each adds a `Problems` entry, which means exit 2 and no write, in plan and apply mode alike):
- the source does not exist;
- the source is a folder (v1 relocates single resources only);
- `TargetFolder` equals the source's parent folder ("no-op");
- the target exists and `-Overwrite` was not passed;
- `-Move` with `-Overwrite` (not supported in v1: the rollback would need a move plus a reimport);
- `-Move` of a resource that `Get-JrsDashboardsReferencing` reports a dashboard uses (the dashboard would break; Task 0 Step 4);
- the target folder does not exist and `-CreateFolders` was not passed.

Journal: one step `copy <src> -> <target>` or `move <src> -> <target>`, written RUNNING with its compensation before the call:
- copy onto a new target: `delete <target>`;
- copy with `-Overwrite` onto an existing target: `Export-JrsBackup` of the target first, then `reimport` (if the backup fails, the step is `-Irreversible "no backup of overwritten target"`);
- move: `move` back.

- [ ] **Step 1: Write the failing unit tests** (`tests/relocate_resource.Tests.ps1`, dot-source the script, mock `Test-JrsResource`, `Get-JrsDashboardsReferencing` and `Invoke-JrsGet`)

```powershell
Describe "Get-JrsRelocatePlan prechecks" {
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
        ($p.Problems -join ";") | Should Match "/reports/a/dash"
    }
    It "refuses a same-folder relocate as a no-op, after normalizing" {
        Mock Test-JrsResource { $true }
        $p = Get-JrsRelocatePlan -Jrs $script:Dead -Source "reports/a/r" -TargetFolder "/reports/a/"
        ($p.Problems -join ";") | Should Match "no-op"
    }
    It "refuses -Move with -Overwrite" {
        Mock Test-JrsResource { $true }
        Mock Get-JrsDashboardsReferencing { @() }
        $p = Get-JrsRelocatePlan -Jrs $script:Dead -Source "/reports/a/r" -TargetFolder "/reports/b" -Move -Overwrite
        ($p.Problems -join ";") | Should Match "not supported"
    }
    It "plans a copy to <folder>/<leaf>" {
        Mock Test-JrsResource { param($Jrs, $Uri) $Uri -ne "/reports/b/r" }
        $p = Get-JrsRelocatePlan -Jrs $script:Dead -Source "/reports/a/r" -TargetFolder "/reports/b"
        $p.Ok | Should Be $true; $p.Target | Should Be "/reports/b/r"
    }
}
Describe "move compensation" {
    It "replays as a move back to the source folder" {
        Mock Invoke-JrsRelocate { [pscustomobject]@{ Code = "201"; Body = "{}" } }
        Invoke-JrsCompensation -Jrs $script:Dead -Comp ([pscustomobject]@{ type = "move"; from = "/reports/b/r"; toFolder = "/reports/a" }) | Out-Null
        Assert-MockCalled Invoke-JrsRelocate -Times 1 -ParameterFilter { $Mode -eq "move" -and $Source -eq "/reports/b/r" -and $TargetFolder -eq "/reports/a" }
    }
}
```

Harness `Describe "relocate_resource.ps1 against mock_jrs"`, reusing `Invoke-Skill`/`Get-Writes`/`Clear-Log`. Seed `/reports/t/src/r` and the folder `/reports/t/dst` with direct curl PUTs to the mock first.
- plan mode: exit 0, `(Get-Writes).Count | Should Be 0`;
- `-Move -Apply`: exit 0; `GET /reports/t/dst/r` is 200 and `GET /reports/t/src/r` is 404;
- `recover_run.ps1 -RunId latest -Rollback -Apply`: exit 3 (ROLLED_BACK), and the source is back.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `pwsh -NoProfile -Command "Invoke-Pester tests/relocate_resource.Tests.ps1, tests/harness.Tests.ps1"`
Expected: FAIL, script not found / `unknown compensation type 'move'`.

- [ ] **Step 3: Implement** `relocate_resource.ps1`, modelled on `teardown_dashboard.ps1` (lines 48-132): `$prev = Enter-JrsPlanMode -Apply:$Apply` / `try`-`finally Restore-JrsPlanMode`; prints `[plan] ...` lines plus the recover hint; `exit 2` on `Problems`; `Complete-JrsRun FAILED -ExitCode 4` plus the `recover_run.ps1` hint on failure. Add the `"move"` case to `Invoke-JrsCompensation` and `"MOVE <from> -> <toFolder>"` to the rollback description switch.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `pwsh -NoProfile -Command "Invoke-Pester tests"`
Expected: PASS, 0 failed (the whole suite, so `run_journal.Tests.ps1` and `dotsource.Tests.ps1` still pass).

- [ ] **Step 5: Commit**

```bash
git add plugins/jasper-deploy/skills/jasper-deploy/scripts/relocate_resource.ps1 plugins/jasper-deploy/skills/jasper-deploy/scripts/_jrs_run.ps1 plugins/jasper-deploy/skills/jasper-deploy/tests/relocate_resource.Tests.ps1 plugins/jasper-deploy/skills/jasper-deploy/tests/harness.Tests.ps1
git commit -m "feat(jasper-deploy): relocate_resource.ps1 copy/move, plan by default, journaled move-back rollback"
```

---

### Task 3: `_jobs_common.ps1` -- job reads, transition planning, guarded batch call

**Files:**
- Create: `scripts/_jobs_common.ps1` (no `param()` block; dot-sources `_jrs_common.ps1` only if `Invoke-JrsRest` is not already defined)
- Test: create `tests/jobs_common.Tests.ps1`

**Interfaces:**
- Consumes: `Invoke-JrsRest`, `Assert-JrsOk`.
- Produces:
  - `Get-JrsJobList -Jrs [-ReportUri <uri>] -> object[]` of `[pscustomobject]@{ Id [int]; Label; ReportUnitURI; Owner }`. A 204 response gives `@()`. Always wrapped in `@()`. The body key is the one recorded in Task 0 Step 1.
  - `Get-JrsJobState -Jrs -Id <int> -> [pscustomobject]@{ Id; Value; NextFireTime; PreviousFireTime }`. `Value` is `NORMAL|EXECUTING|PAUSED|<error>`, or `MISSING` on a 404.
  - `Resolve-JrsJobTargets -Jrs -Ids <int[]> [-All] -> int[]`. Throws `"refusing to act on every job without -All"` when `Ids` is empty and `-All` is not set, and `"-Id and -All are mutually exclusive"` when both are given. `-All` expands to `(Get-JrsJobList).Id`.
  - `Get-JrsJobTransitionPlan -States <state objects> -Action pause|resume -> object[]` of `[pscustomobject]@{ Id; From; Act ('pause'|'resume'|'skip'); Reason }`. pause: NORMAL or EXECUTING become `pause` (EXECUTING gets the reason "current run finishes; future triggers paused"); PAUSED is skipped ("already paused"); MISSING is skipped. resume: only PAUSED becomes `resume`.
  - `ConvertTo-JrsJobIdBody -Ids <int[]> -> string`, e.g. `{"jobId":[5]}`.
  - `Invoke-JrsJobBatch -Jrs -Action pause|resume|restart -Ids <int[]> -> int[]`, the IDs the server echoed. **Throws `"empty job list"` before any request when `Ids` is empty.** Body via a temp file; `Content-Type` and `Accept` `application/json`.

- [ ] **Step 1: Write the failing tests**

```powershell
. "$PSScriptRoot/../scripts/_jobs_common.ps1"
Describe "job-id body" {
    It "keeps a single id as an array" { ConvertTo-JrsJobIdBody -Ids @(5) | Should Be '{"jobId":[5]}' }
    It "keeps order"                   { ConvertTo-JrsJobIdBody -Ids @(7,3) | Should Be '{"jobId":[7,3]}' }
}
Describe "Invoke-JrsJobBatch" {
    It "never sends an empty list (an empty body pauses ALL jobs server-side)" {
        Mock Invoke-JrsRest { throw "must not be called" }
        { Invoke-JrsJobBatch -Jrs $script:Dead -Action pause -Ids @() } | Should Throw "empty job list"
        Assert-MockCalled Invoke-JrsRest -Times 0
    }
    It "POSTs to /rest_v2/jobs/pause" {
        Mock Invoke-JrsRest { [pscustomobject]@{ Code = "200"; Body = '{"jobId":[5]}' } }
        (Invoke-JrsJobBatch -Jrs $script:Dead -Action pause -Ids @(5)) | Should Be 5
        Assert-MockCalled Invoke-JrsRest -Times 1 -ParameterFilter { $Method -eq "POST" -and $Path -eq "/rest_v2/jobs/pause" }
    }
}
Describe "Resolve-JrsJobTargets" {
    It "refuses an empty selection without -All" { { Resolve-JrsJobTargets -Jrs $script:Dead -Ids @() } | Should Throw "without -All" }
    It "rejects -Id together with -All"          { { Resolve-JrsJobTargets -Jrs $script:Dead -Ids @(1) -All } | Should Throw "mutually exclusive" }
}
Describe "Get-JrsJobTransitionPlan" {
    $s = @([pscustomobject]@{Id=1;Value="NORMAL"}, [pscustomobject]@{Id=2;Value="PAUSED"},
           [pscustomobject]@{Id=3;Value="EXECUTING"}, [pscustomobject]@{Id=4;Value="MISSING"})
    It "pauses NORMAL and EXECUTING only; skips already-paused" {
        $p = Get-JrsJobTransitionPlan -States $s -Action pause
        (@($p | Where-Object Act -eq "pause").Id -join ",") | Should Be "1,3"
        ($p | Where-Object Id -eq 2).Reason | Should Be "already paused"
    }
    It "resumes PAUSED only" {
        (@(Get-JrsJobTransitionPlan -States $s -Action resume | Where-Object Act -eq "resume").Id -join ",") | Should Be "2"
    }
}
```

Also add one `Get-JrsJobList` test with a mocked 204 (`Count | Should Be 0`) and one with a single-job body (`Count | Should Be 1`), covering the PS 5.1 unwrap.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `pwsh -NoProfile -Command "Invoke-Pester tests/jobs_common.Tests.ps1"`
Expected: FAIL, the file `_jobs_common.ps1` does not exist.

- [ ] **Step 3: Implement** the six functions in `scripts/_jobs_common.ps1`, with a header comment in the `_jrs_common.ps1` style that warns about the empty-body semantics (REST ref p.229).

- [ ] **Step 4: Run the tests to verify they pass**

Run: `pwsh -NoProfile -Command "Invoke-Pester tests/jobs_common.Tests.ps1, tests/dotsource.Tests.ps1"`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add plugins/jasper-deploy/skills/jasper-deploy/scripts/_jobs_common.ps1 plugins/jasper-deploy/skills/jasper-deploy/tests/jobs_common.Tests.ps1
git commit -m "feat(jasper-deploy): _jobs_common job list/state/transition plan; batch call refuses an empty id list"
```

---

### Task 4: `schedule_job.ps1` pause / resume / restart / state + jobs compensations + mock jobs

**Files:**
- Modify: `scripts/schedule_job.ps1` (`ValidateSet` line 83; `[int]$Id` becomes `[int[]]$Id`; add `[switch]$All`, `[switch]$Apply`; `switch ($Action)` line 115; comment-based help)
- Modify: `scripts/_jrs_run.ps1` (`Invoke-JrsCompensation` and the rollback description: `jobs-pause`, `jobs-resume`)
- Modify: `tests/mock_jrs.py` (add `--jobs <fixture>`; endpoints below; for job batch POSTs, the log line gains `"jobIds": <count>`)
- Test: add a `Describe` to `tests/harness.Tests.ps1`; add the compensation cases to `tests/run_journal.Tests.ps1`

**Interfaces:**
- Consumes: everything from Task 3; `tests/fixtures/jobs/jobs.json` (Task 0).
- Produces:
  - CLI: `schedule_job.ps1 -Action pause|resume|restart (-Id <int[]> | -All) [-Apply]`; `-Action state -Id <int[]>` (read-only; prints `id  value  nextFireTime  label`). `get` and `delete` still need exactly one `-Id` (throw `"-Id takes one id for get/delete"` otherwise).
  - Compensations: pause records `@{ type='jobs-resume'; ids=@(<ids this run pauses>) }`; resume records `@{ type='jobs-pause'; ids=@(...) }`. Both replay via `Invoke-JrsJobBatch` and are a no-op when `ids` is empty. Restart is journaled `-Irreversible "restart fires the job now"`.
  - Mock endpoints: `GET /rest_v2/jobs` returns `{"<key from Task 0>":[...]}` or 204 when empty; `GET /rest_v2/jobs/{id}/state` returns `{"value":...}` or 404; `POST /rest_v2/jobs/pause|resume|restart` updates states for the listed known IDs and echoes them. An empty list pauses or resumes ALL, mirroring the real server so a regression is visible.

Flow for pause/resume: resolve targets, read each job's state, build the transition plan, and print it (plus the "missed triggers are not re-run" note for resume). With no `-Apply`, print `[plan] nothing was written` and exit 0. If no job has a `pause`/`resume` action, print `nothing to do` and exit 0 **without opening a run or sending a request**. Otherwise open the run, write one step RUNNING with its compensation, call `Invoke-JrsJobBatch` with the acting IDs only, mark the step SUCCEEDED (detail = echoed IDs) and complete the run.

- [ ] **Step 1: Write the failing harness tests** (mock started with `--jobs tests/fixtures/jobs/jobs.json`)
  - `-Action pause -Id 101,103` (plan): exit 0, `Get-Writes` count 0.
  - `-Action pause -Id 101,103 -Apply`: one write, to `/rest_v2/jobs/pause`, with `jobIds` 1 (103 was already PAUSED); state of 101 is `PAUSED`.
  - `-Action pause -Id 103 -Apply` (already paused): exit 0, `Get-Writes` count 0. **Review Focus 1.**
  - `-Action pause -Apply` with neither `-Id` nor `-All`: non-zero exit, 0 writes.
  - `-Action pause -All -Apply`: one write whose `jobIds` is 3 (101, 102, 104; never 0).
  - Then `recover_run.ps1 -RunId latest -Rollback -Apply`: exit 3; 101, 102 and 104 are `NORMAL` again, and **103 is still `PAUSED`**. **Review Focus 3.**
  - `-Action pause -Id 101 -Apply` against a profile with `IsProd`, with the env var unset: throws `PROD GUARD`, 0 writes.
  - `run_journal.Tests.ps1`: `Invoke-JrsCompensation` with `type jobs-resume, ids @()` makes no `Invoke-JrsJobBatch` call (mocked, `-Times 0`).

- [ ] **Step 2: Run the tests to verify they fail**

Run: `pwsh -NoProfile -Command "Invoke-Pester tests/harness.Tests.ps1, tests/run_journal.Tests.ps1"`
Expected: FAIL (`Cannot validate argument on parameter 'Action'`; mock answers `mock.unmapped`).

- [ ] **Step 3: Implement** the mock endpoints, then the `schedule_job.ps1` actions (dot-source `_jobs_common.ps1` after `_jrs_common.ps1`), then the two compensation cases.

- [ ] **Step 4: Run the whole suite**

Run: `pwsh -NoProfile -Command "Invoke-Pester tests"` and `python -m pytest tests/test_scaffold_jrxml.py -q`
Expected: PASS, 0 failed.

- [ ] **Step 5: Commit**

```bash
git add plugins/jasper-deploy/skills/jasper-deploy/scripts/schedule_job.ps1 plugins/jasper-deploy/skills/jasper-deploy/scripts/_jrs_run.ps1 plugins/jasper-deploy/skills/jasper-deploy/tests/mock_jrs.py plugins/jasper-deploy/skills/jasper-deploy/tests/harness.Tests.ps1 plugins/jasper-deploy/skills/jasper-deploy/tests/run_journal.Tests.ps1
git commit -m "feat(jasper-deploy): schedule_job pause/resume/restart/state, plan by default, journaled + reversible"
```

---

### Task 5: Upgrade safety -- `snapshot` and `restore`

**Files:**
- Modify: `scripts/_jobs_common.ps1` (two functions), `scripts/schedule_job.ps1` (two actions, `-Snapshot <path>`, `-Out <path>`)
- Test: `tests/jobs_common.Tests.ps1`, `tests/harness.Tests.ps1`

**Interfaces:**
- Consumes: `Get-JrsJobList`, `Get-JrsJobState`, `Invoke-JrsJobBatch`, the Task 4 compensations.
- Produces:
  - `New-JrsJobSnapshot -Jrs [-Path <file>] -> string` (the path written). Default path: `out/job-snapshots/<env or host>-<yyyyMMdd-HHmmss>.json` (gitignored). The document is `{ server, env, takenAt, jobs: [{ id, label, reportUnitURI, owner, state, nextFireTime }] }`. No credentials. Read-only, so allowed on PROD.
  - `Get-JrsJobRestorePlan -Snapshot <obj> -Current <obj[] of {Id,Label,ReportUnitURI,Value}> -> object[]` of `{ Id; Label; Was; Now; Act ('pause'|'resume'|'none'|'unresolved'); MatchedBy ('id'|'label+uri'|'') }`. Match by `id` first. If the id is gone (repository rebuilt by export/import), match by `label + reportUnitURI`, and only when exactly one current job matches; otherwise mark `unresolved`. Snapshot PAUSED and now NORMAL gives `pause` (the 7.5.1 to 7.9.2+ regression from the KB); snapshot NORMAL and now PAUSED gives `resume`. Jobs present now but absent from the snapshot are left alone and not listed.
  - CLI: `schedule_job.ps1 -Action snapshot [-Out <file>]`; `schedule_job.ps1 -Action restore -Snapshot <file> [-Apply]`. Restore executes as at most two journaled steps (one pause batch, one resume batch), each with its compensation. `unresolved` rows are printed and make the exit code 2 even when everything else applied ("review by hand").

- [ ] **Step 1: Write the failing unit tests** for `Get-JrsJobRestorePlan`:
  - snapshot `{101 PAUSED}`, current `{101 NORMAL}`: `Act` is `pause`, `MatchedBy` is `id`;
  - snapshot `{101 NORMAL}`, current `{101 PAUSED}`: `resume`;
  - snapshot `{101 PAUSED t_job_a /reports/t/r1}`, current `{555 NORMAL t_job_a /reports/t/r1}`: `pause` on Id 555, `MatchedBy` `label+uri`;
  - two current jobs with the same label + uri and no id match: `unresolved`;
  - an extra current job not in the snapshot is not in the plan.

  Harness: `snapshot` makes 0 writes and the file exists with 4 jobs. Then `pause -All -Apply`, then `restore -Snapshot <file> -Apply`: one write (resume of 101, 102, 104); 103 stays PAUSED; exit 0.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `pwsh -NoProfile -Command "Invoke-Pester tests/jobs_common.Tests.ps1, tests/harness.Tests.ps1"`
Expected: FAIL, the functions are not defined.

- [ ] **Step 3: Implement** both functions and both actions.

- [ ] **Step 4: Run the whole suite**

Run: `pwsh -NoProfile -Command "Invoke-Pester tests"`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add plugins/jasper-deploy/skills/jasper-deploy/scripts/_jobs_common.ps1 plugins/jasper-deploy/skills/jasper-deploy/scripts/schedule_job.ps1 plugins/jasper-deploy/skills/jasper-deploy/tests/jobs_common.Tests.ps1 plugins/jasper-deploy/skills/jasper-deploy/tests/harness.Tests.ps1
git commit -m "feat(jasper-deploy): schedule_job snapshot/restore for upgrade windows"
```

---

### Task 6: Docs, version bump, doc checks

**Files:**
- Modify: `SKILL.md` (capability map: update the `schedule_job.ps1` row; add a `relocate_resource.ps1 -Source -TargetFolder [-Move] [-Apply]` row pointing to `references/jrs-rest-api.md`; add `_jobs_common.ps1` wherever the helper files are listed)
- Modify: `references/admin-and-scheduling.md` (pause/resume/restart/state/snapshot/restore usage; the empty-list warning; missed triggers are not re-run; job-owner transfer is SQL-only per the KB and must be run by a DBA, so it stays out of the tool)
- Modify: `references/upgrade-migration-playbook.md` (pre-upgrade runbook: `snapshot`, then `pause -All -Apply`, then upgrade, then `restore -Snapshot <pre> -Apply`; plus the KB note that 7.5.1-or-earlier to 7.9.2+ resumes paused jobs because the Quartz `instanceName` changed)
- Modify: `references/gotchas.md` (new G-ids under "REST / PowerShell" for: an empty `/jobs/pause|resume` list means ALL jobs; and a move breaks dashboards that reference the moved resource. Use the next free ids)
- Modify: `references/jrs-rest-api.md` (cross-link the scripts from the Task 0 sections)
- Modify: `plugins/jasper-deploy/CHANGELOG.md` (a `## 1.4.0 (<date>)` entry listing every change in this plan, and stating whether it was validated on STAGE only), `plugins/jasper-deploy/.claude-plugin/plugin.json` (`"version": "1.4.0"`)

- [ ] **Step 1:** Make the edits above. ASCII only.
- [ ] **Step 2:** Run `pwsh -NoProfile -File scripts/check_docs.ps1`. Expected: exit 0 (no broken links, every script in `scripts/` mentioned in `SKILL.md`).
- [ ] **Step 3:** Run `pwsh -NoProfile -File scripts/smoke_test.ps1` (or the offline Pester part only, if STAGE is down). Expected: PASS.
- [ ] **Step 4: Commit**

```bash
git add plugins/jasper-deploy/
git commit -m "docs(jasper-deploy): 1.4.0 - scheduler pause/resume/snapshot/restore and relocate_resource"
```

---

### Task 7: STAGE acceptance (human-run `-Apply`; PROD is not contacted)

- [ ] **Step 1:** Relocate on STAGE: deploy a throwaway report to `/reports/_smoke/relocate/src`. Run `relocate_resource.ps1 -Source /reports/_smoke/relocate/src/<r> -TargetFolder /reports/_smoke/relocate/dst -CreateFolders` (plan), then the same with `-Move -Apply`, then run the report to PDF (`%PDF-` magic), then `recover_run.ps1 -RunId latest -Rollback -Apply` (expected exit 3) and confirm the source is back.
- [ ] **Step 2:** Jobs on STAGE: create two throwaway future-dated jobs on that report, then run `snapshot`, `pause -Id <a>,<b> -Apply`, `state -Id <a>,<b>` (both PAUSED), `restore -Snapshot <file> -Apply` (both NORMAL), then delete both jobs. **Do not use `-All` on STAGE** unless every existing STAGE job is a throwaway.
- [ ] **Step 3:** Run `verify_suite.ps1` on STAGE. Expected: PASS (the existing suite is unaffected).
- [ ] **Step 4:** Remove `/reports/_smoke/relocate`, record the STAGE results in the CHANGELOG 1.4.0 entry, and commit.
