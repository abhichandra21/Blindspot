# Guidelines for a small Mac app

Lessons from building Blindspot, in the order you will meet them.

## 1. Set up the project right on day one

- Start as a Swift package: code in `Sources/`, tests in `Tests/`, run tests with `swift test`.
  Moving to this layout later cost a whole review round.
- Build the `.app` with a small `build.sh` that calls `swiftc` directly.
  `swift build` marked the app as built against an older macOS, which can change how windows look.
- Keep the logic apart from the UI.
  Pass in anything that touches the real system (settings storage, `launchctl`, window lists, Accessibility), so tests can swap in fakes.
- Tests must never touch the real Mac.
  Use temp folders, and put test settings in a temp file path; macOS leaves test settings files behind otherwise.
- Write each test so it fails before the fix and passes after.
  Otherwise you can't tell whether it tests anything.
- Generate the icon with a small script kept in the repo, and add a license on day one.

## 2. Permissions

- Never ask for a permission at launch.
  Explain what it is for first, and ask only when the user turns on the feature that needs it.
- Remember that you already asked, so you don't keep prompting.
  Show a "quit and reopen" hint, because Screen Recording often needs a restart to take effect.
- macOS ties permissions to the app's signature.
  A differently signed build counts as a new app and loses them, including a Homebrew copy versus your own build.
  Sign your own builds with one local certificate so permissions survive rebuilds.
- Anything that acts on the user's windows, like minimizing them, should be off until the user turns it on.

## 3. Behavior

- Never let calls to other apps freeze your app.
  Run them in the background with a timeout, one at a time, and drop results that arrive after the user has changed something.
- Show the warning first, then do the slow work.
- Status text should tell apart "turned off", "couldn't check", and "nothing found".
  Never show "all clear" when you couldn't actually check.
- When you aren't sure which window to act on, warn and do nothing.
  Don't guess.
- Never log private data such as window titles.
- If the app allows only one copy at a time, update steps must say "quit the old copy first".
- Start at Login: store the app's path, notice when it points to an old copy, and check whether `launchctl` actually succeeded.
- A window hidden from screen capture also can't be screenshotted for docs.
  Plan your images around that.

## 4. Shipping without an Apple developer account

- People's first launch will go wrong unless they're told exactly what to click: **Done**, not Move to Trash, then Privacy & Security > **Open Anyway**.
- Cleanup apps like AppCleaner will offer to delete your settings when the app gets trashed.
  Warn users to say no.
- Work Macs often have no admin rights, so `/Applications` may be off limits.
  Mention `~/Applications`.
- Homebrew: run your own tap, leave the "downloaded" flag on, make plain uninstall keep settings, and make the full uninstall (`--zap`) also switch off the login entry.

## 5. GitHub and releases

- Builds run with read-only access.
  Only a release job that runs on version tags gets write access.
- Pin every build tool to an exact version, including the Mac runner and Xcode.
  CI builds against GitHub's Xcode, which can differ from yours.
- After the first merge, protect `main`: changes go through a PR and the build must pass.
  Turn on Dependabot and secret scanning.
- Have one person or session merge.
  Clicking merge on GitHub while someone is still pushing lost commits twice.

## 6. Docs and website

- Quote every message and button label exactly as the code has it, and never promise more than the code does.
- Publish the website only after a release exists that matches what the page says.
  Keep it free of trackers, and check that its text is easy to read in light and dark mode.

## 7. How to work

- Fix one item at a time, with a short plan, tests that fail first, a separate reviewer plus a second-opinion review, and one commit per item.
- Do the live test once at the end, with fake data, covering everything.
- Write down known limits instead of chasing rare cases.
