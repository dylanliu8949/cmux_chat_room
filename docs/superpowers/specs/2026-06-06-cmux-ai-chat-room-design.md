# cmux AI Chat Room — Design & Implementation Plan

> Status: **Draft for review (rev 3)** · Author: Dylan (with Claude) · Date: 2026-06-06
> Review loop: Codex reviews this doc → Claude addresses comments → repeat to convergence → execution.

### Revision history

- **rev 1** — initial spec.
- **rev 2** — incorporates Codex review round 1 (3 independent reviewers, all "Not Ready") after verifying every claim against the code. Major changes: (a) reuse the **existing** cmux agent pipeline — hooks (`CLI/CMUXCLI+AgentHookDefinitions.swift`), launch (`Packages/CMUXAgentLaunch`), lifecycle (`Workspace.agentLifecycleStatesByPanelId`), and the `stop` hook's existing `last_assistant_message` payload — instead of building parallel infrastructure; (b) token-based correlation; (c) fix package layering with a low `CmuxChatRoomCore`; (d) single source of truth for lifecycle; (e) central `WorkspaceRole`-aware close policy; (f) explicit persistence/migration; (g) correct CI test gating; (h) "Step 0" infra audit; (i) UX: richer `@`-autocomplete rows, full (non-collapsed) messages, channel windowing + "load earlier", new-agent failure states, accessibility/reduced-motion.
- **rev 3** — incorporates Codex review round 2 (3 reviewers), verified against code. Major changes: (a) **`surface_id` carried end-to-end** — `WorkstreamEvent`/feed schema extended with `surface_id` (hook layer already has it; `CLI/cmux.swift:205`), and the chat bridge consumes **raw decoded events before EventBus redaction** (`CmuxEventPublishing.swift:451` nulls `tool_input`); per-surface FIFO now works with multiple agent panels per workspace. (b) **Hidden `ChatRequestID` marker** correlation (chosen over exact-text): a non-displayed token is injected with the prompt, round-trips via the raw `toolInputJSON` (`WorkstreamEvent.swift:17`, **not** the whitespace-collapsing `submittedPromptMessage` at `WorkspacePromptSubmit.swift:133`), binds the turn, and is stripped before channel display/forward; FIFO still pairs the bound `prompt-submit` to its `stop`. (c) **Close gate at the lowest mutator** — guard inside `TabManager.closeWorkspace` (`:5205`, no guard today) with an explicit internal force flag, since AppleScript (`AppleScriptSupport.swift:473`) and config (`CmuxConfigExecutor.swift:508`) call it directly. (d) **needs-input hold** — `send_text` injects raw terminal bytes (`TerminalController.swift:8653`), so prompts to a `needsInput` target are held (not blind-injected into a permission prompt) and delivered when it leaves `needsInput`; running/idle still pipe through immediately. (e) UX: per-message **copy** + **quote-into-composer**.

---

## 1. Background

### Why this exists

Dylan runs a disciplined multi-agent coding workflow:

```
create-plan → plan-review → plan-execution → code-review
```

with two cooperating roles:

- **Coder agent:** create-plan → address-review-comment → plan-execution → address-review-comment
- **Review agent:** review-plan → code-review

In practice Dylan often pairs **Claude Code as the coder** and **Codex as the reviewer**, because the models have complementary strengths (below). Today this is done by hand — copying text between separate terminal windows — which is tedious and loses track once more than two agents are involved.

### The hard-won philosophy behind the workflow

These beliefs are *requirements in disguise*; the product must protect them:

1. **Review is additive only when a human coordinates toward convergence.** A fully automated Codex⇄Claude `while` loop burned ~60% of a weekly token allowance, executed a plan that was bad from the start, drifted in scope hop-to-hop, and produced something that didn't work. Lesson: **the human holds the canonical intent and gates every hop.** Deliberate friction is a feature — anywhere the tool is tempted to auto-advance a hop, the answer is *no*.
2. **An agent should never be both coder and reviewer in one session.** Authors are biased toward "ship it"; reviewing must be a separate session/agent.
3. **Different models have different shapes.** Codex analyzes better than it codes (it will say "this plan is beyond saving" — the sane, scope-saving call). Claude codes well but is eager-to-please ("is it better now?") and shallower in analysis. Route work to the model whose shape fits.
4. **Agency on both sides is additive** — a coder that can reject a reviewer's claim, a reviewer that can say "not addressed, no-go" — *when a human arbitrates.*
5. **Independent convergence is signal.** Spawn N agents on the same question; if they *independently* converge, that's the obvious answer. Independence is what makes it meaningful — agents must be **blind to each other.**

### What we're building

A fork of **cmux** (native macOS terminal app with vertical tabs) turned into an **AI chat room**: a pinned, Slack-channel-style tab that orchestrates a set of agent terminal tabs via `@mentions`, collects each agent's *final* message back into the channel, and lets the human forward messages between agents — while every agent tab remains a fully interactive coding-agent terminal.

The chat room is an **adjudication and coordination surface** — not a consensus engine, not a wrapper that hides the real sessions. It makes coordination fast and legible; it never removes the human from the loop.

---

## 2. References

### Upstream / fork

- Upstream cmux: https://github.com/manaflow-ai/cmux
- This fork: https://github.com/asura1234/cmux_chat_room
- Binding rules (read first): [`CLAUDE.md`](../../../CLAUDE.md) — package architecture, Swift 6 concurrency, file organization, localization, test wiring, socket policies.

### Existing infrastructure we BUILD ON (verified — the feature is mostly orchestration over these)

| Concern | File · symbol | Notes |
|---|---|---|
| Tab **is** a Workspace | `Sources/TabManager.swift:16` | `typealias Tab = Workspace` |
| Tab presentation fields | `Sources/Workspace.swift:10293-10301` | `customTitle`, `customDescription`, `isPinned`, `customColor`, `groupId` exist |
| Sidebar tab row | `Sources/ContentView.swift:15048` | `TabItemView` (Equatable, snapshot-fed) |
| **Existing agent lifecycle** | `Sources/Workspace.swift:10559` | `agentLifecycleStatesByPanelId: [UUID:[String:AgentHibernationLifecycleState]]` |
| Lifecycle states | `Sources/AgentHibernation/AgentHibernationLifecycleState.swift:3` | `unknown / running / idle / needsInput` |
| Lifecycle mutation + CLI | `Sources/Workspace.swift:12287`; `Sources/TerminalController.swift:19378` | `setAgentLifecycle(...)`, `set_agent_lifecycle` CLI |
| **Existing agent hook defs** | `CLI/CMUXCLI+AgentHookDefinitions.swift:142-256` | hooks for claude/codex/cursor/gemini/… ; events `prompt-submit`, `stop`, `agent-response`, `session-end/-finalize` |
| **`stop` already carries final msg** | `CLI/CMUXCLI+OmpExtension.swift:192` | `sendHook("stop", ctx, { last_assistant_message })` |
| Hook → app routing | `cmux hooks <agent> <subcommand>` over `CMUX_SOCKET_PATH`; `Sources/WorkspacePromptSubmit.swift:86` (`lastAssistantMessage`); `CLI/FeedEventClassifier.swift:214` (`stop → .response`) | the feed already classifies turn-completion |
| **Agent launch infra** | `Packages/CMUXAgentLaunch/` (`HermesAgentHookConfig.swift`, `AgentSpawnIdentity.swift`, env policy, resume) | hook install + identity stamping; reuse for launch |
| Panel protocol (needs shim) | `Sources/Panels/Panel.swift:267` | `protocol Panel: AnyObject, Identifiable, ObservableObject` — **requires ObservableObject** |
| New terminal surface | `Sources/Workspace.swift:14522` | `newTerminalSurface(...)` |
| Inject text | `Sources/TerminalController.swift:18155,18290`; V2 `surface.send_text` `:2010` | prompt injection path |
| Close paths (scattered) | `Sources/TabManager.swift:5381,5402,5412,5423`; socket `closeWorkspace` `Sources/TerminalController.swift:18104`; UI `Sources/ContentView.swift:15482` | `canCloseWorkspace(_,allowPinned:)` gates on `isPinned`; **no role-aware single gate** |
| Persistence snapshots | `Sources/SessionPersistence.swift:1379` (`SessionTerminalPanelSnapshot`, has `agent`), `:1787` (`SessionWorkspaceSnapshot`, has `isPinned/groupId/customColor`) | **no agent-kind / workspace-role field yet** |
| Notifications hub | `Sources/TerminalNotificationStore.swift:822` | split notifications |
| Rename plumbing | `Sources/ContentView.swift:3138-3157`; `Sources/Workspace.swift:12076-12132` | command-palette + context-menu → `customTitle` |
| Package wiring exemplars | `Packages/CmuxSettings`(+UI), `Packages/CmuxSocketControl`, `Packages/CMUXAgentLaunch` | copy pbxproj shape |
| **CI package-test gate** | `.github/workflows/ci.yml:411-442` | `cmux-unit` does NOT run SPM tests; a `PACKAGES=(…)` list runs `swift test --package-path` per package — new packages MUST be added here |
| Localized strings | `Resources/Localizable.xcstrings`; `web/messages/{en,ja}.json` | EN + JA |

---

## 3. Product / UX design

> Mockups are the brainstorm artifacts rendered to PNG. Interactive HTML originals live under `.superpowers/brainstorm/` (gitignored). Note: mockups predate two later decisions — `~`-abbreviated paths, and richer `@`-autocomplete rows (§3.10).

### 3.1 Two tab types
One pinned **chat-room** tab (colored, always on top, **non-closable**) + N **agent** tabs. Bash tabs dropped — an agent tab is a real terminal (shell via the agent's `!`).

![Two tab types](assets/2026-06-06-chat-room/two-types.png)

### 3.2 Sidebar — agent tabs (three lines + live status)
Editable title (auto-named "claude code 1"), then **~pwd**, then **branch on its own line**. Live lifecycle badge from the **existing** `agentLifecycleStatesByPanelId`: rotating green spinner = `running`, dim dot = `idle`, pulsing amber + `!` = `needsInput`.

![Sidebar with status badges and spinner](assets/2026-06-06-chat-room/sidebar-v2.png)

### 3.3 Rename = title only
Double-click the title text → inline edit (pre-selected; Enter saves / Esc cancels). Same action via right-click → Rename and command palette → Rename Tab. pwd/branch read-only.

![Inline rename of the title](assets/2026-06-06-chat-room/rename.png)

### 3.4 Routing rule — chat-origin replies only
An agent's final message returns to the channel **only** if the prompt came from the channel. Direct turns stay in the tab. Guaranteed by token correlation (§4.6), not heuristics.

![Routing rule](assets/2026-06-06-chat-room/routing-rule.png)

### 3.5 Channel layout — grouped exchanges (one level deep)
Ordered list of **exchanges**: one outgoing prompt (`@mention` or forward) + the replies from its targets, grouped beneath. A forward is a *new* exchange — not a nested thread.

![Channel layout: grouped exchanges](assets/2026-06-06-chat-room/layout-choice.png)

### 3.6 Exchange progress + stalled visibility
Each exchange shows **N/M replied**, who's still `running`, and any `needsInput` agent (amber, jump-to-tab). Status is read from the existing lifecycle state.

![Exchange progress and needs-input](assets/2026-06-06-chat-room/exchange-status.png)

### 3.7 Message labeling + forward / quote
Every reply is stamped with the origin agent's name + two subtitles, **snapshotted at send time**. Each message carries three actions:
- **Forward** — wraps the original in `"double quotes"` and lets you **append your own note**, then *sends it to one or more agents* — the *steering wheel* (re-scope, narrow, reject a claim).
- **Quote into composer** — same quote shape, but drops the `"double-quoted"` original into *your own composer* so you can add text after it and post it as **your** channel message (not sent to an agent). This is the human analog of forward, for composing structured messages like a quote-plus-reply.
- **Copy** — copies the message's raw text to the clipboard.

![Message labeling and forward composer](assets/2026-06-06-chat-room/message-and-forward.png)

### 3.8 Full messages, no collapsing
Channel messages and the forward/quote preview **always render in full** — no "read more" / truncation / collapse of any kind (a collapse invites skimming). Non-hiding affordances only: **copy**, **quote into composer** (§3.7), and a **go-to-source-tab** link per message.

### 3.9 Channel windowing ("load earlier")
For very long histories the channel keeps a **bounded recent window** scrollable (e.g. the most recent N exchanges). Scrolling to the top reveals a **"Load earlier"** button that pages older exchanges in from the persisted store on demand. Individual messages are never truncated; only the *count* of rendered exchanges is bounded for performance.

### 3.10 Mention targeting
You type/match the **name** (`@`), but each autocomplete **dropdown row shows name + kind + ~cwd + branch** so duplicate/renamed titles and "same repo, different branch" are distinguishable. Selection stores a **stable `AgentID`**, never the display string. The dropdown is **rebuilt fresh each time it opens** from the live roster, so every current agent tab is present and closed ones are absent.

### 3.11 Sending vs. agent state
Prompts inject **raw terminal input** (not a semantic queue), so state matters:
- **running / idle** → injected immediately (these TUIs buffer follow-up input safely).
- **needs-input** (agent sitting at a permission/y-n prompt) → **held, not injected** (a blind injection could answer the dialog with garbage). The exchange shows that target as *"waiting — agent needs input"* with a jump-to-tab link; the held prompt is delivered automatically once the agent leaves `needsInput`. If the agent never leaves it (or the tab closes), the held prompt resolves to `failedToDispatch` / `tabClosed`.

### 3.12 Notifications (v1)
Disjoint events, no double-ring:
- **Completion** (chat-origin turn finished) → notifies the **chat-room tab** when unfocused.
- **Needs-input** (agent blocked) → notifies the **agent tab**.

### 3.13 Accessibility
Status is never color/motion-only: each lifecycle state carries a **text/accessibility label** (`running` / `idle` / `needs input`). Honor **Reduce Motion** (spinner → static glyph) and high-contrast.

### 3.14 Explicit non-goals for v1 (YAGNI)
No `/poll` or slash-command framework; no automated review/apply loop; no interrupt-from-chat; no token/cost accounting (strong follow-on); no deep/nested threads; no general busy-queue — the only state-based hold is the `needsInput` safety hold (§3.11).

---

## 4. Engineering design

### 4.1 Constraints (from `CLAUDE.md`, binding)
Layered package DAG (Core → Services → Domain → UI → Executable), downward deps only. Swift 6 concurrency only (`actor`/`async`/`AsyncStream`/`@Observable`/`@MainActor`; no Combine/`@Published`/locks/`DispatchQueue.main.async`/completion handlers). Constructor DI; the executable is the single composition root. One type per file; DocC on public symbols. Snapshot boundary (rows get value snapshots + closures, never a store). No state mutation in view-body. Inject `UserDefaults`/`FileManager`/paths/clock. Swift Testing. Localization audit. Socket: no focus stealing; telemetry off-main.

### 4.2 Packages (layering fixed)

```
Packages/
  CmuxChatRoomCore/    # Core: pure Sendable DTOs, IDs, AgentEvent, protocol seams (no AppKit)
  CmuxChatRoom/        # Domain/State: @Observable coordinator + correlation (depends ↓ Core)
  CmuxChatRoomUI/      # UI: SwiftUI channel views (depends ↓ CmuxChatRoom + Core)
  CMUXAgentLaunch/     # (existing Service) extended for chat-room agent launch + hook install
```

Dependency direction is strictly downward: `CmuxChatRoomUI → CmuxChatRoom → CmuxChatRoomCore`; agent launch lives in the existing **services** package `CMUXAgentLaunch` (also `→ Core` only). The app target composes concretes. This resolves the rev-1 inversion (services no longer import the domain package).

### 4.3 Data model (`CmuxChatRoomCore`, all `Sendable` value types)

```swift
public struct AgentID: Hashable, Sendable, Codable { public let raw: UUID }      // = workspace/tab id
public struct SurfaceID: Hashable, Sendable, Codable { public let raw: UUID }    // agent's terminal surface
public struct ChatRequestID: Hashable, Sendable, Codable { public let raw: UUID } // correlation token
public struct MessageID: Hashable, Sendable, Codable { public let raw: UUID }
public struct ExchangeID: Hashable, Sendable, Codable { public let raw: UUID }

public enum AgentKind: String, Sendable, Codable { case claudeCode, codex, cursor }

public struct AgentIdentitySnapshot: Sendable, Codable, Hashable {
    public let agentID: AgentID
    public let title: String           // editable title at send time
    public let kind: AgentKind
    public let cwdDisplay: String      // ~-abbreviated
    public let branch: String?
}

public enum PromptOrigin: Sendable, Codable, Equatable {
    case userMention
    case forward(sourceMessageID: MessageID)
}

public struct OutgoingPrompt: Sendable, Codable {
    public let exchangeID: ExchangeID
    public let origin: PromptOrigin
    public let bodyText: String        // forward: "\"<quoted>\"\n<note>"
    public let targets: [AgentIdentitySnapshot]
    public let sentAt: Date
}

public struct Reply: Sendable, Codable {
    public let id: MessageID
    public let exchangeID: ExchangeID
    public let from: AgentIdentitySnapshot
    public let markdownBody: String    // verbatim last_assistant_message
    public let receivedAt: Date
}

public enum ReplyOutcome: Sendable, Codable {
    case pending, replied(Reply), tabClosed, failedToDispatch
}

public struct Exchange: Sendable, Codable {
    public let prompt: OutgoingPrompt
    public var outcomes: [AgentID: ReplyOutcome]
}

/// Normalized turn events the coordinator consumes (sourced from existing hooks).
/// Carry `SurfaceID` (not just workspace) so per-surface FIFO works with multiple agent panels.
public enum AgentTurnEvent: Sendable {
    /// `rawPromptText` is the UN-normalized prompt from `toolInputJSON` (NOT the whitespace-collapsed
    /// `submittedPromptMessage`), so the embedded marker survives and is extractable.
    case promptSubmitted(SurfaceID, rawPromptText: String)
    case turnCompleted(SurfaceID, finalMessage: String)   // from `stop` last_assistant_message
}

/// The hidden correlation marker embedded in an injected prompt and recovered from `rawPromptText`.
/// Rendered invisibly (see ``ChatPromptMarker/inject`` / ``strip``); never shown in the channel or a forward.
public enum ChatPromptMarker {
    /// Append a non-displayed token encoding `id` to `body` before injection.
    public static func inject(_ id: ChatRequestID, into body: String) -> String { … }
    /// Recover the `ChatRequestID` (if any) from a raw prompt, plus the body with the marker removed.
    public static func extract(from rawPrompt: String) -> (ChatRequestID?, cleaned: String) { … }
}
```

### 4.4 Reuse the existing hook pipeline (no new transport)

The agent CLIs already run cmux hooks (`CLI/CMUXCLI+AgentHookDefinitions.swift`) that call `cmux hooks <agent> <subcommand>` over the socket. We **extend the app-side handling** of two events already in the pipeline rather than writing new hook scripts or a `chat.agent_report` command:

- `prompt-submit` — carries the submitted prompt text.
- `stop` (a.k.a. `agent-response`) — already carries `last_assistant_message` (`CMUXCLI+OmpExtension.swift:192`).

App-side, these are routed (per surface) into a `CmuxChatRoomCore.AgentTurnEvent` stream the coordinator subscribes to. Launch/hook installation reuses `CMUXAgentLaunch` (which already stamps identity and installs hook config). **Step 0 (§5) confirms, per agent (claude/codex/cursor), that `prompt-submit` fires for injected input, that `stop` carries the final message, and that the marker (§4.6) round-trips through that agent's prompt handling without the agent choking on it.**

**Two schema/plumbing fixes required (verified gaps):**
- **`surface_id` must be carried end-to-end.** `WorkstreamEvent` currently has `workspaceId` but no `surfaceId` (`WorkstreamEvent.swift:14`); the hook layer already knows the surface (`CLI/cmux.swift:205`), so extend the `feed.push`/`WorkstreamEvent` schema with `surface_id` and thread it through. Without it, per-surface FIFO collapses when a workspace holds multiple agent panels.
- **Consume RAW events before redaction.** The public `EventBus` nulls `tool_input`/`context` bodies (`CmuxEventPublishing.swift:451`). The chat bridge must tap the **raw decoded `WorkstreamEvent`** (`toolInputJSON`/`extraFieldsJSON`, `WorkstreamEvent.swift:17,22`) *before* that redaction — both to read the prompt and to recover the marker. It must **not** use `submittedPromptMessage`, which collapses whitespace (`WorkspacePromptSubmit.swift:133`) and would corrupt multiline prompts/forwards.

`AgentRosterProviding` (live tabs → mentionable set) and `PromptInjecting` (wrap `surface.send_text` + submit, non-focus-stealing) are protocol seams in `CmuxChatRoomCore`, implemented in the app target over `TabManager` / `TerminalController`.

### 4.5 Lifecycle: single source of truth

The coordinator does **not** keep its own lifecycle dictionary. Sidebar badges, exchange progress, and the needs-input notification all read the **existing** `Workspace.agentLifecycleStatesByPanelId` (already updated by `set_agent_lifecycle`). The coordinator observes it via a read-only seam (`AgentLifecycleReading`, exposing a snapshot + `AsyncStream` of changes) implemented in the app over the existing store. No drift with hibernation/sidebar.

### 4.6 Coordinator + marker correlation + needs-input hold (`CmuxChatRoom`, `@MainActor @Observable`)

```swift
@MainActor @Observable
public final class ChatRoomCoordinator {
    public private(set) var exchanges: [Exchange] = []          // bounded window in UI; full set in store
    private var turnQueueBySurface: [SurfaceID: [TurnBinding]] = [:]   // per-surface FIFO of submitted turns
    private var pendingByRequest: [ChatRequestID: PendingInjection] = [:] // injected, awaiting prompt-submit
    private var heldForNeedsInput: [AgentID: [HeldPrompt]] = [:]  // §3.11 safety hold

    private let roster: any AgentRosterProviding
    private let lifecycle: any AgentLifecycleReading
    private let injector: any PromptInjecting
    private let notifier: any ChatNotifying
    private let history: any ChatHistoryStore

    public func send(_ body: String, to mentions: [AgentMention], origin: PromptOrigin) async { … }
    public func forward(_ message: MessageID, to: [AgentMention], note: String) async { … }
    public func handle(_ event: AgentTurnEvent) { … }
    public func onLifecycleChange(_ id: AgentID, _ state: AgentLifecycle) { … } // releases held prompts
    public func loadEarlier() async { … }
}

struct PendingInjection { let requestID: ChatRequestID; let exchangeID: ExchangeID; let surface: SurfaceID }
struct HeldPrompt { let requestID: ChatRequestID; let exchangeID: ExchangeID; let bodyWithMarker: String }
enum TurnBinding { case chatOrigin(ChatRequestID, ExchangeID); case direct }
```

**Correlation invariant (the core of the routing rule) — marker-based:**

1. `send`: resolve mentions → live `AgentID`/`SurfaceID` at send time (dead → `.failedToDispatch`). Create one `Exchange`. For each target: mint a `ChatRequestID`, build `bodyWithMarker = ChatPromptMarker.inject(id, into: body)`, mark outcome `.pending`. **If the target is `needsInput`**, append to `heldForNeedsInput[agent]` and show *"waiting — needs input"* (§3.11); **otherwise** record `pendingByRequest[id]` and inject `bodyWithMarker`. Persist.
2. `handle(.promptSubmitted(surface, rawPromptText))`: `let (id, _) = ChatPromptMarker.extract(from: rawPromptText)`. If `id` is present **and** in `pendingByRequest` → remove it, append `.chatOrigin(id, exchangeID)` to `turnQueueBySurface[surface]`. Else append `.direct`. (Binding requires the marker — a direct turn, even byte-identical, has no marker and is never chat-origin.)
3. `handle(.turnCompleted(surface, finalMessage))`: pop the **front** of `turnQueueBySurface[surface]` (agents process turns in order). `.chatOrigin` → attach `finalMessage` to that exchange/target, persist, notify the chat tab (if unfocused). `.direct` → **drop**.
4. `onLifecycleChange(agent, state)`: when an agent leaves `needsInput`, flush `heldForNeedsInput[agent]` — for each held prompt, record `pendingByRequest` and inject `bodyWithMarker`.
5. Tab closed: `.pending`/held outcomes for that agent → `.tabClosed`; clear its queues/holds.

The marker makes binding independent of prompt text, so a byte-identical direct prompt while a chat prompt is pending can no longer mis-bind (it carries no marker). A direct turn that completes first is bound `.direct` and dropped. No marker ⇒ no chat binding ⇒ no leak.

> **Marker design constraints** (validated in Step 0): the injected token must (a) survive verbatim in `toolInputJSON`, (b) be reliably stripped before any channel display/forward, and (c) not derail the agent. Candidate: a single trailing line the agent treats as inert metadata; the exact encoding is fixed in Step 0 against each CLI. If an agent cannot carry it cleanly, that agent falls back to per-surface FIFO + raw-text match with the documented byte-identical-collision limitation (a contained per-adapter decision, not a redesign).

### 4.7 Live roster (no parallel registry)
`AgentRosterProviding` is implemented over `TabManager`, exposing `current()` + an `AsyncStream` of changes; the mentionable set is *derived* from live tabs. `@all` = live agents at send instant. The autocomplete dropdown calls `current()` on open (§3.10).

### 4.8 Chat-room panel + agent tabs (app target)
- `ChatRoomPanel: Panel` — because `Panel` requires `ObservableObject`, this is a **thin legacy shell** in the app target; all real state lives in the `@Observable` `ChatRoomCoordinator` (package), which the shell holds and forwards to. Documented as an intentional adapter until `Panel` is modernized.
- Chat-room workspace: new `WorkspaceRole` (`.chatRoom` / `.agent`), `isPinned`, distinct `customColor`, **non-closable** (§4.10); ensured once per window.
- Agent tab: `WorkspaceRole.agent` + `AgentKind`; auto-named; sidebar three-line layout + lifecycle badge (snapshot-fed row — coordinator never injected into the row).
- `ChatRoomView` (`CmuxChatRoomUI`): exchange list (windowed, snapshot-fed rows + "Load earlier"), composer with `@` autocomplete (§3.10), per-message actions **forward / quote-into-composer / copy / go-to-tab** (§3.7), full messages (§3.8), progress + needs-input/held status, markdown rendering.

### 4.9 Create-agent + worktree sub-flow (with failure states)
"New agent" sheet: (1) kind; (2) location — *current pwd/branch* or *new worktree* (base branch + new branch + parent dir → `git worktree add <path> -b <branch> <base>`); then launch via `CMUXAgentLaunch`, auto-name, add to roster.
**Failure/validation (inline, recoverable):** path or branch collision; dirty/missing base repo; missing CLI binary; unsupported/uninstalled hook for that agent; `git worktree add` failure; partial launch (surface created but agent didn't start → offer retry/close). Each surfaces an inline error in the sheet; nothing half-creates silently.

### 4.10 Close policy (gate at the lowest mutator)
The role guard must live in the **destructive funnel itself**, not just at UI/socket entrypoints. Verified: `TabManager.closeWorkspace` (`:5205`) has no can-close guard today (only `guard tabs.count > 1`), and it's called **directly** by non-UI paths — AppleScript (`AppleScriptSupport.swift:473,624`) and config replacement (`CmuxConfigExecutor.swift:508`) — which bypass the UI's `canCloseWorkspace`. So:

- Add a required `WorkspaceRole` to `Workspace`; make `closeWorkspace` **refuse a `.chatRoom` workspace** unless called with an explicit internal `force: true` (used only for app teardown / window close / session replace).
- `canCloseWorkspace` remains a **UI affordance only** (hides/disables the X, ⌘W, palette/menu items).
- Every entrypoint — sidebar X, ⌘W/menu, command palette, socket `closeWorkspace` (`TerminalController.swift:18104`), bulk/window close, AppleScript, config replace — now hits the same guarded mutator.
- Agent tabs: confirm-on-close when `running`; pending/held outcomes → `.tabClosed`; removed from roster. Closing an agent never erases its past messages (identity snapshots persist).

### 4.11 Persistence + migration
`ChatHistoryStore` (actor-backed repository, JSON under Application Support, keyed per **window/session** — the same key that ties to session restore; named invariant: one chat room per window, history key = window/session id). Stores all exchanges/replies with embedded `AgentIdentitySnapshot`; supports **paged reads** for "Load earlier" (§3.9) and bounded initial load.
Session snapshots gain explicit fields (with migration defaults for old data): `SessionWorkspaceSnapshot.role: WorkspaceRole?` (default `.agent` when absent for restored tabs that had an agent, else `nil`) and the agent **kind** persisted on the panel/agent snapshot (`SessionTerminalPanelSnapshot.agent` extended or a sibling field). On restore: re-derive the live roster from restored agent tabs; the chat-room tab is recreated from its role; history reconnects by window/session key. Without these fields, restored agent tabs would vanish from `@all` and lose kind/badges — so they are required, not optional.

### 4.12 Data flow

```mermaid
flowchart LR
  U[Human in channel] -- "@mention / forward / quote" --> CO[ChatRoomCoordinator]
  CO -- "inject body + hidden ChatRequestID marker (held if needsInput)" --> SURF[Agent terminal surface]
  SURF --> AG[Agent CLI]
  AG -- "existing hooks: prompt-submit(raw toolInputJSON) / stop(last_assistant_message)" --> HK[cmux hooks route]
  HK -- "raw WorkstreamEvent + surface_id, pre-redaction" --> APP[app-side hook bridge]
  APP -- "AgentTurnEvent (SurfaceID)" --> CO
  CO -- "extract marker → bind; per-surface FIFO pop" --> EX[Exchange replies]
  EX --> UI[ChatRoomView windowed]
  LC[Workspace.agentLifecycleStatesByPanelId] -- read-only seam --> CO
  CO -- "leaves needsInput → flush held prompts" --> SURF
  TM[TabManager live tabs] -- AsyncStream --> CO
  CO -- completion (unfocused) --> NCH[notify chat tab]
  LC -- needsInput --> NAG[notify agent tab]
```

---

## 5. Execution steps

Vertical slice: Claude Code end-to-end *before* Codex/Cursor. Two-commit red/green per regression test.

0. **Existing-infra audit (no code).** Inventory and document, per agent (claude/codex/cursor): exact `cmux hooks` events fired, whether `prompt-submit` fires for *injected* input, whether `stop` carries `last_assistant_message`, **whether the §4.6 marker round-trips through `toolInputJSON` and the agent tolerates it**, how `CMUXAgentLaunch` installs hooks + stamps identity, **where `surface_id` is available at the hook layer and how to thread it into `WorkstreamEvent`/`feed.push`**, the existing lifecycle update path, all close entrypoints (incl. AppleScript/config direct calls), and the CI package-test list. Output: a findings note that confirms/adjusts §4.4–§4.11 and fixes the marker encoding before any code.
1. **Scaffold packages.** `CmuxChatRoomCore`, `CmuxChatRoom`, `CmuxChatRoomUI` (+ Swift Testing targets). Add all three to `.github/workflows/ci.yml` `PACKAGES`. Wire any app-target test files into `project.pbxproj`; run `normalize-pbxproj.py` + `check-pbxproj.sh`.
2. **Core model.** §4.3 DTOs + `ChatPromptMarker` + protocol seams in `CmuxChatRoomCore`. Unit-test `ChatPromptMarker.inject`/`extract` round-trip incl. multiline/forward bodies.
3. **Coordinator + correlation (pure).** Implement §4.6 against fakes. **Correlation tests first (red/green):** direct turn dropped; direct completes-first while chat pending; **byte-identical direct prompt (no marker) does not bind**; marker bind/strip; FIFO pairing per surface; **needs-input hold then flush on lifecycle change**; forward/quote; resolve-at-send-time.
4. **Persistence.** `ChatHistoryStore` actor + JSON + paged reads; round-trip + migration tests (injected temp dir).
5. **`surface_id` + raw-event hook bridge.** Extend `WorkstreamEvent`/`feed.push` with `surface_id`; tap **raw decoded events before EventBus redaction**; map `prompt-submit`(raw `toolInputJSON`)/`stop` → `AgentTurnEvent`. Lifecycle read-only seam over `agentLifecycleStatesByPanelId`; injection seam over `surface.send_text` (multi-line safe, non-focus-stealing).
6. **Claude Code end-to-end** via `CMUXAgentLaunch`: create agent tab → `@` → inject body + marker → bound via marker at `prompt-submit` → `stop` final message → channel reply. Verify marker is stripped from the displayed reply path.
7. **Chat-room panel + UI.** `ChatRoomPanel` shell + `ChatRoomView` (windowed snapshot-fed exchanges, "Load earlier", `@` autocomplete rows §3.10, forward composer, **quote-into-composer + copy** (§3.7), full messages, progress + needs-input/held status, jump-to-tab, a11y/reduced-motion).
8. **Chat-room tab + roles.** `WorkspaceRole`; pinned/colored/auto-created once per window.
9. **Agent tab UX.** `AgentKind`; auto-name; three-line sidebar + lifecycle badge; inline rename via existing `customTitle` action.
10. **Create-agent + worktree sheet** with failure states (§4.9).
11. **Close policy (§4.10)** — guard inside `TabManager.closeWorkspace` with `force:` flag; verify via direct call, AppleScript, config replace, socket, palette/menu, bulk.
12. **Notifications** split (completion→chat, needs-input→agent).
13. **Persistence/restore (§4.11)** incl. role/kind migration; roster re-derivation.
14. **Codex adapter** — confirm hook events via Step 0; wire; degrade gracefully.
15. **Cursor adapter** — same; document limitations.
16. **Localization + audit**; **DocC** on public symbols; package READMEs.

---

## 6. Test & verification

### 6.1 Automated (full functional coverage; manual = UX 验收 only)
Swift Testing, behavior-level (no source-text/AST assertions). **Package tests for `CmuxChatRoom*` run via the `ci.yml` `PACKAGES` list** (the `cmux-unit` scheme does not run SPM tests); app-target integration tests go in `cmuxTests/` wired into `project.pbxproj`.

**Marker (`ChatPromptMarker`):** `inject`/`extract` round-trip for single-line, **multiline**, and forward/quote bodies; `extract` strips the marker from the cleaned body; a body with no marker extracts `nil`.

**Coordinator / correlation (pure) — the core:**
- Chat-origin completion routes to the correct exchange/target (bound via marker).
- **Direct turn (no marker) is dropped.**
- **Direct turn completes first while a chat prompt is pending → not attached.**
- **Byte-identical direct prompt while a chat prompt is pending → does NOT bind** (no marker present).
- FIFO `prompt-submit → stop` pairing per surface; correct with **multiple agent panels in one workspace** (distinct `SurfaceID`s).
- **needs-input hold:** sending to a `needsInput` target holds (no inject); leaving `needsInput` flushes + injects; held + tab-closed → `.tabClosed`; held + never-unblocks is surfaced.
- `@all` fan-out; replies attach as they arrive; N/M progress correct.
- Forward = new exchange `"\"quoted\"\n<note>"`; reply chains back. Quote-into-composer produces the quoted body as a user draft (not auto-sent).
- Resolve at send time; target removed before send → `.failedToDispatch`.
- Tab closed with pending → `.tabClosed`.
- Identity snapshot frozen at send time (later branch switch doesn't mutate history).
- `loadEarlier()` pages older exchanges; window bound respected.

**Lifecycle:** badge/progress/needs-input derive from the existing lifecycle seam (assert via fake store) — no second source.

**Persistence/migration:** round-trip incl. snapshots; old snapshot without role/kind restores with correct defaults; closed-agent history renders; paged reads.

**Close policy (app-target, through real entrypoints):** `.chatRoom` cannot close via **direct `TabManager.closeWorkspace`**, sidebar X, ⌘W/menu, command palette, **socket `closeWorkspace`**, AppleScript, config replace, or bulk/window close; the internal `force:` teardown path *can* close it. Agent confirm-on-close when `running`.

**Hook bridge (integration):** crafted raw `prompt-submit`(with marker)/`stop` events carrying `surface_id` drive the coordinator; marker recovered from `toolInputJSON`; `last_assistant_message` decoded verbatim; events read pre-redaction; malformed input rejected without crash; no focus change.

**Build gates:** `cmux-unit` compiles; `check-pbxproj.sh` + test-wiring lint pass; new packages present in `ci.yml`.

### 6.2 Manual acceptance (验收 — UX only)
`./scripts/reload.sh --tag chat-room`. Confirm:
1. Chat-room tab pinned, colored, **cannot** close via X, ⌘W, command palette, or context menu.
2. Three agent tabs (Claude/Codex/Cursor) auto-name; show ~pwd + branch (own line); **rotating** spinner while running (static glyph under Reduce Motion).
3. Double-click title → inline rename; pwd/branch read-only.
4. `@claude-code-1 <prompt>` → appears in that tab, runs; on finish **only the final message** posts to the channel, stamped name + ~pwd + branch.
5. Type directly in an agent tab → that final message does **not** appear in the channel (even if it finishes before an in-flight chat prompt, and even if you type byte-identical text).
6. `@all <question>` → grouped exchange; **N/M replied** updates; replies arrive independently.
7. Two agents with the **same title** (or same repo, different branch) → autocomplete rows show kind/~cwd/branch; selecting routes to the intended one.
8. Trigger a permission prompt in one agent → **needs-input** (amber, text label) + notifies that tab; channel does not ring. `@`-sending to it **holds** ("waiting — needs input"); answer the prompt → the held message is delivered and its reply returns.
9. Forward a reply with a note → target gets `"quoted"` + note; reply chains into a new exchange. **Quote-into-composer** drops the quoted text into your composer as your own draft; **copy** copies the raw text; go-to-tab works. Long messages render in full.
10. New-agent sheet failure paths surface inline (branch collision, missing CLI, worktree failure) — no half-created tab.
11. New agent in a **new worktree** → branch/worktree created; tab shows new branch.
12. Close a running agent → confirm; gone from `@`/`@all`; past messages remain.
13. Long channel → only a recent window renders; **"Load earlier"** pages history.
14. Restart → history persists (incl. since-closed agents); agent tabs restore with kind/badges and reappear in `@all`.
15. Notifications: chat tab for replies (unfocused); agent tab for needs-input; no double-ring.

---

## 7. Open items for the reviewer (Codex, round 3)

Resolved since round 2: correlation now uses a **hidden `ChatRequestID` marker** (§4.6) not exact text; `surface_id` is carried end-to-end and events are read **pre-redaction** (§4.4); the close gate moved to the **lowest mutator** with a `force:` path (§4.10); `needsInput` targets are **held, not blind-injected** (§3.11/§4.6).

Remaining for review:
- **Marker viability (Step 0):** the design hinges on a token that (a) survives in `toolInputJSON`, (b) strips cleanly before display/forward, and (c) doesn't derail each agent. Is there a known encoding that's safe across Claude/Codex/Cursor, or should some agents fall back to FIFO + raw-text match with the documented collision limit? What's the right marker form (trailing metadata line? sentinel-wrapped block?)?
- **Final-message availability:** if an agent's `stop` doesn't carry the message, is reading its transcript (`RestorableAgentSession.transcriptPath`) acceptable, or restrict v1 to agents that carry it?
- **`surface_id` threading:** is extending `WorkstreamEvent`/`feed.push` the right layer, and does any consumer assume the current schema?
- **History key:** confirm one-chat-room-per-window and that the window/session id is the right persistence key across restore.
- **`WorkspaceRole` placement:** add to `Workspace` + persistence as proposed, or model the chat room as a distinct workspace subtype?
