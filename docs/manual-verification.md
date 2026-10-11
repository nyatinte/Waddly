# v1.0 manual verification plan

Use this plan on a real Apple Silicon Mac with the v1.0 candidate. These checks exercise macOS permission, login-item, display, and lifecycle behavior that automated tests do not fully cover.

## Results record

Copy this block into the results for each run. Record completed results in the linked issues (#63, #65, #67, #68) and, where relevant, [the release E2E report](release-e2e-2026-10-05.md). Record Homebrew and DMG results in [the dedicated Homebrew verification checklist](homebrew-verification.md) under #66.

- Date/time and time zone:
- Tester:
- Mac model / chip:
- macOS version and build:
- Waddly version:
- Waddly commit:
- DMG filename and SHA-256 (if applicable):
- Test app location (`/Applications`, mounted DMG, or build directory):

| Check | Pass / fail / not run | Evidence or failure notes |
| --- | --- | --- |
| #63 Input Monitoring permission lifecycle | | |
| #68 Login item | | |
| #67 Long run and sleep/wake | | |
| #65 Display, Spaces, fullscreen, and scale | | |
| #66 Homebrew and DMG | See linked checklist | |

For every failed check, capture the Waddly version/commit and macOS version, exact reproduction steps, expected and actual result, screenshots or a short screen recording, and relevant Console messages or logs with timestamps. Do not capture or share typed content or key codes.

## #63 Input Monitoring permission lifecycle

**Preconditions:** Use the release candidate in `/Applications` where possible, a configured pet image, and a text editor with a blank document. In System Settings → Privacy & Security → Input Monitoring, remove any existing Waddly entry before the fresh-permission cases. Keep the same Waddly installation identity throughout each case. Use a harmless test document; the app should react to input without collecting it.

### Fresh grant

1. **Precondition:** Waddly is quit, its Input Monitoring entry is absent, and no other Waddly instance is running. **Action:** Launch Waddly and follow the setup wizard to its Input Monitoring step; enable Waddly in the system permission list, return to the wizard, and then type a few ordinary characters and press Enter in the test editor. **Expected result:** Setup reports that Input Monitoring is allowed; the menu tooltip indicates that Waddly is reacting to keyboard input; menu state reflects active monitoring; the pet reacts to input, including its Enter response. **On failure, capture:** Wizard status, menu open with tooltip/state visible, permission-list state, and a timestamped screen recording of the test.

### Deny

2. **Precondition:** Remove Waddly from the Input Monitoring list and quit it. **Action:** Launch Waddly, decline or leave the permission disabled when prompted, then inspect the setup wizard and menu and type in the test editor. **Expected result:** The wizard reports that permission is required, the menu tooltip indicates permission is required, menu state does not claim active monitoring, and the pet does not react to keyboard input; the rest of the app remains usable. **On failure, capture:** Wizard, menu tooltip/state, permission-list state, and a timestamped screen recording.

### Revoke while running and re-grant without restarting

3. **Precondition:** Waddly is running with permission granted and actively reacting; keep its menu and the test editor available. **Action:** In System Settings → Privacy & Security → Input Monitoring, switch Waddly off while it remains running. Return to Waddly and observe its setup status, menu tooltip/state, and input response. Then turn Waddly back on, return to the already-running app, and test ordinary input and Enter again without quitting or relaunching Waddly. **Expected result:** After revocation, the app detects the permission loss, shows the required-permission wizard/status and tooltip, no longer indicates active monitoring, and stops reacting. After re-grant, the already-running app updates its status and menu to active and the event tap resumes responding without restarting Waddly. **On failure, capture:** A screen recording spanning both permission changes, timestamps, wizard and menu states after each change, and process uptime/PID (do not record any typed text or key codes).

## #68 Login item

**Preconditions:** Use a disposable test account or otherwise coordinate logout/reboot tests. Have a copy of the release candidate available in `/Applications`; separately test a DMG-mounted app and a `build/Waddly.app` copy. Note the exact bundle path for each run. A macOS login-item notification or System Settings confirmation may be part of the expected OS flow.

### Register and unregister from the menu; persistence across relaunch

1. **Precondition:** Waddly is running from `/Applications`; inspect the current login-item status before changing it. **Action:** Open the menu, select the login-item toggle, verify its selected/checkmarked state, quit Waddly normally, relaunch it, and inspect the menu again. Toggle the item off, quit and relaunch once more. **Expected result:** Registration and unregistration are available from the menu; the checkmark agrees with `SMAppService` status after each change and persists across relaunch; the off state also persists. **On failure, capture:** Menu before/after each toggle, any macOS notification or dialog, app path, and status before and after relaunch.

### Launch after logout/login and reboot

2. **Precondition:** The app is installed in `/Applications`, the login item is enabled, and no Waddly instance is open. **Action:** Log out and back in, confirm whether Waddly launches; then, with the item still enabled, restart the Mac and confirm whether Waddly launches after login. **Expected result:** Waddly launches automatically after both logout/login and reboot/login, without manual launch. **On failure, capture:** Whether the login item remained enabled, login time, app path, relevant Login Items & Extensions settings, and a recording or timestamped screenshots after login.

### Non-`/Applications` locations and surfaced errors

3. **Precondition:** Use a test account and copies of the same candidate in a mounted DMG and in the build directory; ensure no other copy is running and note which copy is launched. **Action:** For each location, launch that copy, try enabling the login item from the menu, inspect the checkmark and any error, then try disabling it if registration succeeded. **Expected result:** The app's displayed menu state must agree with the actual `SMAppService` status. If macOS rejects registration from that location, Waddly surfaces an actionable error instead of silently showing registration as successful; record whether the OS allows it for each location. **On failure, capture:** Exact app path, menu state, full error text/dialog, relevant System Settings login-item entry, and Console messages at the time of the attempt.

## #67 Long run and sleep/wake

**Preconditions:** Use the Release app and a configured pet with multiple sleep frames. Grant Input Monitoring, disable automatic display sleep for the duration of the idle test (but do not prevent the explicit system sleep test), and close unrelated Waddly instances. Keep the pet visible. For memory context and exact sampler output, follow [docs/MEMORY.md](MEMORY.md), which documents `macos/profile-memory.sh`, RSS and physical-footprint samples, and their limitations. Do not treat a short sample or a single startup reading as evidence of bounded long-run memory.

### Real-time idle, sleeping, frozen, and wake-on-input

1. **Precondition:** Waddly is running, active, and not paused; note the last-input time. **Action:** Stop all keyboard input and observe in real time through at least 325 seconds after the last input, then type once in the test editor. **Expected result:** The pet transitions from active to sleeping after 25 seconds, remains in its sleep animation, becomes frozen after 325 seconds, and wakes/reacts on the next input. Transitions should not be skipped or replayed as a burst after delays. **On failure, capture:** Timestamped continuous video or periodic screenshots with elapsed times, plus relevant logs.

### Idle run of at least 325 seconds and memory behavior

2. **Precondition:** Launch the Release app and start the sampler using the workflow in [docs/MEMORY.md](MEMORY.md); identify the Waddly PID and keep it unchanged. **Action:** Run `./macos/profile-memory.sh PID sleep-frozen 360` (replace `PID` with the app process ID), do not type for the full sample, and inspect the generated `rss.csv`, `footprint.txt`, `summary.txt`, and `environment.txt` under `dist/memory/`. **Expected result:** The sample includes at least 325 seconds of idle time and reaches frozen; animation stops at the frozen state, and memory settles to a bounded plateau rather than showing sustained unbounded growth. Record RSS and physical footprint separately; samples can miss short spikes, and no universal budget is established by one run. **On failure, capture:** The complete timestamped sampler output directory, app PID/age, screen recording or state timestamps, and any profile-memory permission errors. Repeat comparable runs before concluding that a trend is real.

### System sleep/wake cycle

3. **Precondition:** Waddly is running with permission granted and visible; note its phase and ensure the login-item setting is not being changed. **Action:** Put the Mac to sleep using the Apple menu, wait at least 30 seconds, wake and unlock it, then observe Waddly without restarting it; test input once the desktop is ready. **Expected result:** The app remains responsive after wake, shows the phase appropriate to elapsed idle time (normally frozen after a long sleep), and resumes reacting to input without a stuck animation, stale panel, or restart. **On failure, capture:** Sleep/wake timestamps, screen recording immediately after wake, app process uptime, phase before and after, and relevant system/app logs.

## #65 Display, Spaces, fullscreen, and scale

**Preconditions:** Use a configured, visible pet and grant Input Monitoring. If possible, use a second display and a fullscreen-capable app. Note the pet's initial display, location, and display-size setting. Waddly's pet panel is expected to join all Spaces and remain stationary; this check verifies that it stays visible and reachable under real display changes rather than assuming that panel configuration guarantees it.

1. **Precondition:** The pet is visible on the external display, with a second display available. **Action:** Disconnect that display, inspect the remaining desktop, reconnect it, and inspect both displays. **Expected result:** The panel remains visible on an available screen when the display is disconnected and remains reachable after reconnection; it is not stranded off-screen or duplicated as an inaccessible panel. **On failure, capture:** A continuous recording or screenshots before disconnection, after disconnection, and after reconnection, including display arrangement and Waddly panel position.

2. **Precondition:** Waddly is visible on a normal desktop. **Action:** Switch between at least two Spaces using Mission Control or the keyboard, observing each Space. **Expected result:** The pet panel is visible and reachable across Spaces, consistent with its all-Spaces behavior, and does not become stranded behind a Space transition. **On failure, capture:** Screenshots or recording of each Space and the panel visibility/position.

3. **Precondition:** A fullscreen-capable app is open and Waddly is visible before fullscreen. **Action:** Enter and exit fullscreen, checking whether Waddly remains visible and whether it can be reached using the normal Space-switching controls. **Expected result:** Record whether macOS places the panel over the fullscreen app or in a separate Space; in either case, the pet remains reachable and returns to a usable visible position on exit, with no inaccessible or stuck panel. **On failure, capture:** Recording of entry/exit, Space transitions, and panel location.

4. **Precondition:** The pet is visible and the current display resolution/scale and Waddly display-size setting are recorded. **Action:** Change the display resolution or scaling in System Settings → Displays, return to the desktop, and inspect the panel; then restore the original scale. **Expected result:** The pet remains visible, correctly rendered, and reachable after the scale change and restoration; its on-screen location is usable and the panel is not clipped or stranded off-screen. **On failure, capture:** Before/after display settings, screenshots showing the panel bounds, and whether the original setting restores the prior placement.

## #66 Homebrew and DMG

Run [docs/homebrew-verification.md](homebrew-verification.md) for fresh install, upgrade, uninstall, and first-launch-from-quarantined-DMG checks. Record the DMG checksum and results there or in issue #66; do not duplicate that checklist in this plan.
