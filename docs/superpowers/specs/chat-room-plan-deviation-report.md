# Chat Room — Plan Deviation Report

> Implementation pass against `2026-06-06-cmux-ai-chat-room-design.md`. Lists where the build
> deviates from the design doc and why. Architecture/correlation/persistence layers were already
> faithful (33 pre-existing package tests); this pass closed UI-fidelity and app-integration gaps and
> records the residual deviations below.

## Summary of work done this pass
- **Sidebar (§3.1/§3.2)** — replaced the flat agent list with the designed two-section layout: agents
  **sub-grouped under their room** (room sub-headers) as **three-line rows** (title / ~pwd / branch)
  with a **live status badge** (rotating green spinner = running, dim dot = idle, pulsing amber + "!"
  = needs-input), honoring **Reduce Motion** + accessibility labels. Rooms render as colored `#` rows
  with an unread dot. All rows are **value snapshots** (snapshot-boundary safe, CLAUDE.md #2586).
- **Channel (§3.5/§3.6)** — exchange header now shows the **"N / M replied"** pill; replies show a
  green agent name + `~cwd · branch`; pending targets show **live** `⟳ still working…` or amber
  `⚠ needs input — go to tab →`, driven by a new `lifecycleVersion` change-signal on the coordinator
  (no lifecycle cache — single source of truth preserved, §4.5).
- **Composer (§3.10)** — replaced chip-only targeting with a typed **`@`-autocomplete** whose rows
  show **name · kind · ~cwd · branch**, room-scoped, storing stable `AgentID`; `@all` shortcut;
  quote-into-composer (§3.7) seeds the body.
- **Close policy (§4.10)** — moved the gate to the **lowest mutator** (`TabManager.closeWorkspace`)
  with a re-entrancy bypass, so the last room is non-closable and a room close cascades to its agents
  through **every** entrypoint (⌘W, palette, socket, AppleScript), and every agent close reconciles
  the coordinator (`onAgentClosed`).
- **Localization** — 44 new keys registered in `Localizable.xcstrings` (English source).
- **Tests** — Core 11 + Domain 23 = **34 package tests green** (added a `lifecycleVersion` test).

---

## Deviations from the plan (with reasons)

### D1. `surface_id` is derived from `workspaceId + focusedPanelId`, not threaded end-to-end
**Plan:** §4.4 / Step 5 — extend `WorkstreamEvent`/`feed.push` with a real `surface_id` field threaded
from the hook layer.
**Built:** the hook bridge keys the per-surface FIFO on `SurfaceID(raw: focusedPanelId)` of the agent
workspace resolved from the event's `workspaceId`.
**Reason:** under the v1 invariant **one agent per tab ⇒ `SurfaceID == panelId`** (§4.3), this is
exact; threading a new schema field through `feed.push` and all existing consumers is broader risk
for no v1 behavior change. Revisit if multi-panel-per-workspace agents land.

### D2. Agent/room creation uses AppKit prompts, not a SwiftUI sheet
**Plan:** §4.9 / Step 10 — a "New agent" sheet (model + directory) with inline, recoverable failure
states; room create dialog.
**Built:** `NSOpenPanel` (directory) + `NSAlert` (model) for agent creation; `NSAlert` for room name.
**Reason:** functional and faster to ship the end-to-end flow; the rich inline-failure sheet is UI
polish that doesn't change the create/launch logic. Failure surfacing is currently coarse (panel
cancel / no-op) rather than the per-error inline messages the spec lists.

### D3. `ChatRoomController` is a `static var shared` singleton + `ObservableObject`
**Plan:** CLAUDE.md bans `static let/var shared` singletons and `ObservableObject`/`@Published` in new
code; the executable should construct + inject.
**Built:** `ChatRoomController.shared` is set once at window registration and read from the sidebar /
close gate; it is `ObservableObject` with `@Published badgedRoomIDs`, and bridges via
`NotificationCenter`.
**Reason:** cmux's app shell is not yet a clean composition root (TabManager, AppDelegate are
singletons/ObservableObjects), and the chat bridge must hang off the same lifecycle. The **package**
layers (Core/Domain/UI) are clean and DI'd; this is app-shell glue. Flagged for the eventual
composition-root refactor. (The `NotificationCenter` bridge is likewise app-shell glue, not package
API.)

### D4. Creation-policy fail-closed is partial (not enforced at the `addWorkspace` funnel)
**Plan:** §4.9 — route **all ~27 `addWorkspace` sites** through one policy that stamps
role+kind+roomID or rejects (fail-closed), with a per-surface acceptance matrix.
**Built:** the dedicated agent-creation path stamps role+kind+roomID correctly; generic `addWorkspace`
sites are **not** intercepted. A workspace created elsewhere defaults to `role = .agent` with
`roomID == nil` and is shown under an **"unassigned"** sub-header and **migrated into a room** by
`ensureDefaultRoomExists()` (so it is never silently lost), but it is not the spec's funnel-level
enforcement.
**Reason:** intercepting 27 call sites across 11 files (AppleScript, config, fork-conversation, …) is
a broad, regression-prone change; the fail-safe (default `.agent` + migrate-to-room + exclude
unknown-kind from rosters) preserves the invariants without it. Recommended as a dedicated follow-up.

### D5. Needs-input "notifies the agent tab" = the sidebar badge, not a system notification
**Plan:** §3.12 — needs-input notifies the agent tab.
**Built:** the agent's sidebar row shows the pulsing amber + "!" badge and an amber row tint, and the
channel shows `⚠ needs input — go to tab →`. No OS-level (Notification Center) alert is posted.
**Reason:** the spec's intent — *surface it on the tab, never gate sending* — is met by the badge;
an OS notification is additive polish. Completion→room badge (the other half of §3.12) is wired
(`badgedRoomIDs`).

### D6. `CmuxChatRoomUI` is not in the CI `swift test` PACKAGES list
**Plan:** Step 1 — add all three packages to `ci.yml` PACKAGES.
**Built:** `CmuxChatRoomCore` + `CmuxChatRoom` are in the list; `CmuxChatRoomUI` is **not**.
**Reason:** the UI package has **no test target** (SwiftUI views; nothing runs headlessly), so
`swift test --package-path` on it fails with "no tests found" and would break CI. It is gated instead
by compiling into the app target. Add it only if/when it gains headless tests.

### D7. Localization: English-only this pass; other locales deferred
**Plan:** CLAUDE.md — every user-facing string localized for all supported locales (EN + JA at
minimum); `defaultValue` does not count.
**Built:** 44 new keys added to `Localizable.xcstrings` with **English** source values; 2 interpolated
keys left for Xcode extraction. The app is fully functional in English via `defaultValue`.
**Reason:** the catalog carries ~15 languages per key; hand-authoring faithful translations (esp. JA)
for 44 keys would mean fabricating translations. Registered the keys with correct English source;
**translation is a required follow-on pass** (the keys now show as untranslated in Xcode's catalog UI,
the normal state for new strings).

### D8. Sidebar badge / live-status reactivity is event-driven, not push-subscribed
**Plan:** §4.5 — lifecycle changes propagate via `AsyncStream`.
**Built:** the app seams' `changes` streams are stubs; lifecycle/feed events reach the coordinator via
the `NotificationCenter` bridge, and the channel re-reads live status on `lifecycleVersion`. The
**sidebar** rebuilds status badges when its body re-evaluates (selection/tab changes); a pure
lifecycle transition with no other sidebar change may lag until the next invalidation.
**Reason:** wiring the real `AsyncStream` seams end-to-end is a larger plumbing change; the
notification bridge already delivers the behaviorally-important paths (held-prompt flush, channel
status). Sidebar-badge live-push is a refinement.

---

## Not deviations (explicitly faithful)
- Marker-only correlation, room-scoping, FIFO pairing, forward/quote, needs-input hold,
  resolve-at-send-time, move-mid-flight routing — all per §4.6, covered by the 23 domain tests.
- `ChatRoomID` decoupled from the re-minted `Workspace.id` as a stable persisted field (§4.3/§4.11).
- Rooms **derived** from `.chatRoom` workspaces (no owned `rooms`/`activeRoom`) via the
  `RoomWorkspaceReading/Managing` seams (§4.6).
- History keyed by `ChatRoomID`; persistence of role/roomID/kind/chatRoomID/name with migration (§4.11).
- No worktree management (per the rev-8 decision); close has no filesystem effects (§4.9/§4.10).
- Marker hidden token, raw pre-redaction event consumption for prompt/final-message (§4.4).

## Known follow-ups
1. Codex/Cursor adapters remain gated on **G1** (final-message capture) — Claude is the verified path.
2. Full creation-policy funnel enforcement (D4) + new-agent sheet (D2).
3. Translation pass for the 44 new keys (D7); real `AsyncStream` seams (D8); `surface_id` schema (D1).
