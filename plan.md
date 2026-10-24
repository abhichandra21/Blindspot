# Blindspot fix plan and handoff

## Start here

Read [AGENTS.md](AGENTS.md) and [charter.md](charter.md) first.
Since item 2, the Claude sessions `fix-coordinator`, `code-writer`, and `code-reviewer` replace the Codex sessions named below; `code-reviewer` also gets a Codex review of each item.
Items 1, 2, 3, 5, 6, and 6b are committed on the `review-fixes` branch, one commit each, and pushed to draft PR https://github.com/abhichandra21/Blindspot/pull/1.
The next implementation item is item 7; item 4 is the owner's live test.
The owner will run the item 4 live Teams call once, after all other items, covering every fix together.
If a fix or check needs a live call, record it under item 4 and move on; do not block other items on it.

Item 1 was done by the earlier Codex sessions: `plan-execution` implemented it and `code-review` reviewed it with no findings.

The owner is the developer, tester, maintainer, and currently the sole user.
Explain changes in plain language, with a concrete example when useful.
Keep this a small Apple-silicon Teams app.
No Intel support, Apple developer account, notarization, other meeting-app detectors, or larger framework is wanted.
A personal Homebrew tap is useful later if it genuinely simplifies installation and updates.
The coordinator commits each accepted item on `review-fixes` without asking again.
No pushes, merges, other branch changes, releases, issues, PRs, or remote tap creation are authorized.

## State at the original item 1 handoff

This is the snapshot from before item 2; the current state is in the Start here section.
Snapshot verified on 23 October 2026 at 19:55 CDT.

- Repository: `/Users/abhishek.chandra/Data/Codebase/Blindspot`.
- Branch: `main`.
- HEAD: `a25e60339dd603a249511c94bdc015c4019ddaf2`.
- Modified tracked file: `main.swift`, with 52 additions and 21 deletions for item 1.
- New implementation file: `tests/StatusTests.swift`, 128 lines, still untracked.
- New agreed project instructions: `AGENTS.md` and `charter.md`, still untracked.
- Pre-existing unrelated file: `docs/images/social-preview.png`, still untracked; preserve it.
- No implementation commit was made and the installed/running app was not replaced or relaunched.
- Item 1 has passed code review and deterministic checks; live UI and Teams behavior have not been tested.

Snapshot SHA-256 values:

```text
main.swift
de15f979ed824d1d3461d3ec4756d608a64ac0d58ef207bd7671c739bae96b76
tests/StatusTests.swift
c202f8821e304ab314545adfe97b531ba02a2bec2afb833c786a5f5dedc13982
```

Check the actual files and Git status before continuing.
If they differ from this snapshot, inspect the differences instead of overwriting them.
The old Word report's source links refer to the original commit; current line numbers have moved.
The updated Word report is `/Users/abhishek.chandra/Documents/Blindspot Code Review.docx`.

## Sessions and agreement

All three sessions agreed to the charter before item 1 began.
They share the same worktree.

- Coordinator/review-report session: `01a16aed-d336-7773-a373-07842641001d`.
- Implementation session `plan-execution`: `01a16b01-e58f-7320-826f-bb08ba4fa4eb`.
- Read-only review session `code-review`: `01a16b5a-fc57-7621-bd43-94a9c8deb50a`.

Use `code-review` for reviews, as the owner requested.
If the session tools are available, `read_thread` reads status, `send_message_to_thread` sends a task, and `wait_threads` waits for results.
Do not confuse them with child-agent tools that can only address agents created in the current conversation.
Both named sessions were told to stop after item 1; do not dispatch another item until the owner resumes development with the next agent.
Use only one code writer at a time.

## What item 1 changed

- `GuardState` now has `checksDisabled`, `observationFailed`, and a shared `statusText` mapping used by the actual UI.
- `onScreenWindows()` returns nil on a failed read instead of disguising failure as an empty successful list.
- `displayBounds()` checks CoreGraphics return values and returns nil on failure.
- `currentState` accepts injectable permission, window, and display providers plus selected tabs and pause state.
- State order is paused, no tabs selected, missing permission, failed window read, no indicator, failed display read, then exposure classification.
- No tabs selected says `Checks disabled: no Teams tabs selected`.
- Failed observation says `Unable to check Teams sharing` and uses an orange shield.
- No indicator says `No Teams share detected`.
- A clear share says `Sharing; no watched Teams windows detected in the shared area`.
- `BLINDSPOT_TESTING` selects the test entry point without launching AppKit or prompting for permissions.
- Exposure geometry, automatic minimizing, retries, sounds, banner placement, saved preferences, permission requests, and login behavior were intentionally left unchanged.

Current source anchors:

- `main.swift:118`: states and status text.
- `main.swift:143`: window metadata read.
- `main.swift:160`: display metadata read.
- `main.swift:168`: whole-display heuristic.
- `main.swift:177`: production detector and test seam.
- `main.swift:213`: Accessibility minimizing.
- `main.swift:275`: refresh, minimize dispatch, and UI updates.
- `main.swift:334`: banner placement.
- `main.swift:405`: Settings controller.
- `main.swift:667`: test entry guard.
- `tests/StatusTests.swift`: the production regression checks.

## Reproduce the checks

Run from the repository root.
These commands write build output outside the repository and do not launch the app.
The tests in `Tests/BlindspotTests` import the production `Blindspot` target with `@testable import`; they do not carry a copied detector implementation.
Running the tests needs full Xcode for XCTest.

```bash
set -euo pipefail
blindspot_check_dir=$(mktemp -d /tmp/blindspot-check.XXXXXX)
swift test --scratch-path "$blindspot_check_dir/build"
# Same compile as build.sh, so the SDK stamp matches the shipped app.
swiftc -O -target arm64-apple-macos13.0 -module-cache-path "$blindspot_check_dir/module-cache" Sources/Blindspot/*.swift -o "$blindspot_check_dir/Blindspot"
xcrun vtool -show-build "$blindspot_check_dir/Blindspot"
git diff --check
```

Expected current result since item 6b: 12 XCTest methods with 117 assertions pass, the release build succeeds, and the binary reports `minos 13.0` with `sdk` equal to `xcrun --show-sdk-version`.
The results below for item 1 refer to the earlier single-file commands.

Expected result for item 1: 30/30 checks pass, production compilation succeeds, and the binary reports `minos 13.0`.
That minimum-target check is not a runtime test on macOS 13.

The implementer demonstrated 11 failures among the same 30 checks before the behavior fix, then 30/30 afterward.
`code-review` independently compiled both paths, ran all 30 checks, inspected the red evidence, and reported zero findings.
Temporary implementation evidence is in `/tmp/blindspot-item1.htIIzD`: `red-results.txt`, `test-results.txt`, `main-before-fix.swift`, and binaries.
The coordinator also reran checks using `/tmp/blindspot-handoff.rHCvmP`.
Temporary paths may disappear; the source and commands above are the durable way to reproduce the checks.

Do not run `./build.sh` in the repository just to verify compilation: it deletes and recreates the local `Blindspot.app`.
To verify the bundle, copy the required source/build inputs to a temporary directory and run the script there.
The script may use the existing local signing identity through Keychain; do not export a key or change signing configuration for a check.

## Work order and completion checks

- [x] 1. Truthful disabled/error/no-match statuses: implemented, regression checks passed, code review passed.
- [x] 2. Safer automatic minimizing: implemented, 45/45 regression checks passed, code review passed after one fix. Open limit the owner chose to leave for item 4: a maximized-window share can look like a whole-display share, so a chat behind it may still be warned about and minimized. Codex rejected item 2 over this limit only. Also untested: whether Teams' AX frames match CG bounds within 1 point (if not, minimizing is safely skipped every time).
- [x] 3. Warnings before bounded Accessibility work: implemented, 69/69 regression checks passed, code review passed after one fix. Known limits: a cancel that lands just after the final "still wanted" check cannot stop that one AX write; if the share switches between displays while an attempt is still reading, with no gap where nothing is exposed, the earlier display's chat can still be minimized (small fix if wanted: cancel when targets change). Codex rejected item 3 over these two limits only. Untested live: warning drawing before the attempt, whether the 1 s AX timeout suits a busy Teams. Item 7 must describe the new "Not minimized: ..." menu line and tooltip.
- [ ] 4. Real Teams share and display checks: not performed.
- [x] 5. Clear first-run permissions and safe warning preview: implemented, 95/95 regression checks passed, code review and Codex accepted after three fixes. Minimizing is now opt-in when no choice was stored (old versions stored it only on a checkbox click). The test warning shows only while checks run and nothing is shared. Known limit: the test sound can overlap a real warning's sound within about 1 s. Tests keep their settings under the temp dir, not ~/Library/Preferences. Open for the item 4 call: first-launch Settings flow, the Allow button and prompt, the relaunch hint, the test banner on one and two screens and its refusals, the Accessibility prompt when minimizing is turned on, and the new Settings layout. Item 7 must refresh settings-permissions.png and describe the new Settings text.
- [x] 6. Reliable Start at Login: implemented, 117/117 regression checks passed, code review accepted with no findings. Codex rejected over one limit. Known limits: if launchctl enable succeeds but the follow-up check fails, the box stays on with "Couldn't check Start at Login."; if a stale plist is repaired and then launchctl enable fails, the box shows off while the repaired plist may still start this copy at the next login (the next Settings open shows the truth). Item 4 caution: do not toggle Start at Login in a temporary test build, or the real login entry will point at it; turn it on again from the real copy afterwards. Open for the item 4 call: a real login after enabling, moving the app and re-enabling, real print-disabled output, and the login label in Settings.
- [x] 6b. Swift package layout (owner decision), done: code review and Codex accepted after one fix (build.sh keeps compiling with swiftc so the app records the real SDK). Originally planned as: move code from main.swift into a few files under `Sources/Blindspot/` (detection, minimizing, login item, settings, app entry), convert the tests to a `Tests/` target run with `swift test`, and keep `build.sh` producing the same signed `.app`. No behavior changes; all existing checks must still pass. Done before item 7 so the docs describe the final layout.
- [ ] 7. Accurate existing documentation and warning screenshot: not started.
- [ ] 8. A simple app icon: not started.
- [ ] 9. Smaller CI permissions and pinned actions: not started.
- [ ] 10. A personal Homebrew cask: not started.

For each item, record the pre-change diff, explain the smallest plan in the session, add a meaningful failing regression for logic changes, implement only that item, rerun relevant checks, and send the entire item change to `code-review`.
HEAD will remain the same while changes are uncommitted, so use a temporary before/after snapshot or item patch to separate each item from earlier accepted work.
The reviewer must also inspect new untracked test or asset files; `git diff HEAD` alone omits them.
Do not move to another code fix while the active fix has unresolved in-scope findings.
Keep required owner-operated live checks open; independent fixes can continue after review without pretending those checks passed.

## Item 2 Make automatic minimizing choose safely

**Files:** `main.swift`, primarily `WindowInfo`, `GuardState`, `currentState`, `minimize`, and `AppDelegate.refresh`; extend the existing regression file.

1. Preserve the warning for a watched window on a shared display, including a small strip visible behind iTerm and the accepted fully-covered false positive.
2. Separate windows that warrant a warning from windows that may be automatically minimized.
   The current `.chatExposed` state carries only windows and a rectangle, so the minimize caller currently loses the display/window distinction.
   Carry the smallest extra mode/eligibility information needed; do not create a detector framework.
3. For a share classified as a window rather than a display, keep the warning but do not automatically minimize merely because the overlap passes 50 percent.
4. Do not claim equal bounds prove capture identity.
   The existing 60-point origin and 120-point size tolerance can classify an almost-full-screen window as a display.
   Establish what the supported Teams indicator actually distinguishes; if maximized-window and display shares remain indistinguishable, keep that limitation explicit and ask the owner before introducing a new user choice or claiming it is solved.
5. Revalidate the Accessibility target using its PID, title, and window bounds in matching coordinate units.
   Read the public AX position/size attributes; do not use a private window-number API.
   Require one unambiguous candidate.
   If two windows still match, skip automatic action and retain the warning.
   If the title, bounds, or process changed since observation, skip the stale target.
6. Keep a result that distinguishes a successful minimize, an ambiguous/skipped target, and an API failure so item 3 can display a useful outcome.
   Keep private titles out of logs.

**Regression cases:** display share with partial Chat overlap; Chat on another display; separate chat behind a shared presentation; two same-title AX windows at different positions; two indistinguishable AX candidates; a moved or retitled candidate; unsupported/read-failed AX attributes.
Use synthetic records at the pure selection seam and a thin AX adapter; do not minimize real windows from unit tests.
The existing tests for the 50-percent rule currently document warning classification, not safe minimize eligibility; adjust them only for an intentional change to that contract.

**Finished when:** display-share warnings remain sensitive, known ambiguous cases do not trigger automatic minimizing, regression checks and the normal build pass, and `code-review` accepts the actual change.
Actual Teams indicator behavior remains an owner/live-test question until observed.

## Item 3 Show warnings before potentially slow work

**Files:** `main.swift` around `refresh`, `minimize`, pause/settings callbacks, and the existing test seam.

1. Update warning state, icon, sound, and safe banner before starting the minimize attempt.
   Merely moving assignments earlier is insufficient if the main run loop stays blocked before AppKit can draw.
2. Keep AppKit/UI operations on the main thread.
   Use the smallest single-in-flight mechanism for AX work if background execution is needed; do not queue another attempt every second while one is still running.
3. Set a short AX messaging timeout using `AXUIElementSetMessagingTimeout`.
   Verify the documented scope: setting it on the application element alone does not automatically set it on every child window.
   Either use the process-wide system element timeout or set it on each queried/written element.
   Give timeout values names with seconds in them.
4. Avoid applying a queued stale action after pause, checks being disabled, minimizing being switched off, or the share ending.
   Keep this cancellation/state check small and tied to the current attempt.
5. Surface inability to minimize while retaining the exposure warning.
   Preserve the retry behavior when the app is enabled and permission becomes available.

**Regression cases:** warning delivered before a fake delayed/failed action; only one attempt in flight; pause or a changed share invalidates pending work; no retry when minimizing is off; retry after a transient failure; failure does not become a clear-share status.
Use injected effects/clock or a small action seam instead of real Teams or long sleeps.

**Finished when:** tests and build pass, the main thread is not held by the minimize path, and `code-review` accepts the result.
A real UI delay test remains separate from deterministic callback ordering.

## Item 4 Verify the actual Teams behavior

**Type:** owner-operated testing, not an instruction to invent a meeting or alter permissions automatically.
The test app must be built from the changed source; an already-running older app does not validate the new code.
Use dummy content and get explicit permission before replacing/relaunching the owner's installed copy or operating their windows.

- [ ] Whole-display share starts and stops with correct status changes.
- [ ] Chat and Activity each trigger when selected and do not trigger when deselected.
- [ ] A partly visible Chat behind iTerm triggers the warning and permitted automatic minimizing.
- [ ] A completely covered Chat produces the documented conservative warning.
- [ ] A watched window on an unshared display does not trigger exposure on the shared display.
- [ ] A single-display setup uses sound and red icon without placing the banner into the share.
- [ ] An available second display receives the banner; switching the shared display never leaves the banner on it.
- [ ] Adding/removing/rearranging a display refreshes banner placement even when exposure data has not otherwise changed.
- [ ] Minimize and restore exercise the retry behavior; failed or denied minimizing leaves the warning understandable.
- [ ] No selected tabs shows disabled; pause and resume behave as stated.
- [ ] Denied/revoked Screen Recording shows missing permission; Accessibility remains optional for warnings.
- [ ] Granting access, and relaunching if macOS requests it, restores checking.
- [ ] Teams restart and sleep/wake recover without duplicate warnings or stale state.
- [ ] A single-window share is treated according to the explicit supported limitation, not assumed to be a display.
- [ ] Share a maximized window with a chat behind it: record whether the app treats it as a whole-display share. The reviewer suggested a tighter size check for minimizing only; that needs the owner's decision.
- [ ] Automatic minimizing actually finds the exposed chat (the window position Teams reports matches the app's within 1 point).

Record macOS and Teams versions, share mode, displays, selected tabs, permissions, and observed results without copying private chat titles.
Do not call unobserved pop-out, meeting-chat, localized-title, or concurrent-indicator cases supported.
If a concrete defect appears, stop and make it the next bounded correction; do not treat a failed manual check as an excuse for an unrelated rewrite.

## Item 5 Make permission setup understandable

**Files:** `Prefs`, `applicationDidFinishLaunching`, `SettingsWindowController`, `PermissionRow`, and existing install guidance when wording changes.

1. Reuse the existing Settings window for a short explanation of detection and minimizing.
   Avoid a new wizard or separate onboarding system.
2. Ask for Screen Recording only after the explanation is visible and the user takes the setup action.
   Keep later denied-permission recovery easy to find and avoid repeated prompt loops.
3. Request Accessibility only when the user explicitly enables minimizing.
   Preserve explicit stored true/false choices.
   For a missing stored choice, use warning-only until the user chooses minimizing; do not pretend the old version's implicit default proves consent.
   Explain that intentional change for users upgrading from an unstored default.
4. Show an understandable permission/relaunch hint when needed, using the existing System Settings links.
5. Add a warning preview that uses dummy text and never calls the actual minimize path.
   Respect the banner's shared-display avoidance; do not expose a preview on a display believed to be shared.

**Checks:** new preferences and existing explicit choices; no Accessibility prompt for warning-only use; enabling minimizing requests access; denial does not loop; preview does not mutate Teams; one-screen and two-screen preview behavior; no duplicate copy after permission relaunch.
Test defaults/prompt decisions with an isolated UserDefaults suite or a small decision seam, never the owner's actual defaults.
Perform visual checks with a deliberately launched test build only after approval.

## Item 6 Fix Start at Login without expanding the task

**Files:** `LoginItem` and Settings login handlers in `main.swift`; existing install/uninstall text only if required.

1. Read the owned plist and compare its executable path with the current bundle path.
   Repair a stale path when enabling the login item instead of only writing a missing file.
   Preserve the existing label, RunAtLoad, and KeepAlive-on-failure behavior.
2. Return and inspect launchctl exit status separately from output; a failed query is not proof that login is enabled.
3. Keep the prior known checkbox value and display a useful failure if writing or enabling fails.
   Do not silently show success.
4. Use Process arguments and filesystem APIs, including paths with spaces; do not build shell commands from app paths.
5. Keep the documented next-login behavior and never delete or reload unrelated LaunchAgents.
   Do not introduce SMAppService merely to avoid fixing these concrete cases.

**Checks:** absent plist, enabled and disabled output, query failure, write failure, a moved app path, enable/disable failure, unchanged owned plist fields, and a path with spaces.
Use a temporary home/plist directory and injected command runner.
Actual login/launchctl mutations require the owner's specific instruction; do not modify the real login entry during unit tests.

## Item 7 Update the existing documentation

**Files:** `README.md`, `docs/INSTALL.md`, `docs/BUILDING.md`; add a warning screenshot asset only when required.

1. Show the warning and red icon before settings screenshots.
   Capture a test example with dummy content; do not publish real contacts or chat text.
2. Explain the new disabled/error statuses and that detection checks approximately once per second.
3. State the supported hardware, observed Teams title patterns, tested share modes, and the conservative covered-window warning.
4. State that separate notification banners are outside the current tab-window model and link to the Teams Do not disturb while sharing setting.
5. Explain that window metadata is read locally, settings/login information is stored, and the diagnostic command may print titles.
6. Keep the normal macOS approval steps and optional Accessibility explanation accurate.
   Describe possible permission resets after changed ad-hoc builds without claiming every update always breaks both grants.
7. Do not prescribe an Apple developer account, add a website, or add separate planning/marketing documents.

**Checks:** every described status and default matches the final code; links work; install/update/uninstall instructions agree; screenshots have no private data; unsupported cases are not advertised as verified.
Inspect documentation diffs directly; do not add tests that merely assert prose strings.

## Item 8 Add a simple bundle icon

**Files:** one original icon asset such as `assets/Blindspot.icns` and `build.sh`; a small generator only if needed to maintain it.

1. Make original, recognizable shield artwork that remains legible at small sizes.
   Do not copy an SF Symbol as an app logo or turn this into a branding project.
2. Package the icon into `Contents/Resources` and set `CFBundleIconFile` in Info.plist.
3. Copy resources before signing so the bundle seal includes them.
4. Keep architecture, bundle identifier, minimum macOS, and version behavior unchanged.

**Checks:** build the bundle in temp; run `plutil -lint` and `codesign --verify --strict`; inspect the icon at small and large sizes and confirm the bundle resource/key exists.
Finder and System Settings may cache icons; a stale cached display is not by itself proof the asset is missing.
Preserve the unrelated social-preview image.

## Item 9 Tighten the existing CI workflow

**Files:** `.github/workflows/build.yml`; `build.sh` only if a directly required change is identified.

1. Set ordinary builds to contents read access and disable checkout credential persistence when unnecessary.
2. Use a separate tag-only release job with contents write access and `needs` on the successful build.
   GitHub token permissions cannot be scoped to a single step.
3. Pass the ZIP from the build job to the release job and preserve ZIP bundle attributes.
   If the release job does not check out Git, set `GH_REPO` or use `gh --repo "$GITHUB_REPOSITORY"` so publishing does not rely on a missing local repository.
4. Pin each used GitHub action to a verified full commit SHA from its official repository.
   Verify those revisions live; do not invent hashes or reuse stale values from a plan.
5. Select a currently available, tested macOS runner/toolchain baseline instead of assuming macos-latest is reproducible.
   Verify availability before naming a version.
6. Keep PR builds, main pushes, and tag versioning/release packaging working.
   Do not introduce signing secrets or an Apple account.

7. After the item 6b split, add a `swift test` step so CI runs the regression checks.

**Checks:** `actionlint`, `bash -n build.sh`, temporary local bundle build, plist/signature checks, and review of each event path and permissions block.
Do not push a tag or trigger a release merely to test the workflow.
Record any GitHub runtime execution that still needs approval.

## Item 10 Prepare a personal Homebrew cask

**Files:** a local draft such as `Casks/blindspot.rb` and the existing install guide.
Creating a remote `homebrew-*` repository or publishing a release needs explicit approval.

1. Use a real published version and its exact ZIP URL; download the actual asset and compute its SHA-256.
   Do not invent a future release or checksum for the uncommitted fixes.
2. Declare arm64 and the actual supported macOS minimum; install the app bundle with the standard app stanza.
3. Keep quarantine enabled and explain Open Anyway, Screen Recording, optional Accessibility, and possible update re-grants in caveats.
   Do not remove quarantine, grant permissions, import certificates, or disable Gatekeeper in hooks.
4. Run static cask/style checks and verify the download without replacing the owner's app.
5. With the owner's approval, test one fresh install, one upgrade, and uninstall in a controlled location.
   Check the installed path, login item, and permissions after upgrade.
   Do not delete preferences or signing identities by default.
6. Keep the README/manual ZIP path valid for people who do not use Homebrew.
   Do not pursue official Homebrew cask admission under the no-Apple-account constraint.

**Finished when:** the local cask is reviewed, its real checksum/download is verified, any unperformed install/upgrade checks are explicit, and the owner approves any external publication separately.
Homebrew does not remove the macOS approval step or guarantee permission continuity.

## Do not add these to the current fixes

Intel/universal binaries, Apple membership or notarization, other meeting apps, a generalized localization configuration UI, Sparkle, a marketing site, a contribution program, a detector architecture, or measured performance claims without actual measurements.
License/social-preview housekeeping, timer tolerance/idle polling, a timed pause, and activating an existing copy are later tasks unless the owner explicitly reprioritizes them.

## Suggested skills and official references

Use implementation, focused test-first work, verification-before-completion, and code review skills when available, subject to the owner's instructions and charter.
Use the Documents skill if updating the Word report, including render-and-inspect verification.
Use Context7 for API documentation when available and official documentation as the disclosed fallback.

- AX timeouts: https://developer.apple.com/documentation/applicationservices/1459345-axuielementsetmessagingtimeout
- Service Management, if separately approved: https://developer.apple.com/documentation/servicemanagement/smappservice
- GitHub workflow permissions: https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax#permissions
- GitHub action security: https://docs.github.com/en/actions/reference/security/secure-use
- Homebrew personal taps: https://docs.brew.sh/How-to-Create-and-Maintain-a-Tap
- Cask format: https://docs.brew.sh/Cask-Cookbook
- Official cask limits: https://docs.brew.sh/Acceptable-Casks
- Teams presentation status: https://support.microsoft.com/en-us/teams/notifications-settings/change-your-status-in-microsoft-teams
