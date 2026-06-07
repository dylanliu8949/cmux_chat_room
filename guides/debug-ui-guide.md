# UI Test Debugging Guide

This guide covers Ralph-specific constraints and codebase-specific knowledge for debugging UI test failures. General debugging skills are assumed.

## Guardrails

These rules exist because Ralph runs unsupervised.

1. **Never delete tests** - Developers check commit history, deleting tests is not a solution
2. **Don't blindly increase wait times** - If an operation doesn't work, increasing `sleep` almost never helps. Check coordinate calculations, gesture parameters, or app state instead
3. **Partial progress over risky attempts** - Fix what you're confident about first

## Test Trust Levels

### e2e-tests (Stable)
- Location: `ui-test/e2e-tests/`
- Must pass CI pre-merge
- **If failing: the code change has a problem, not the test**

### feature-tests (May be unstable)
- Location: `ui-test/feature-tests/`
- **If failing: could be a code issue or a test implementation issue**

## Debug HTTP Server

The app runs an HTTP debug server during testing:
- iOS: port `8765` (direct)
- Android: port `8765` on device, mapped to host `8766` via `adb forward`

```bash
curl http://localhost:8765/editor/state | jq                              # Full editor state
curl http://localhost:8765/canvas/element/{element_id}/screen-bounds | jq # Element screen coords
```

### 🚫 Read-only — never use this server to mutate state

The debug server is **read-only by design**. Every endpoint is a GET that reads state out of `EditorService`; no endpoint calls a mutating API (`mergeCells`, `insertRow`, `deleteColumn`, `updateElement`, `setInteractionMode`, etc.) and none ever will.

When a UI test needs to trigger an action, it MUST issue a real Appium tap/drag that flows through Compose → gesture recognizer → service — the same path a user takes. Shortcutting via a hypothetical "debug mutation endpoint" is explicitly banned because:

- It silently skips the gesture recognizer and the render pipeline, so regressions there pass unnoticed while the test reports green.
- It produces a false sense of coverage: the test claims "merge works" when what actually works is the service method in isolation (already covered by unit tests).
- It invites a creeping surface where every hard-to-reproduce gesture gets a backdoor, and eventually the UI test suite stops testing the UI.

If an invariant genuinely isn't reachable from the UI (e.g., `BatchCommand` cascade-commit when structural mutations happen while `TEXT_EDITING` — the mobile TablePropertiesBar is hidden in that mode and offers no trigger), that invariant belongs in a service-layer unit test, not in a debug-server endpoint. Don't propose adding one to work around a UI limitation.

When reviewing a PR that adds a debug-server endpoint: ask "does this read or write?". If it writes, reject.

## Log Timestamp Correlation

Test output and app logs both use `[ms]` timestamps relative to `TestClock` start. The delay between them depends on Appium action type:

| Action Type | Latency |
|-------------|---------|
| Debug HTTP request | ~0-5ms |
| Appium element click (accessibility ID) | ~20-30ms |
| W3C Actions (coordinate tap/drag) | ~250-270ms |

To debug: find the failing step timestamp in test output, then look at app logs offset by the appropriate latency. If the app interpreted the gesture as the wrong type (e.g., resize → multi-select), the bug is in gesture recognition or coordinate calculation.

## Run Artifacts

Each test run creates a timestamped folder:
```
ui-test/.run/<timestamp>/
├── android_build.log / ios_build.log     ← App build output captured during launch
├── android_appium.log / ios_appium.log   ← Appium server log
├── android_test.log / ios_test.log       ← pytest output
├── android_app.log / ios_app.log         ← Device log (filtered by app)
├── android_renderer.log / ios_renderer.log ← Renderer log (Renderer/ tagged lines from app log)
├── android_crash.log / ios_crash.log     ← Crash artifacts captured after the run
├── ios_crash_reports/                    ← Raw copied iOS `.ips` / `.crash` reports when present
├── *_milestone_*.png                    ← Milestone screenshots at key test phases (480p)
├── *_final_screenshot.png               ← Screenshot at test end (pass or fail)
└── env.sh                                ← Runtime state (device serial, clock offset, etc.)
```

**Milestone screenshots** (`*_milestone_*.png`) are captured at key test phase transitions (e.g., after text insertion, after poem typing, after select-all). **Use these to understand the visual state of the app when debugging a failure** — they show exactly what the canvas looked like at each phase without needing to watch a video recording. Read the screenshot image file with the `Read` tool to see the app state visually.

**Intermediate screenshots** (`*_intermediate_screenshot_N.png`) are captured between test phases (e.g., after completing all alignment tests, before deleting elements for the next phase). They use sequential numbering: `intermediate_screenshot_1`, `intermediate_screenshot_2`, etc. These are especially useful when a later phase fails — you can check whether the canvas was in a clean state before the failing phase started.

**Renderer logs** (`*_renderer.log`) can be very large (20k+ lines, 3MB+ per session). **Caution**: they are not included in agent context by default due to size. Read them carefully and selectively when needed.

**When to read**: Only for renderer-related failures (image not displaying, grey images, rendering crash, mask/crop not applied). Do NOT read for gesture, menu, or state failures.

**How to read efficiently**: Each line starts with `[ms_timestamp]`. Use the failing step's timestamp from `*_test.log` to calculate a line range, then read only that range:
1. Find the failure timestamp in `*_test.log` (e.g., `[73064] [STEP 6/6 FAILED]`)
2. Use `Grep` to find the line number in `*_renderer.log` closest to that timestamp (e.g., grep for `\[73` to find lines around ms 73000)
3. Read only ±50 lines around that line number using `Read` with `offset` and `limit`
4. Never read the entire renderer log file — it will exceed your context window

If the app crashes during `ui-test/scripts/run_test.sh`, check the crash files in that same run folder first. Android crashes are collected from the `crash` logcat buffer and `dumpsys activity exit-info`. iOS crashes are collected from simulator `DiagnosticReports` plus a filtered simulator log extract.

If the app fails to build or install before the test really starts, check `ios_build.log` or `android_build.log` first. These files contain the full `xcodebuild` / Gradle output that launch scripts now preserve even when the terminal output is quiet.

## Step Numbering

After adding, removing, or reordering test steps, run the renumber script to keep step numbers sequential:

```bash
python3 ui-test/scripts/renumber_steps.py ui-test/e2e-tests/editor_e2e_1_test.py
```

This updates both `# Step N:` comments and `print("\nStep N: ...")` lines. **You must manually update `TOTAL_STEPS` after running it.** Ralph's step tracker relies on correct sequential numbering to detect progress — incorrect numbering causes the loop to misjudge whether a fix helped.

## Ralph Session Data

### Session History (`.ralph_session_history.jsonl`)

Key events:

| Event | Description |
|-------|-------------|
| `测试结果` | Test result — `tests_passed` shows progress, logs in `ui-test/.run/<timestamp>/` |
| `问题分析完成` | Problem analysis — `description` field is a concise failure summary with coordinates and suspected causes |
| `假设进展` | Hypothesis made progress (tests_passed increased) |
| `假设失败` | Hypothesis failed (reverted) |
| `Git提交` | Changes committed |
| `Git回滚` | Changes reverted |

### Web Search Results (`ralph/search_results.jsonl`)

Cached web search results from previous iterations — check before searching again.
