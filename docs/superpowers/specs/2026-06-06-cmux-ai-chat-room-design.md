# cmux AI Chat Room — Design & Implementation Plan

> Status: **Draft for review (rev 3)** · Author: Dylan (with Claude) · Date: 2026-06-06
> Review loop: Codex reviews this doc → Claude addresses comments → repeat to convergence → execution.

### Revision history

- **rev 1** — initial spec.
- **rev 2** — incorporates Codex review round 1 (3 independent reviewers, all "Not Ready") after verifying every claim against the code. Major changes: (a) reuse the **existing** cmux agent pipeline — hooks (`CLI/CMUXCLI+AgentHookDefinitions.swift`), launch (`Packages/CMUXAgentLaunch`), lifecycle (`Workspace.agentLifecycleStatesByPanelId`), and the `stop` hook's existing `last_assistant_message` payload — instead of building parallel infrastructure; (b) token-based correlation; (c) fix package layering with a low `CmuxChatRoomCore`; (d) single source of truth for lifecycle; (e) central `WorkspaceRole`-aware close policy; (f) explicit persistence/migration; (g) correct CI test gating; (h) "Step 0" infra audit; (i) UX: richer `@`-autocomplete rows, full (non-collapsed) messages, channel windowing + "load earlier", new-agent failure states, accessibility/reduced-motion.
- **rev 3** — incorporates Codex review round 2 (3 reviewers), verified against code. Major changes: (a) **`surface_id` carried end-to-end** — `WorkstreamEvent`/feed schema extended with `surface_id` (hook layer already has it; `CLI/cmux.swift:205`), and the chat bridge consumes **raw decoded events before EventBus redaction** (`CmuxEventPublishing.swift:451` nulls `tool_input`); per-surface FIFO now works with multiple agent panels per workspace. (b) **Hidden `ChatRequestID` marker** correlation (chosen over exact-text): a non-displayed token is injected with the prompt, round-trips via the raw `toolInputJSON` (`WorkstreamEvent.swift:17`, **not** the whitespace-collapsing `submittedPromptMessage` at `WorkspacePromptSubmit.swift:133`), binds the turn, and is stripped before channel display/forward; FIFO still pairs the bound `prompt-submit` to its `stop`. (c) **Close gate at the lowest mutator** — guard inside `TabManager.closeWorkspace` (`:5205`, which today has only a `guard tabs.count > 1`, no role/can-close guard) with an explicit internal force flag, since AppleScript (`AppleScriptSupport.swift:473`) and config (`CmuxConfigExecutor.swift:508`) call it directly. (d) **needs-input hold** — `send_text` injects raw terminal bytes (`TerminalController.swift:8653`), so prompts to a `needsInput` target are held (not blind-injected into a permission prompt) and delivered when it leaves `needsInput`; running/idle still pipe through immediately. (e) UX: per-message **copy** + **quote-into-composer**.
- **rev 5** — **structural pivot (Dylan): multiple chat rooms in one window**, replacing the single pinned chat room. Sidebar splits into two sections — **top: chat rooms** (multiple, renameable), **bottom: agent tabs grouped by `WorkspaceGroup`**. Each chat room corresponds **1:1 to an agent group** (`groupId`); `@`/`@all` scope to *that room's group* (worktree isolation by construction). Motivation: Dylan currently uses one macOS desktop per worktree and switches between them — this collapses that into one cmux instance. Reuses the **existing** cmux group system (`WorkspaceGroup`, `TabManager.swift:1006`; `Workspace.groupId:10300`; group `+`/rename/placement). Consequences: chat rooms are now normal creatable/renameable/closable entities (keep ≥1); **history keys off `ChatRoomID`** (the old "window/session id" open item is resolved); `@all` and isolation are now per-room.
- **rev 4** — incorporates Codex review round 3, verified against code. (B1) confirmed the marker decision is already fully propagated in rev 3 (no exact-text remains); tightened the §4.6 fallback wording. (B2) **final-message capture is confirmed only for Claude via the OMP wrapper** (`CMUXCLI+OmpExtension.swift:192`); there is **no `claude` entry** and codex/cursor `stop` carrying the message is **unconfirmed** — promoted to a named **go/no-go gate (G1)** in Step 0, sized the transcript fallback, and documented that Claude/OMP (self-managed extension, `events: []`) and codex/cursor (`AgentHookDef` table) use **two different hook-install mechanisms**. (B3) added an **identifier-mapping table** — the lifecycle store is `panelId → agentName → state` and a panel may host multiple agents; specified the `(panelId, agentName) → AgentID/SurfaceID` mapping and the one-agent-per-tab constraint. (B4) §4.10 now commits to auditing **every** direct `closeWorkspace` caller (TabManager `4430/5337/5343/5498/5744/6040/7812/7816`, TerminalController `1450/4426/6810/18104`) with force/non-force labels and addresses the `tabs.count > 1` ↔ non-closable-chat-room interaction. Minor: `AgentKind` gains an explicit unsupported-agent path; history-key is a Step-0 must-resolve, not a baked assumption.

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

A fork of **cmux** (native macOS terminal app with vertical tabs) turned into an **AI chat room**: a Slack-like sidebar with **multiple chat rooms** (top section) over **grouped agent terminal tabs** (bottom section). Each chat room corresponds 1:1 to an agent group; you `@mention` agents to send prompts, each agent's *final* message returns to its room, and you forward messages between agents — while every agent tab remains a fully interactive coding-agent terminal.

Multiple rooms in one window replace Dylan's current habit of **one macOS desktop per worktree** (constant Spaces-switching, or one cmux instance per worktree). Now a single instance holds a room per worktree/feature, and `@all` stays scoped to that room's agents — so parallel worktrees don't interfere.

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
| **Existing sidebar groups** | `Sources/TabManager.swift:1006` (`WorkspaceGroup`); `Sources/Workspace.swift:10300` (`groupId`) | named, collapsible groups; group `+`-button (`workspace.group.new_workspace`), placement settings, group rename, anchor-close — **reuse as the agent-group / chat-room binding** |
| **Existing agent lifecycle** | `Sources/Workspace.swift:10559` | `agentLifecycleStatesByPanelId: [UUID:[String:AgentHibernationLifecycleState]]` |
| Lifecycle states | `Sources/AgentHibernation/AgentHibernationLifecycleState.swift:3` | `unknown / running / idle / needsInput` |
| Lifecycle mutation + CLI | `Sources/Workspace.swift:12287`; `Sources/TerminalController.swift:19378` | `setAgentLifecycle(...)`, `set_agent_lifecycle` CLI |
| **Existing agent hook defs** | `CLI/CMUXCLI+AgentHookDefinitions.swift:142-256` | table-based hooks for codex/cursor/gemini/grok/kiro/… ; events `prompt-submit`, `stop`, `agent-response`, `session-end/-finalize`. **No `claude` entry** — Claude runs via the OMP wrapper (self-managed extension; `events: []` in the table) |
| **Final-message payload (Claude/OMP only)** | `CLI/CMUXCLI+OmpExtension.swift:192` | `sendHook("stop", ctx, { last_assistant_message })` — verified for OMP/Claude only; **codex/cursor `stop` carrying the final text is unconfirmed (gate G1, §5)** |
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

### 3.1 Two-section sidebar: chat rooms over grouped agents
The sidebar has two sections:
- **Top — Chat rooms:** N chat rooms (each colored, renameable). One is "active" (its channel is shown). Creatable/closable; keep ≥1.
- **Bottom — Agents:** agent tabs organized into **groups** (reusing cmux `WorkspaceGroup`). **Each group corresponds 1:1 to a chat room.** Bash tabs dropped — an agent tab is a real terminal (shell via the agent's `!`).

**Room ⟷ group correspondence (the core structure):** selecting a chat room scopes everything to its group. `@` autocomplete and `@all` resolve to **that room's group only**; agents in other rooms are untouched. This makes worktree isolation *structural* rather than manual — a room per worktree/feature, `@all` never crosses contexts.

- **Membership:** an agent tab belongs to **exactly one** group/room (one agent → one room). No "ungrouped" agents.
- **Creation:** a new chat room creates a new (empty) group; the group header's `+` creates an agent tab **into the active room**. Agent creation (kind + worktree, §4.9) targets the active room's group.
- **Moving:** drag an agent tab between groups to reassign it to another room.

![Two-section sidebar: each agent group ⟷ one chat room](assets/2026-06-06-chat-room/two-section-rooms.png)

*(Selecting `#feature-auth` lights its group and scopes `@all` to it; `refactor-db`/`scratch` agents are untouched. Earlier single-room mockups under `assets/` predate this pivot.)*

### 3.2 Sidebar — agent tabs (three lines + live status)
Editable title (auto-named "claude code 1"), then **~pwd**, then **branch on its own line**. Live lifecycle badge from the **existing** `agentLifecycleStatesByPanelId`: rotating green spinner = `running`, dim dot = `idle`, pulsing amber + `!` = `needsInput`.

![Sidebar with status badges and spinner](assets/2026-06-06-chat-room/sidebar-v2.png)

### 3.3 Rename = title only
Double-click the title text → inline edit (pre-selected; Enter saves / Esc cancels). Same action via right-click → Rename and command palette → Rename Tab. pwd/branch read-only.

![Inline rename of the title](assets/2026-06-06-chat-room/rename.png)

### 3.4 Routing rule — chat-origin replies only
An agent's final message returns to **its room's channel** **only** if the prompt came from that room. Direct turns stay in the tab. Guaranteed by token correlation (§4.6), not heuristics.

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
You type/match the **name** (`@`), but each autocomplete **dropdown row shows name + kind + ~cwd + branch** so duplicate/renamed titles and "same repo, different branch" are distinguishable. Selection stores a **stable `AgentID`**, never the display string. The dropdown is **rebuilt fresh each time it opens** and is **scoped to the active room's group** — only that room's live agents appear; `@all` = that group. (Agents in other rooms are deliberately unreachable from here — isolation by construction.)

### 3.11 Sending vs. agent state
Prompts inject **raw terminal input** (not a semantic queue), so state matters:
- **running / idle** → injected immediately (these TUIs buffer follow-up input safely).
- **needs-input** (agent sitting at a permission/y-n prompt) → **held, not injected** (a blind injection could answer the dialog with garbage). The exchange shows that target as *"waiting — agent needs input"* with a jump-to-tab link; the held prompt is delivered automatically once the agent leaves `needsInput`. If the agent never leaves it (or the tab closes), the held prompt resolves to `failedToDispatch` / `tabClosed`.

### 3.12 Notifications (v1)
Disjoint events, no double-ring:
- **Completion** (chat-origin turn finished) → notifies **its chat room** (badge on that room in the top section) when that room isn't the active/focused one.
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
public struct AgentID: Hashable, Sendable, Codable { public let raw: UUID }      // = agent workspace/tab id
public struct SurfaceID: Hashable, Sendable, Codable { public let raw: UUID }    // agent's terminal surface
public struct ChatRoomID: Hashable, Sendable, Codable { public let raw: UUID }   // a chat room (= its WorkspaceGroup)
public struct ChatRequestID: Hashable, Sendable, Codable { public let raw: UUID } // correlation token
public struct MessageID: Hashable, Sendable, Codable { public let raw: UUID }
public struct ExchangeID: Hashable, Sendable, Codable { public let raw: UUID }

/// A chat room: a named channel bound 1:1 to an agent group (`WorkspaceGroup`).
public struct ChatRoom: Sendable, Codable, Identifiable {
    public let id: ChatRoomID
    public var name: String          // renameable
    public let groupId: UUID         // the bound cmux WorkspaceGroup; its members are this room's agents
}

public enum AgentKind: String, Sendable, Codable { case claudeCode, codex, cursor }
// v1 supports exactly these three. The lifecycle store admits ~16 agent-name strings and the hook
// table has more (grok/gemini/kiro/…). Roster derivation maps an unknown agent name to `nil` kind →
// the tab is treated as "unsupported": not @-mentionable, no crash (see §4.3 identifier mapping).

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
    public let roomID: ChatRoomID      // which room this exchange lives in
    public let origin: PromptOrigin
    public let bodyText: String        // forward: "\"<quoted>\"\n<note>"
    public let targets: [AgentIdentitySnapshot]   // resolved from this room's group only
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

**Identifier spaces.** These must not be conflated:

| Coordinate | Type | Meaning | Owner |
|---|---|---|---|
| `ChatRoomID` | `UUID` | a chat room | `RoomsCoordinator` (§4.6) |
| `groupId` | `UUID` | the cmux `WorkspaceGroup` a room is bound to; its members are the room's agents | `TabManager` |
| `AgentID` | `UUID` | the agent **tab/workspace** id (belongs to exactly one `groupId`) | `TabManager` |
| `SurfaceID` | `UUID` | the agent's **terminal surface** (= cmux `panelId`) | `Workspace.panels` |
| `panelId` | `UUID` | key of the existing lifecycle store | `Workspace.agentLifecycleStatesByPanelId` |
| `agentName` | `String` | inner key of the lifecycle store (`"claude_code"`, `"codex"`, …); a panel may hold several | the agent CLI / hook |

**Room ↔ group:** `ChatRoom.groupId` is the binding; a room's agents = the live workspaces with that `groupId`. An agent's room is `agent.groupId → ChatRoomID` (each `groupId` maps to exactly one room).
**v1 constraints:** one agent per agent-tab (so `SurfaceID == panelId`; lifecycle lookup `agentLifecycleStatesByPanelId[panelId][agentName]`), and one agent → one group/room. The `AgentRosterProviding`/`AgentLifecycleReading` seams (app target) own the `AgentID ↔ (panelId, agentName)` map and the `groupId ↔ ChatRoomID` map, exposing only `AgentID`/`SurfaceID`/`ChatRoomID` to the coordinator; a panel reporting multiple agent names → tab flagged unsupported, not guessed.

### 4.4 Reuse the existing hook pipeline (no new transport)

The agent CLIs already run cmux hooks (`CLI/CMUXCLI+AgentHookDefinitions.swift`) that call `cmux hooks <agent> <subcommand>` over the socket. We **extend the app-side handling** of two events already in the pipeline rather than writing new hook scripts or a `chat.agent_report` command:

- `prompt-submit` — carries the submitted prompt text.
- `stop` (a.k.a. `agent-response`) — carries `last_assistant_message` **for Claude via the OMP wrapper only** (`CMUXCLI+OmpExtension.swift:192`). **Whether codex/cursor `stop` carries the final message is unconfirmed** (see gate G1).

App-side, these are routed (per surface) into a `CmuxChatRoomCore.AgentTurnEvent` stream the coordinator subscribes to.

**Two hook-install mechanisms, not one (verified).** "Reuse `CMUXAgentLaunch`" is *not* uniform across agents:
- **Claude** runs through the **OMP self-managed extension** — its hook entry has `events: []` in the table and OMP installs/owns its own hooks; this is the only path verified to emit `last_assistant_message`.
- **codex/cursor/etc.** use the **`AgentHookDef` table** (`prompt-submit`/`stop`/…). Their final-message payload is unverified.
So the chat bridge must handle both install/report shapes; the spec no longer assumes a single symmetric "claude/codex/cursor hook."

**Gate G1 (go/no-go, in Step 0): can the *reviewer* return its text?** The product has no value until Codex (the reviewer half of the core use case) can post its final message to the channel. Step 0 must confirm, per codex and cursor, that *either* `stop` carries the final message *or* it is recoverable from the transcript (`RestorableAgentSession.transcriptPath`, §7). **Size the transcript fallback now** — it is a materially larger lift than an adapter (locate + tail the per-agent transcript, parse the last assistant turn, map session→surface), and if needed it moves out of "Step 0 finding" into its own implementation step before that agent ships. If neither path works for an agent, that agent is **not in v1** (explicit, not silent).

**Step 0 also confirms**, per agent, that `prompt-submit` fires for *injected* input and that the marker (§4.6) round-trips through that agent's prompt handling without the agent choking on it.

**Two schema/plumbing fixes required (verified gaps):**
- **`surface_id` must be carried end-to-end.** `WorkstreamEvent` currently has `workspaceId` but no `surfaceId` (`WorkstreamEvent.swift:14`); the hook layer already knows the surface (`CLI/cmux.swift:205`), so extend the `feed.push`/`WorkstreamEvent` schema with `surface_id` and thread it through. Without it, per-surface FIFO collapses when a workspace holds multiple agent panels.
- **Consume RAW events before redaction.** The public `EventBus` nulls `tool_input`/`context` bodies (`CmuxEventPublishing.swift:451`). The chat bridge must tap the **raw decoded `WorkstreamEvent`** (`toolInputJSON`/`extraFieldsJSON`, `WorkstreamEvent.swift:17,22`) *before* that redaction — both to read the prompt and to recover the marker. It must **not** use `submittedPromptMessage`, which collapses whitespace (`WorkspacePromptSubmit.swift:133`) and would corrupt multiline prompts/forwards.

`AgentRosterProviding` (live tabs → mentionable set) and `PromptInjecting` (wrap `surface.send_text` + submit, non-focus-stealing) are protocol seams in `CmuxChatRoomCore`, implemented in the app target over `TabManager` / `TerminalController`.

### 4.5 Lifecycle: single source of truth

The coordinator does **not** keep its own lifecycle dictionary. Sidebar badges, exchange progress, and the needs-input notification all read the **existing** `Workspace.agentLifecycleStatesByPanelId` (already updated by `set_agent_lifecycle`). The coordinator observes it via a read-only seam (`AgentLifecycleReading`, exposing a snapshot + `AsyncStream` of changes keyed by `AgentID`) implemented in the app over the existing store. No drift with hibernation/sidebar.

The seam performs the identifier mapping from §4.3: for an agent tab it resolves `AgentID → (panelId, agentName)` and reads `agentLifecycleStatesByPanelId[panelId][agentName]`. It is the **only** place that crosses between the chat-room id space (`AgentID`/`SurfaceID`) and the store's `(panelId, agentName)` space; the coordinator never sees `panelId`/`agentName`.

### 4.6 Coordinator + marker correlation + needs-input hold (`CmuxChatRoom`, `@MainActor @Observable`)

```swift
/// Owns all chat rooms; correlation queues are global (a surface belongs to one agent in one room).
@MainActor @Observable
public final class RoomsCoordinator {
    public private(set) var rooms: [ChatRoom] = []
    public private(set) var activeRoom: ChatRoomID?
    private var byRoom: [ChatRoomID: RoomChannel] = [:]            // per-room channel state

    // global correlation (keyed by surface / request, not by room)
    private var turnQueueBySurface: [SurfaceID: [TurnBinding]] = [:]
    private var pendingByRequest: [ChatRequestID: PendingInjection] = [:]
    private var heldForNeedsInput: [AgentID: [HeldPrompt]] = [:]   // §3.11 safety hold

    private let roster: any AgentRosterProviding   // resolves a room's group → live agents
    private let lifecycle: any AgentLifecycleReading
    private let injector: any PromptInjecting
    private let notifier: any ChatNotifying
    private let history: any ChatHistoryStore

    public func createRoom(name: String) async -> ChatRoomID { … }   // also creates the bound WorkspaceGroup
    public func renameRoom(_ id: ChatRoomID, to: String) async { … }
    public func closeRoom(_ id: ChatRoomID) async { … }              // §4.10; keep ≥1
    public func send(in room: ChatRoomID, _ body: String, to mentions: [AgentMention], origin: PromptOrigin) async { … }
    public func forward(_ message: MessageID, to: [AgentMention], note: String) async { … }
    public func handle(_ event: AgentTurnEvent) { … }               // routes via request→room map
    public func onLifecycleChange(_ id: AgentID, _ state: AgentLifecycle) { … }
    public func loadEarlier(in room: ChatRoomID) async { … }
}

/// One room's view state (bounded window in UI; full set in the store).
struct RoomChannel { var roomID: ChatRoomID; var exchanges: [Exchange] }

struct PendingInjection { let requestID: ChatRequestID; let exchangeID: ExchangeID; let roomID: ChatRoomID; let surface: SurfaceID }
struct HeldPrompt { let requestID: ChatRequestID; let exchangeID: ExchangeID; let roomID: ChatRoomID; let bodyWithMarker: String }
enum TurnBinding { case chatOrigin(ChatRequestID, ExchangeID, ChatRoomID); case direct }
```

**Correlation invariant (the core of the routing rule) — marker-based, room-scoped:**

1. `send(in: room, …)`: resolve mentions **against `room`'s group only** → live `AgentID`/`SurfaceID` at send time (mentions outside the group are not offered; dead → `.failedToDispatch`). Create one `Exchange` with `roomID = room`. For each target: mint a `ChatRequestID` (recorded with its `roomID`), build `bodyWithMarker = ChatPromptMarker.inject(id, into: body)`, mark outcome `.pending`. **If the target is `needsInput`**, hold (§3.11); **otherwise** record `pendingByRequest[id]` and inject `bodyWithMarker`. Persist to that room's history.
2. `handle(.promptSubmitted(surface, rawPromptText))`: `let (id, _) = ChatPromptMarker.extract(from: rawPromptText)`. If `id` is present **and** in `pendingByRequest` → remove it, append `.chatOrigin(id, exchangeID, roomID)` to `turnQueueBySurface[surface]`. Else append `.direct`. (Binding requires the marker — a direct turn, even byte-identical, has no marker and is never chat-origin.)
3. `handle(.turnCompleted(surface, finalMessage))`: pop the **front** of `turnQueueBySurface[surface]` (agents process turns in order). `.chatOrigin` → attach `finalMessage` to that exchange/target **in its `roomID`'s channel**, persist, notify that room (if it isn't the active/focused room). `.direct` → **drop**.
4. `onLifecycleChange(agent, state)`: when an agent leaves `needsInput`, flush `heldForNeedsInput[agent]` — for each held prompt, record `pendingByRequest` and inject `bodyWithMarker`.
5. Tab closed: `.pending`/held outcomes for that agent → `.tabClosed`; clear its queues/holds.

The marker makes binding independent of prompt text, so a byte-identical direct prompt while a chat prompt is pending can no longer mis-bind (it carries no marker). A direct turn that completes first is bound `.direct` and dropped. No marker ⇒ no chat binding ⇒ no leak.

> **The marker is the only correlation mechanism in v1.** There is no exact-text matching path in the design (exact-text is broken anyway — `submittedPromptMessage` collapses whitespace, `WorkspacePromptSubmit.swift:133`). **Marker design constraints** (encoding fixed in Step 0): the token must (a) survive verbatim in `toolInputJSON`, (b) strip reliably before any channel display/forward, (c) not derail the agent. Candidate: a single trailing line the agent treats as inert metadata. If a specific agent cannot carry the marker cleanly, that agent is handled by a **documented, explicitly-degraded per-adapter fallback** (per-surface FIFO + raw `toolInputJSON` match, with the byte-identical-same-surface collision called out and tested) — a contained per-agent exception, never the default path.

### 4.7 Live roster (no parallel registry), per room
`AgentRosterProviding` is implemented over `TabManager`, exposing `current(inGroup:)` + an `AsyncStream` of changes; a room's mentionable set is *derived* from live workspaces whose `groupId` == the room's group. `@all` = that group's live agents at send instant. The autocomplete dropdown calls `current(inGroup:)` for the active room on open (§3.10). No parallel registry — the groups *are* the membership.

### 4.8 Two-section sidebar + chat-room panels (app target)
- **Top section (chat rooms):** rendered from `RoomsCoordinator.rooms`; each row colored + renameable (reuse `customTitle`-style rename), with an unread badge (§3.12). Selecting one sets `activeRoom`.
- **Bottom section (agents):** the existing cmux grouped sidebar (`WorkspaceGroup`), where **each group is a room's membership** (`ChatRoom.groupId`). Reuse the group header `+` (creates an agent into that group/room), group rename, collapse, and drag-to-reorder/move (moving across groups reassigns the agent's room).
- Chat-room workspace: `WorkspaceRole` (`.chatRoom` / `.agent`); a `.chatRoom` carries its `ChatRoomID` and bound `groupId`. Rooms are **creatable / renameable / closable** (keep ≥1) — *not* a single pinned home base anymore.
- Agent tab: `WorkspaceRole.agent` + `AgentKind` + its `groupId`; auto-named; sidebar three-line layout + lifecycle badge (snapshot-fed row — coordinator never injected into the row).
- `ChatRoomPanel: Panel` — because `Panel` requires `ObservableObject`, this is a **thin legacy shell** in the app target; real state lives in the `@Observable` `RoomsCoordinator` (package), which the shell holds and forwards to. Intentional adapter until `Panel` is modernized.
- `ChatRoomView` (`CmuxChatRoomUI`): renders the **active room's** channel — exchange list (windowed, snapshot-fed rows + "Load earlier"), composer with group-scoped `@` autocomplete (§3.10), per-message actions **forward / quote-into-composer / copy / go-to-tab** (§3.7), full messages (§3.8), progress + needs-input/held status, markdown rendering.

### 4.9 Create-agent + worktree sub-flow (with failure states)
"New agent" sheet: (1) kind; (2) location — *current pwd/branch* or *new worktree* (base branch + new branch + parent dir → `git worktree add <path> -b <branch> <base>`); then launch via `CMUXAgentLaunch`, auto-name, add to roster.
**Failure/validation (inline, recoverable):** path or branch collision; dirty/missing base repo; missing CLI binary; unsupported/uninstalled hook for that agent; `git worktree add` failure; partial launch (surface created but agent didn't start → offer retry/close). Each surfaces an inline error in the sheet; nothing half-creates silently.

### 4.10 Close policy (gate at the lowest mutator)
Rooms are normal closable entities now, but two invariants still need a gate at the **destructive funnel**: **keep ≥1 room**, and a room-close cleans up its group. Verified: `TabManager.closeWorkspace` (`:5205`) today has only `guard tabs.count > 1 else { return }` (no role/can-close guard) and is called **directly** by many paths that bypass the UI's `canCloseWorkspace`. So:

- Add a required `WorkspaceRole` to `Workspace`; change `closeWorkspace` to take `force: Bool = false` and return a result (closed / refused). It **refuses closing the *last* `.chatRoom`** (keep ≥1) unless `force` (app teardown). `canCloseWorkspace` remains a **UI affordance only**.
- **Closing a chat room** (not the last): confirm if any of its agents are `running`; then close the room and, by the one-agent-one-room rule, **close its group's agent tabs too** (each as below). History for that room is retained in the store (re-openable later by id) unless the user explicitly purges.
- **Execution must audit and label every direct `closeWorkspace` caller** as force or non-force (Step 0 re-greps; not exhaustive):

  | Caller | Path | Default |
  |---|---|---|
  | `TerminalController:18104` | socket `close_workspace` | non-force |
  | `TerminalController:1450,4426` | socket dispatch | non-force |
  | `TerminalController:6810` | `workspace.unpin.related_workspaces` | non-force |
  | `AppleScriptSupport:473,624` | AppleScript | non-force |
  | `CmuxConfigExecutor:508` | config replace | **force** (bootstrap/replace) |
  | `TabManager:5337,5343` | `closeTab` / `closeCurrentWorkspace` | non-force |
  | `TabManager:4430,5498,5744` | group delete / post-confirm batch | non-force; group delete = close that room |
  | `TabManager:6040,7812,7816` | internal cleanup / teardown | **force** |

- **`tabs.count > 1` interaction:** the keep-≥1-room invariant means a window always retains one chat room, so the guard never strands the last *agent* tab. **Close-all / window-teardown `force`-closes rooms last.** Reuse the existing **group-delete** path (`TabManager:4430`) as "close room": deleting a group = closing its room.
- Agent tabs: confirm-on-close when `running`; pending/held outcomes → `.tabClosed`; removed from roster. Closing an agent never erases its past messages (identity snapshots persist).

### 4.11 Persistence + migration
`ChatHistoryStore` (actor-backed repository, JSON under Application Support). Stores all exchanges/replies with embedded `AgentIdentitySnapshot`; supports **paged reads** for "Load earlier" (§3.9) and bounded initial load.
**History keys off `ChatRoomID`** — the room is a first-class, persisted entity with its own stable id, so the old "what id survives restore?" problem is gone. Each room's history file is keyed by its `ChatRoomID`.
Session snapshots gain explicit fields (migration defaults for old data):
- **Rooms list** — the set of `ChatRoom`s (`id`, `name`, `groupId`) and which is active, persisted with the window/session. (Migration: an existing session with no rooms gets one default room whose group is a new group containing its agent tabs.)
- `SessionWorkspaceSnapshot.role: WorkspaceRole?` (default: `.chatRoom` if it was the room workspace, else `.agent`) and the agent **kind** on the panel/agent snapshot (`SessionTerminalPanelSnapshot.agent` extended or sibling). `groupId` is already persisted (`SessionWorkspaceSnapshot.groupId`).
On restore: rebuild rooms from the persisted list; bind each to its `groupId`; re-derive each room's roster from restored agent workspaces' `groupId`; reconnect each room's history by `ChatRoomID`. Without role/kind, restored agent tabs would lose kind/badges and their room binding — required, not optional.

### 4.12 Data flow

```mermaid
flowchart LR
  U[Human in active room] -- "@mention / forward / quote (scoped to room group)" --> CO[RoomsCoordinator]
  CO -- "inject body + hidden ChatRequestID marker (held if needsInput)" --> SURF[Agent terminal surface]
  SURF --> AG[Agent CLI]
  AG -- "existing hooks: prompt-submit(raw toolInputJSON) / stop(last_assistant_message)" --> HK[cmux hooks route]
  HK -- "raw WorkstreamEvent + surface_id, pre-redaction" --> APP[app-side hook bridge]
  APP -- "AgentTurnEvent (SurfaceID)" --> CO
  CO -- "extract marker → bind; FIFO pop → route by roomID" --> EX[Exchange replies in that room]
  EX --> UI[ChatRoomView - active room, windowed]
  LC[Workspace.agentLifecycleStatesByPanelId] -- read-only seam --> CO
  CO -- "leaves needsInput → flush held prompts" --> SURF
  TM[TabManager groups + live tabs] -- AsyncStream --> CO
  CO -- "completion in non-active room" --> NCH[badge that room]
  LC -- needsInput --> NAG[notify agent tab]
```

---

## 5. Execution steps

Vertical slice: Claude Code end-to-end *before* Codex/Cursor. Two-commit red/green per regression test.

0. **Existing-infra audit + gates (no code).** Produce a findings note that confirms/adjusts §4.3–§4.11 and resolves these before any code:
   - **Gate G1 (go/no-go): can codex and cursor return their final message?** Confirm `stop` carries it, or that it's recoverable from `RestorableAgentSession.transcriptPath`. **Size the transcript fallback** (locate/tail transcript, parse last assistant turn, map session→surface); if needed it becomes its own step before that agent ships. An agent that can do neither is **out of v1** (explicit).
   - **Marker encoding** — fix a concrete token that round-trips through `toolInputJSON` and that Claude/codex/cursor each tolerate (test all three); per-agent degraded fallback (§4.6) where it can't.
   - **`surface_id` threading** — where it's available at the hook layer (`CLI/cmux.swift:205`) and how to add it to `WorkstreamEvent`/`feed.push` without breaking existing consumers.
   - **Identifier mapping** — confirm one-agent-per-tab, the `AgentID ↔ (panelId, agentName)` resolution, and the `groupId ↔ ChatRoomID` binding (§4.3).
   - **Existing group API** — confirm `WorkspaceGroup` supports programmatic create/rename/move-member/delete and exposes membership + ordering for the bottom section + room binding (§4.8).
   - **Hook-install mechanisms** — Claude/OMP (self-managed) vs `AgentHookDef` table (codex/cursor); the bridge handles both.
   - **Close-caller audit** — re-grep every direct `closeWorkspace` caller; label force/non-force; confirm group-delete (`TabManager:4430`) is the "close room" path (§4.10).
   - Plus: that `prompt-submit` fires for *injected* input per agent, and the CI package-test list. (History key is now `ChatRoomID` — resolved, no longer a gate.)
1. **Scaffold packages.** `CmuxChatRoomCore`, `CmuxChatRoom`, `CmuxChatRoomUI` (+ Swift Testing targets). Add all three to `.github/workflows/ci.yml` `PACKAGES`. Wire any app-target test files into `project.pbxproj`; run `normalize-pbxproj.py` + `check-pbxproj.sh`.
2. **Core model.** §4.3 DTOs + `ChatPromptMarker` + protocol seams in `CmuxChatRoomCore`. Unit-test `ChatPromptMarker.inject`/`extract` round-trip incl. multiline/forward bodies.
3. **`RoomsCoordinator` + correlation (pure).** Implement §4.6 against fakes (multi-room). **Correlation tests first (red/green):** direct turn dropped; direct completes-first while chat pending; **byte-identical direct prompt (no marker) does not bind**; marker bind/strip; FIFO pairing per surface; **completion routes to the originating room (not the active room)**; **`@all` resolves only the active room's group**; **needs-input hold then flush**; forward/quote; resolve-at-send-time.
4. **Persistence.** `ChatHistoryStore` actor + JSON + paged reads; round-trip + migration tests (injected temp dir).
5. **`surface_id` + raw-event hook bridge.** Extend `WorkstreamEvent`/`feed.push` with `surface_id`; tap **raw decoded events before EventBus redaction**; map `prompt-submit`(raw `toolInputJSON`)/`stop` → `AgentTurnEvent`. Lifecycle read-only seam over `agentLifecycleStatesByPanelId`; injection seam over `surface.send_text` (multi-line safe, non-focus-stealing).
6. **Claude Code end-to-end** via `CMUXAgentLaunch`: create agent tab → `@` → inject body + marker → bound via marker at `prompt-submit` → `stop` final message → channel reply. Verify marker is stripped from the displayed reply path.
7. **Two-section sidebar + rooms (§4.8).** Top chat-rooms section over the existing grouped agents section; `WorkspaceRole`; room create/rename/select bound to `WorkspaceGroup` create/rename; active-room selection; drag-to-move agent between groups = reassign room.
8. **Chat-room panel + UI.** `ChatRoomPanel` shell + `ChatRoomView` for the active room (windowed snapshot-fed exchanges, "Load earlier", group-scoped `@` autocomplete §3.10, forward composer, **quote-into-composer + copy** §3.7, full messages, progress + needs-input/held status, jump-to-tab, a11y/reduced-motion).
9. **Agent tab UX.** `AgentKind`; auto-name; three-line sidebar + lifecycle badge; inline rename via existing `customTitle` action.
10. **Create-agent + worktree sheet** with failure states (§4.9); creates into the active room's group.
11. **Close policy (§4.10)** — `force:` flag in `TabManager.closeWorkspace`; keep-≥1-room; group-delete = close room (+ its agents); verify via direct call, AppleScript, config replace, socket, palette/menu, bulk.
12. **Notifications** split (completion→originating room badge, needs-input→agent tab).
13. **Persistence/restore (§4.11)** — rooms list + room↔group binding + role/kind migration; per-room history by `ChatRoomID`; roster re-derivation by `groupId`.
14. **Codex adapter** — **blocked on gate G1**; wire `stop`→final-message (or the sized transcript fallback if G1 requires it); degrade gracefully. Codex is the reviewer half of the core use case, so this is the first non-Claude milestone with real product value.
15. **Cursor adapter** — same; subject to G1; document limitations.
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

**Rooms / scoping (the pivot):**
- `@all` in room A resolves **only A's group**; an agent in room B is not offered and not targeted.
- A completion from an agent in room B **routes to B's channel**, even while room A is active.
- Isolation: a prompt in room A never appears in room B's history.
- Membership: each agent has exactly one `groupId`→room; moving an agent to another group reassigns its room; an agent with an unknown/missing group is excluded (no crash).
- Close room (not last) → its agents close; its history is retained and re-loads by `ChatRoomID`. Closing the **last** room is refused (keep ≥1).

**Lifecycle + identifier mapping:** badge/progress/needs-input derive from the existing lifecycle seam (assert via fake store) — no second source. The seam resolves `AgentID → (panelId, agentName)` correctly (assert mapping); a panel reporting an **unknown/unsupported agent name** → tab flagged unsupported, excluded from the `@` roster, **no crash**; a panel reporting **multiple** agent names → flagged unsupported (one-agent-per-tab invariant).

**Persistence/migration:** round-trip rooms list + room↔group binding + exchanges/snapshots; history reloads per `ChatRoomID`; old (pre-rooms) snapshot migrates to one default room over a group of its agents; old snapshot without role/kind restores with correct defaults; closed-agent history renders; paged reads.

**Close policy (app-target, through real entrypoints):** the **last** `.chatRoom` cannot close via **direct `TabManager.closeWorkspace(force:false)`**, sidebar X, ⌘W/menu, command palette, **socket `closeWorkspace`**, AppleScript, config replace, or bulk/`close-all`; the internal `force:true` teardown path *can*. A **non-last** room closes (group-delete path) and closes its agents; its history persists and reloads by id. Close-all / window-teardown force-closes rooms last; no orphaned history. Agent confirm-on-close when `running`.

**Hook bridge (integration):** crafted raw `prompt-submit`(with marker)/`stop` events carrying `surface_id` drive the coordinator; marker recovered from `toolInputJSON`; `last_assistant_message` decoded verbatim; events read pre-redaction; malformed input rejected without crash; no focus change.

**Build gates:** `cmux-unit` compiles; `check-pbxproj.sh` + test-wiring lint pass; new packages present in `ci.yml`.

### 6.2 Manual acceptance (验收 — UX only)
`./scripts/reload.sh --tag chat-room`. Confirm:
1. Sidebar shows two sections — chat rooms on top, grouped agents below. Create a second room; rename a room; each room is colored.
2. Create agent tabs into a room's group (Claude/Codex/Cursor): auto-name; show ~pwd + branch (own line); **rotating** spinner while running (static glyph under Reduce Motion); each appears under its room's group.
3. Double-click an agent title → inline rename; pwd/branch read-only.
4. In room A, `@claude-code-1 <prompt>` → appears in that tab, runs; on finish **only the final message** posts to **room A's** channel, stamped name + ~pwd + branch.
5. Type directly in an agent tab → its final message does **not** appear in any channel (even if it finishes before an in-flight chat prompt, and even byte-identical text).
6. In room A, `@all <question>` → targets **only room A's agents**; room B's agents are neither offered nor hit. **N/M replied** updates; replies arrive independently.
7. Two agents with the **same title** (or same repo, different branch) → autocomplete rows show kind/~cwd/branch; selecting routes to the intended one.
8. Permission prompt in one agent → **needs-input** (amber, text label) + notifies that tab; channel does not ring. `@`-sending to it **holds** ("waiting — needs input"); answer it → held message delivers and its reply returns.
9. Forward a reply with a note → target gets `"quoted"` + note; reply chains into a new exchange. **Quote-into-composer** drops quoted text into your composer as a draft; **copy** copies raw text; go-to-tab works. Long messages render in full.
10. New-agent sheet failure paths surface inline (branch collision, missing CLI, worktree failure) — no half-created tab; created into the active room.
11. New agent in a **new worktree** → branch/worktree created; tab shows new branch, under the active room's group.
12. **Cross-room:** while viewing room A, a reply lands in room B → room B shows an unread badge; switching to B shows it. No leakage into A.
13. **Move:** drag an agent from room A's group to room B's → it's now reachable from B's `@`, not A's.
14. Close a running agent → confirm; gone from its room's `@`/`@all`; past messages remain. Close a non-last room → its agents close, its history persists (re-openable); the last room can't be closed.
15. Long channel → only a recent window renders; **"Load earlier"** pages history.
16. Restart → rooms + per-room history persist (incl. since-closed agents); agent tabs restore under their groups with kind/badges and reappear in the right room's `@all`.
17. Notifications: a room badges for its replies (when not active); agent tab for needs-input; no double-ring.

---

## 7. Open items for the reviewer (Codex, next round)

Resolved in rev 3–4 (round-2/3 feedback): correlation is a **hidden `ChatRequestID` marker only** — exact-text fully removed from the design (B1, confirmed clean: `rg` finds no `exactText`/`exact-text` in the body); `surface_id` carried end-to-end, events read **pre-redaction** (§4.4); close gate at the **lowest mutator** with `force:` + a full caller-audit table and the `tabs.count`/close-all interaction (§4.10); `needsInput` targets **held, not blind-injected** (§3.11/§4.6); **identifier-mapping table** for `AgentID`/`SurfaceID`/`panelId`/`agentName` (§4.3/§4.5); `AgentKind` unsupported-agent path; **two hook-install mechanisms** (Claude/OMP vs table) documented (§4.4).

Resolved by the rev-5 multi-room pivot: **history key** is now the room's own `ChatRoomID` (no window/session-id guessing); `@all` scope and worktree isolation are structural (per-room group).

Remaining — the real risks now live in **Step 0 gates**, not the design body:
- **G1 — can the reviewer return text? (biggest risk.)** Final-message capture is verified **only for Claude via OMP**; codex/cursor are unconfirmed. The product has no value until Codex can post review text. G1 must confirm `stop`-carries-message or size the transcript fallback (`RestorableAgentSession.transcriptPath`) before the Codex adapter ships. Transcript fallback acceptable for v1, or restrict to agents that carry the message?
- **Marker viability (Step 0):** a token that survives `toolInputJSON`, strips before display/forward, and doesn't derail Claude/Codex/Cursor. Right form? Per-agent degraded fallback acceptable where it can't?
- **`surface_id` threading:** is extending `WorkstreamEvent`/`feed.push` the right layer; does any consumer assume the current schema?
- **Group API sufficiency:** does `WorkspaceGroup` expose programmatic create/rename/move-member/delete + membership/order for the room binding (§4.8), or is new group API needed?
- **Room↔group lifetime:** on close, retain a room's history for re-open (proposed) vs purge — and is "delete group = close room" the right reuse, given group-delete's existing anchor-close confirmation (`TabManager:5768`)?
- **`WorkspaceRole` + room model placement:** `WorkspaceRole` on `Workspace` + a persisted rooms list as proposed, or model the chat room as a distinct workspace subtype?
