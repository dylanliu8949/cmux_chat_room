# cmux AI Chat Room — Foundation Implementation Plan (Plan 1 of 2)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the three chat-room packages' **pure, app-independent core** — value-typed data model, the hidden correlation marker, the `RoomsCoordinator` routing engine (against fakes), and a JSON history store — fully unit-tested and gated in CI, so the later app-integration plan only has to compose concretes behind already-tested seams.

**Architecture:** Two SwiftPM packages under `Packages/`, layered downward only: `CmuxChatRoomCore` (Core: `Sendable` DTOs, IDs, `ChatPromptMarker`, protocol seams — no AppKit/cmux deps) → `CmuxChatRoom` (Domain: `@MainActor @Observable RoomsCoordinator`, correlation, needs-input hold, `JSONChatHistoryStore`). Everything the coordinator touches is a protocol seam, so the whole package suite runs headlessly via `swift test` with in-memory fakes. The UI package (`CmuxChatRoomUI`) and all app/cmux wiring are **Plan 2** (they depend on Step 0's empirical findings, which this plan does not).

**Tech Stack:** Swift 6 (`swift-tools-version: 6.0`, `.swiftLanguageMode(.v6)`), Swift Concurrency (`actor` / `async` / `AsyncStream` / `@Observable` / `@MainActor`; no Combine / `@Published` / locks / `DispatchQueue`), Swift Testing (`import Testing`, `@Test`, `#expect`, `#require`), Foundation `Codable` + `JSONEncoder`/`JSONDecoder`.

---

## Scope & boundaries

**In scope (this plan):**
- `Packages/CmuxChatRoomCore` — every value type and protocol seam from spec §4.3–§4.7, plus `ChatPromptMarker`.
- `Packages/CmuxChatRoom` — `RoomsCoordinator` (spec §4.6 correlation, needs-input hold, room CRUD forwarding, windowing) and `JSONChatHistoryStore` (spec §4.11), both fully tested against fakes/temp dirs.
- Both packages added to `.github/workflows/ci.yml` `PACKAGES` so `swift test` gates them.

**Explicitly out of scope (deferred to Plan 2, after Step 0):**
- Spec Step 0 audit (the empirical gates: G1 final-message capture, marker per-agent round-trip, `surface_id` threading, `addWorkspace`/`closeWorkspace` audits).
- `CmuxChatRoomUI` (real SwiftUI views need the app's snapshot-feeding decisions — Plan 2).
- Any change to `Sources/*`, `cmux.xcodeproj/project.pbxproj`, `WorkstreamEvent`, the hook bridge, `CMUXAgentLaunch`, persistence-snapshot fields, notifications, the sidebar renderer.
- App-target concrete implementations of the seams (these are what Plan 2 builds and wires).

**Why this split is honest:** spec §4.6's correlation rules, §4.3's data model, and §4.11's history store are fully specified and have no empirical unknowns. The marker *encoding* has a per-agent round-trip gate (spec §7), but the marker's **API and a concrete candidate encoding** are pinnable now; Step 0 only decides whether to swap the encoding bytes — the `inject`/`extract` contract and all coordinator code are unaffected. So this plan delivers real, regression-tested software that cannot be invalidated by Step 0.

**Marker encoding note (provisional, candidate per spec §4.6 "a single trailing line treated as inert metadata"):** this plan implements a concrete encoding and tests it exhaustively for round-trip/strip. Plan 2's Step 0 validates that Claude/Codex/Cursor each tolerate it in `toolInputJSON`; if an agent chokes, only the bytes inside `ChatPromptMarker` change — the function signatures and every test stay valid.

---

## File structure

```
Packages/
  CmuxChatRoomCore/
    Package.swift
    Sources/CmuxChatRoomCore/
      Ids/{AgentID,SurfaceID,ChatRoomID,ChatRequestID,MessageID,ExchangeID}.swift   # one ID per file
      AgentKind.swift
      AgentLifecycle.swift
      AgentMention.swift
      AgentIdentitySnapshot.swift
      PromptOrigin.swift
      ReplyOutcome.swift
      Reply.swift
      OutgoingPrompt.swift
      Exchange.swift
      ChatRoom.swift
      AgentTurnEvent.swift
      ChatPromptMarker.swift
      Seams/{RoomWorkspaceReading,RoomWorkspaceManaging,AgentRosterProviding,
             AgentLifecycleReading,AgentLifecycleChange,PromptInjecting,
             ChatNotifying,ChatHistoryStore}.swift                                  # one protocol per file
    Tests/CmuxChatRoomCoreTests/
      CodableRoundTripTests.swift
      ChatPromptMarkerTests.swift
  CmuxChatRoom/
    Package.swift
    Sources/CmuxChatRoom/
      RoomChannel.swift
      PendingInjection.swift
      HeldPrompt.swift
      TurnBinding.swift
      RoomsCoordinator.swift
      JSONChatHistoryStore.swift
    Tests/CmuxChatRoomTests/
      Fakes/{FakeRoomWorkspace,FakeRoster,FakeLifecycle,FakeInjector,FakeNotifier,
             InMemoryHistoryStore}.swift
      CorrelationTests.swift
      RoomScopingTests.swift
      NeedsInputHoldTests.swift
      ForwardQuoteTests.swift
      MoveAndCloseTests.swift
      WindowingAndRoomCRUDTests.swift
      JSONChatHistoryStoreTests.swift
```

**Responsibilities:** Core holds only `Sendable` values + protocols (no behavior beyond `ChatPromptMarker`). Domain holds the one stateful orchestrator (`RoomsCoordinator`) and the one repository (`JSONChatHistoryStore`); both take all collaborators via `init`. Fakes live only in the test target.

---

## Conventions for every task

- **Package.swift** for both packages uses this exact preamble shape (copied from `Packages/CmuxSocketControl/Package.swift`):
  ```swift
  // swift-tools-version: 6.0
  import PackageDescription
  ```
  with `platforms: [.macOS(.v14)]`, and on every `.target`/`.testTarget`:
  ```swift
  swiftSettings: [
      .swiftLanguageMode(.v6),
      .enableUpcomingFeature("ExistentialAny"),
      .enableUpcomingFeature("InternalImportsByDefault"),
  ]
  ```
  (`ExistentialAny` means every protocol existential must be written `any P` — the code below already does this.)
- **DocC** triple-slash on every `public` symbol (CLAUDE.md). Examples below include it; keep it.
- **Tests** are Swift Testing only. Run a single package's suite with:
  ```bash
  swift test --package-path Packages/<Name>
  ```
- **Commit** after each task with the message shown. Work on a fresh branch off `main`:
  ```bash
  git checkout main && git pull && git checkout -b feat/chat-room-foundation
  ```
  (Plan doc itself is already committed on `docs/chat-room-spec`; reference it from the feature branch.)

---

## Task 1: Scaffold `CmuxChatRoomCore` + ID types

**Files:**
- Create: `Packages/CmuxChatRoomCore/Package.swift`
- Create: `Packages/CmuxChatRoomCore/Sources/CmuxChatRoomCore/Ids/AgentID.swift` (+ `SurfaceID`, `ChatRoomID`, `ChatRequestID`, `MessageID`, `ExchangeID`)
- Create: `Packages/CmuxChatRoomCore/Tests/CmuxChatRoomCoreTests/CodableRoundTripTests.swift`
- Modify: `.github/workflows/ci.yml` (add `CmuxChatRoomCore` to `PACKAGES`)

- [ ] **Step 1: Write `Package.swift`**

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CmuxChatRoomCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "CmuxChatRoomCore", targets: ["CmuxChatRoomCore"]),
    ],
    targets: [
        .target(
            name: "CmuxChatRoomCore",
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("ExistentialAny"),
                .enableUpcomingFeature("InternalImportsByDefault"),
            ]
        ),
        .testTarget(
            name: "CmuxChatRoomCoreTests",
            dependencies: ["CmuxChatRoomCore"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("ExistentialAny"),
                .enableUpcomingFeature("InternalImportsByDefault"),
            ]
        ),
    ]
)
```

- [ ] **Step 2: Write the six ID types (one file each)**

`Ids/AgentID.swift` (the other five are identical with the name/doc changed):

```swift
import Foundation

/// Stable identifier for an agent tab/workspace. Equals the agent workspace's `id`.
///
/// Re-minted on session restore, so it is **never** used to key persisted history — use
/// ``ChatRoomID`` for durable room identity.
public struct AgentID: Hashable, Sendable, Codable {
    /// The underlying value.
    public let raw: UUID
    /// Creates an identifier wrapping `raw`.
    public init(raw: UUID) { self.raw = raw }
}
```

Create the remaining five with these doc summaries:
- `SurfaceID` — "Identifier for an agent's terminal surface (= cmux `panelId`)."
- `ChatRoomID` — "**Stable, persisted** identifier for a chat room. Distinct from any `Workspace.id` (which is re-minted on restore); room history and agents' `roomID` key off this."
- `ChatRequestID` — "Correlation token minted per injected chat prompt; embedded invisibly via ``ChatPromptMarker`` and recovered at `prompt-submit`."
- `MessageID` — "Identifier for a single reply message."
- `ExchangeID` — "Identifier for one outgoing prompt plus its replies."

Each has the same `public let raw: UUID` + `public init(raw: UUID)` shape.

- [ ] **Step 3: Write the round-trip test**

`CodableRoundTripTests.swift`:

```swift
import Foundation
import Testing
@testable import CmuxChatRoomCore

@Suite struct CodableRoundTripTests {
    @Test func agentIDEncodesAndDecodes() throws {
        let id = AgentID(raw: UUID())
        let data = try JSONEncoder().encode(id)
        let back = try JSONDecoder().decode(AgentID.self, from: data)
        #expect(back == id)
    }

    @Test func chatRoomIDIsValueEqual() {
        let u = UUID()
        #expect(ChatRoomID(raw: u) == ChatRoomID(raw: u))
        #expect(ChatRoomID(raw: u) != ChatRoomID(raw: UUID()))
    }
}
```

- [ ] **Step 4: Run the test (verify it passes)**

Run: `swift test --package-path Packages/CmuxChatRoomCore`
Expected: PASS (2 tests).

- [ ] **Step 5: Add the package to CI**

In `.github/workflows/ci.yml`, inside the `PACKAGES=(` array (currently ending `CMUXAgentLaunch`), add a line:

```bash
            CmuxChatRoomCore
```

- [ ] **Step 6: Commit**

```bash
git add Packages/CmuxChatRoomCore .github/workflows/ci.yml
git commit -m "feat(chat-room): scaffold CmuxChatRoomCore + ID types"
```

---

## Task 2: Enum/value primitives — `AgentKind`, `AgentLifecycle`, `AgentMention`

**Files:**
- Create: `Sources/CmuxChatRoomCore/AgentKind.swift`, `AgentLifecycle.swift`, `AgentMention.swift`
- Modify: `Tests/CmuxChatRoomCoreTests/CodableRoundTripTests.swift`

- [ ] **Step 1: Write the three types**

`AgentKind.swift`:

```swift
/// The coding-agent CLIs supported by the chat room in v1.
public enum AgentKind: String, Sendable, Codable, CaseIterable {
    /// Anthropic Claude Code (via the OMP wrapper).
    case claudeCode
    /// OpenAI Codex CLI.
    case codex
    /// Cursor agent CLI.
    case cursor
}
```

`AgentLifecycle.swift`:

```swift
/// Chat-room-space mirror of the app's agent lifecycle, exposed by ``AgentLifecycleReading``.
public enum AgentLifecycle: String, Sendable, Codable {
    /// State not yet known.
    case unknown
    /// The agent is actively working a turn.
    case running
    /// The agent is idle and ready for input.
    case idle
    /// The agent is blocked on a permission/confirmation prompt; raw injection is unsafe.
    case needsInput
}
```

`AgentMention.swift`:

```swift
import Foundation

/// A user's selection of a single agent to address (from `@`-autocomplete).
///
/// Stores a stable ``AgentID`` — never a display string — so renames/duplicate titles can't
/// misroute. `@all` is expressed by the caller as the full list of a room's mentions.
public struct AgentMention: Hashable, Sendable, Codable {
    /// The addressed agent.
    public let agentID: AgentID
    /// Creates a mention of `agentID`.
    public init(agentID: AgentID) { self.agentID = agentID }
}
```

- [ ] **Step 2: Add tests**

Append to `CodableRoundTripTests.swift` inside the suite:

```swift
    @Test func agentKindRawValuesAreStable() {
        #expect(AgentKind.claudeCode.rawValue == "claudeCode")
        #expect(AgentKind.codex.rawValue == "codex")
        #expect(AgentKind.cursor.rawValue == "cursor")
        #expect(AgentKind.allCases.count == 3)
    }

    @Test func agentLifecycleDecodesFromRaw() throws {
        let data = Data(#""needsInput""#.utf8)
        #expect(try JSONDecoder().decode(AgentLifecycle.self, from: data) == .needsInput)
    }
```

- [ ] **Step 3: Run tests**

Run: `swift test --package-path Packages/CmuxChatRoomCore`
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add Packages/CmuxChatRoomCore
git commit -m "feat(chat-room): add AgentKind/AgentLifecycle/AgentMention"
```

---

## Task 3: Message/exchange DTOs

**Files:**
- Create: `Sources/CmuxChatRoomCore/AgentIdentitySnapshot.swift`, `PromptOrigin.swift`, `ReplyOutcome.swift`, `Reply.swift`, `OutgoingPrompt.swift`, `Exchange.swift`, `ChatRoom.swift`
- Modify: `Tests/CmuxChatRoomCoreTests/CodableRoundTripTests.swift`

- [ ] **Step 1: Write the DTOs**

`AgentIdentitySnapshot.swift`:

```swift
/// An agent's display identity **frozen at send time**, stamped onto every prompt target and reply
/// so channel history never mutates when a tab is later renamed or switches branch.
public struct AgentIdentitySnapshot: Sendable, Codable, Hashable {
    /// The agent this snapshot describes.
    public let agentID: AgentID
    /// Editable tab title at send time.
    public let title: String
    /// Which CLI this agent is.
    public let kind: AgentKind
    /// `~`-abbreviated working directory at send time.
    public let cwdDisplay: String
    /// Git branch at send time, if known.
    public let branch: String?
    /// Creates a frozen identity snapshot.
    public init(agentID: AgentID, title: String, kind: AgentKind, cwdDisplay: String, branch: String?) {
        self.agentID = agentID; self.title = title; self.kind = kind
        self.cwdDisplay = cwdDisplay; self.branch = branch
    }
}
```

`PromptOrigin.swift`:

```swift
/// Why an outgoing prompt exists.
public enum PromptOrigin: Sendable, Codable, Equatable {
    /// The user `@`-mentioned the target(s) directly.
    case userMention
    /// The prompt forwards an earlier reply (the "steering wheel").
    case forward(sourceMessageID: MessageID)
}
```

`ReplyOutcome.swift`:

```swift
/// The status of one target within an ``Exchange``.
public enum ReplyOutcome: Sendable, Codable, Equatable {
    /// Injected (or held) and awaiting the agent's final message.
    case pending
    /// The agent posted its final message.
    case replied(Reply)
    /// The agent's tab closed before replying.
    case tabClosed
    /// The prompt could not be dispatched (target gone, or never left needs-input).
    case failedToDispatch
}
```

`Reply.swift`:

```swift
import Foundation

/// One agent's final message returned to a channel.
public struct Reply: Sendable, Codable, Equatable {
    /// Stable id of this message.
    public let id: MessageID
    /// The exchange this reply belongs to.
    public let exchangeID: ExchangeID
    /// Frozen identity of the replying agent.
    public let from: AgentIdentitySnapshot
    /// The verbatim `last_assistant_message` (markdown).
    public let markdownBody: String
    /// When the reply was received.
    public let receivedAt: Date
    /// Creates a reply.
    public init(id: MessageID, exchangeID: ExchangeID, from: AgentIdentitySnapshot,
                markdownBody: String, receivedAt: Date) {
        self.id = id; self.exchangeID = exchangeID; self.from = from
        self.markdownBody = markdownBody; self.receivedAt = receivedAt
    }
}
```

`OutgoingPrompt.swift`:

```swift
import Foundation

/// One outgoing prompt posted to a room and dispatched to its targets.
public struct OutgoingPrompt: Sendable, Codable {
    /// The exchange this prompt opens.
    public let exchangeID: ExchangeID
    /// The room this exchange lives in.
    public let roomID: ChatRoomID
    /// Why this prompt exists.
    public let origin: PromptOrigin
    /// The user-visible body (clean — never contains the correlation marker).
    /// For a forward this is `"\"<quoted>\"\n<note>"`.
    public let bodyText: String
    /// Targets resolved from **this room's** agents at send time (frozen snapshots).
    public let targets: [AgentIdentitySnapshot]
    /// When sent.
    public let sentAt: Date
    /// Creates an outgoing prompt.
    public init(exchangeID: ExchangeID, roomID: ChatRoomID, origin: PromptOrigin,
                bodyText: String, targets: [AgentIdentitySnapshot], sentAt: Date) {
        self.exchangeID = exchangeID; self.roomID = roomID; self.origin = origin
        self.bodyText = bodyText; self.targets = targets; self.sentAt = sentAt
    }
}
```

`Exchange.swift`:

```swift
/// One outgoing prompt plus the per-target outcomes (one level deep — no nested threads).
public struct Exchange: Sendable, Codable, Identifiable {
    /// Stable id (== `prompt.exchangeID`).
    public var id: ExchangeID { prompt.exchangeID }
    /// The prompt that opened this exchange.
    public let prompt: OutgoingPrompt
    /// Per-target outcome, keyed by ``AgentID``.
    public var outcomes: [AgentID: ReplyOutcome]
    /// Creates an exchange.
    public init(prompt: OutgoingPrompt, outcomes: [AgentID: ReplyOutcome]) {
        self.prompt = prompt; self.outcomes = outcomes
    }
}
```

`ChatRoom.swift`:

```swift
/// A named channel, backed by a `.chatRoom` workspace whose stable persisted `chatRoomID` equals
/// ``id`` (NOT the re-minted `Workspace.id`). Membership is the set of agents whose `roomID == id`.
public struct ChatRoom: Sendable, Codable, Identifiable, Equatable {
    /// Stable room identity.
    public let id: ChatRoomID
    /// Renameable display name.
    public var name: String
    /// Creates a room.
    public init(id: ChatRoomID, name: String) { self.id = id; self.name = name }
}
```

- [ ] **Step 2: Add a round-trip test for a fully-populated `Exchange`**

Append to `CodableRoundTripTests.swift`:

```swift
    @Test func exchangeWithRepliedOutcomeRoundTrips() throws {
        let agent = AgentID(raw: UUID())
        let snap = AgentIdentitySnapshot(agentID: agent, title: "claude code 1",
                                         kind: .claudeCode, cwdDisplay: "~/work/cmux", branch: "main")
        let ex = ExchangeID(raw: UUID())
        let prompt = OutgoingPrompt(exchangeID: ex, roomID: ChatRoomID(raw: UUID()),
                                    origin: .userMention, bodyText: "review this",
                                    targets: [snap], sentAt: Date(timeIntervalSince1970: 100))
        let reply = Reply(id: MessageID(raw: UUID()), exchangeID: ex, from: snap,
                          markdownBody: "Done.\n\n- fixed x", receivedAt: Date(timeIntervalSince1970: 200))
        let exchange = Exchange(prompt: prompt, outcomes: [agent: .replied(reply)])

        let data = try JSONEncoder().encode(exchange)
        let back = try JSONDecoder().decode(Exchange.self, from: data)
        #expect(back.id == ex)
        #expect(back.outcomes[agent] == .replied(reply))
        #expect(back.prompt.targets.first?.title == "claude code 1")
    }
```

- [ ] **Step 3: Run tests**

Run: `swift test --package-path Packages/CmuxChatRoomCore`
Expected: PASS.

> Note: `[AgentID: ReplyOutcome]` is `Codable` because `AgentID` is `Codable` but **not** `String`-keyed, so Foundation encodes it as an array of alternating key/value entries. The round-trip test above proves it decodes correctly — do not switch to `[String: …]`.

- [ ] **Step 4: Commit**

```bash
git add Packages/CmuxChatRoomCore
git commit -m "feat(chat-room): add message/exchange DTOs"
```

---

## Task 4: `AgentTurnEvent`

**Files:**
- Create: `Sources/CmuxChatRoomCore/AgentTurnEvent.swift`

- [ ] **Step 1: Write the event**

```swift
/// Normalized turn events the coordinator consumes (sourced from the existing hook pipeline by the
/// app-side bridge in Plan 2). Carries ``SurfaceID`` so per-surface FIFO works when a workspace
/// holds multiple agent panels.
public enum AgentTurnEvent: Sendable {
    /// A prompt was submitted on `surface`. `rawPromptText` is the **un-normalized** prompt
    /// (from `toolInputJSON`, not the whitespace-collapsed `submittedPromptMessage`) so the embedded
    /// ``ChatPromptMarker`` survives and is extractable.
    case promptSubmitted(SurfaceID, rawPromptText: String)
    /// A turn completed on `surface`, carrying the agent's final message (`last_assistant_message`).
    case turnCompleted(SurfaceID, finalMessage: String)
}
```

- [ ] **Step 2: Compile**

Run: `swift build --package-path Packages/CmuxChatRoomCore`
Expected: builds (no test needed for a pure enum; behavior is tested via the coordinator in Task 9+).

- [ ] **Step 3: Commit**

```bash
git add Packages/CmuxChatRoomCore
git commit -m "feat(chat-room): add AgentTurnEvent"
```

---

## Task 5: `ChatPromptMarker` (the correlation token) — TDD

**Files:**
- Create: `Sources/CmuxChatRoomCore/ChatPromptMarker.swift`
- Create: `Tests/CmuxChatRoomCoreTests/ChatPromptMarkerTests.swift`

> The marker is the **only** correlation mechanism (spec §4.6). Encoding is a single trailing
> metadata line that survives verbatim in `toolInputJSON`, strips cleanly before any display, and
> reads as inert to an LLM. Concrete candidate (Plan-2 Step 0 may swap the bytes; the API is fixed):
> `\n\n<!-- cmux-chat-request:<UUID> -->`

- [ ] **Step 1: Write the failing tests first**

`ChatPromptMarkerTests.swift`:

```swift
import Foundation
import Testing
@testable import CmuxChatRoomCore

@Suite struct ChatPromptMarkerTests {
    @Test func injectThenExtractRecoversIDAndCleanBody() {
        let id = ChatRequestID(raw: UUID())
        let body = "Please review the auth refactor."
        let injected = ChatPromptMarker.inject(id, into: body)
        let (recovered, cleaned) = ChatPromptMarker.extract(from: injected)
        #expect(recovered == id)
        #expect(cleaned == body)
        #expect(!injected.contains(body) == false)        // body still present in injected text
    }

    @Test func multilineBodySurvivesRoundTrip() {
        let id = ChatRequestID(raw: UUID())
        let body = "Line one\n\nLine two with  weird   spacing\n\tindented\nend"
        let injected = ChatPromptMarker.inject(id, into: body)
        let (recovered, cleaned) = ChatPromptMarker.extract(from: injected)
        #expect(recovered == id)
        #expect(cleaned == body)                          // whitespace preserved exactly
    }

    @Test func forwardShapedBodyRoundTrips() {
        let id = ChatRequestID(raw: UUID())
        let body = "\"original reply text\nwith newline\"\nmy appended note"
        let injected = ChatPromptMarker.inject(id, into: body)
        let (recovered, cleaned) = ChatPromptMarker.extract(from: injected)
        #expect(recovered == id)
        #expect(cleaned == body)
    }

    @Test func bodyWithNoMarkerExtractsNil() {
        let body = "a direct prompt the user typed in the tab"
        let (recovered, cleaned) = ChatPromptMarker.extract(from: body)
        #expect(recovered == nil)
        #expect(cleaned == body)
    }

    @Test func bodyThatMerelyMentionsTheWordIsNotAFalsePositive() {
        let body = "talk about cmux-chat-request handling in general"
        let (recovered, _) = ChatPromptMarker.extract(from: body)
        #expect(recovered == nil)
    }

    @Test func injectedMarkerIsNotVisibleInBodyText() {
        // The marker line must be separable so the channel never shows it.
        let id = ChatRequestID(raw: UUID())
        let injected = ChatPromptMarker.inject(id, into: "hello")
        let (_, cleaned) = ChatPromptMarker.extract(from: injected)
        #expect(!cleaned.contains("cmux-chat-request"))
    }
}
```

- [ ] **Step 2: Run to confirm failure**

Run: `swift test --package-path Packages/CmuxChatRoomCore --filter ChatPromptMarkerTests`
Expected: FAIL — `ChatPromptMarker` does not exist.

- [ ] **Step 3: Implement `ChatPromptMarker`**

```swift
import Foundation

/// Embeds and recovers the hidden ``ChatRequestID`` correlation token in an injected prompt.
///
/// The token is appended as a single trailing metadata line that survives verbatim in the agent's
/// `toolInputJSON`, is recovered at `prompt-submit`, and is stripped before any channel display or
/// forward. It is the sole correlation mechanism — there is no exact-text or FIFO-only fallback.
///
/// ```swift
/// let injected = ChatPromptMarker.inject(requestID, into: "review this")
/// let (id, clean) = ChatPromptMarker.extract(from: injected) // id == requestID, clean == "review this"
/// ```
public enum ChatPromptMarker {
    private static let prefix = "<!-- cmux-chat-request:"
    private static let suffix = " -->"

    /// Appends a non-displayed token encoding `id` after `body`.
    public static func inject(_ id: ChatRequestID, into body: String) -> String {
        "\(body)\n\n\(prefix)\(id.raw.uuidString)\(suffix)"
    }

    /// Recovers the ``ChatRequestID`` (if present) and returns the body with the marker line removed.
    ///
    /// Only a marker that is the **last** non-empty line and parses to a valid UUID matches, so a
    /// body that merely mentions the token text is not a false positive.
    public static func extract(from rawPrompt: String) -> (ChatRequestID?, cleaned: String) {
        // Find the last occurrence of a complete marker.
        guard let prefixRange = rawPrompt.range(of: prefix, options: .backwards),
              let suffixRange = rawPrompt.range(of: suffix, range: prefixRange.upperBound..<rawPrompt.endIndex)
        else {
            return (nil, rawPrompt)
        }
        let uuidString = String(rawPrompt[prefixRange.upperBound..<suffixRange.lowerBound])
        guard let uuid = UUID(uuidString: uuidString) else {
            return (nil, rawPrompt)
        }
        // Strip from the start of the prefix to the end of the suffix, then trim the trailing
        // separator newlines we added in `inject` (and any incidental trailing whitespace).
        var cleaned = String(rawPrompt[rawPrompt.startIndex..<prefixRange.lowerBound])
        while cleaned.hasSuffix("\n") || cleaned.hasSuffix(" ") || cleaned.hasSuffix("\t") {
            cleaned.removeLast()
        }
        return (ChatRequestID(raw: uuid), cleaned)
    }
}
```

> **Caveat for the implementer:** the `multilineBodySurvivesRoundTrip` test ends the body with `"end"` (no trailing whitespace), so the trailing-trim loop is safe. If a real body intentionally ends in newlines, this encoding cannot perfectly preserve them — that's acceptable for v1 (prompts are trimmed by the agents anyway) and is documented here so Plan-2 Step 0 keeps it in mind when finalizing the encoding. Do not add trailing-whitespace preservation logic; it is YAGNI for v1.

- [ ] **Step 4: Run to confirm pass**

Run: `swift test --package-path Packages/CmuxChatRoomCore --filter ChatPromptMarkerTests`
Expected: PASS (6 tests).

- [ ] **Step 5: Commit**

```bash
git add Packages/CmuxChatRoomCore
git commit -m "feat(chat-room): add ChatPromptMarker with round-trip tests"
```

---

## Task 6: Protocol seams

**Files:**
- Create: `Sources/CmuxChatRoomCore/Seams/RoomWorkspaceReading.swift`, `RoomWorkspaceManaging.swift`, `AgentRosterProviding.swift`, `AgentLifecycleReading.swift`, `AgentLifecycleChange.swift`, `PromptInjecting.swift`, `ChatNotifying.swift`, `ChatHistoryStore.swift`

> These are the only surface between the coordinator and the app. The coordinator depends on
> `any P`; Plan 2 implements concretes over `TabManager`/`TerminalController`. **Key design choice
> (refines spec §4.6's internal-struct sketch):** `PromptInjecting.inject` takes an `AgentID`, not a
> `SurfaceID`. The app owns the `AgentID ↔ (panelId, agentName/surface)` mapping (spec §4.5), and the
> coordinator learns the `SurfaceID` purely from `AgentTurnEvent`s — it never needs to resolve a
> surface itself. This keeps the coordinator in `AgentID` space for sends/holds and `SurfaceID` space
> only for the per-surface FIFO queue.

- [ ] **Step 1: Write the seams**

`RoomWorkspaceReading.swift`:

```swift
import Foundation

/// Read seam: the rooms and the active room, **derived** from the live `.chatRoom` workspaces.
///
/// The coordinator owns no `rooms` array or `activeRoom` flag — it reads them here so there is a
/// single source of truth (spec §4.6).
public protocol RoomWorkspaceReading: Sendable {
    /// All rooms, from live `.chatRoom` workspaces (each `id` == its persisted `chatRoomID`).
    func rooms() async -> [ChatRoom]
    /// The active room: selected `.chatRoom` → its `chatRoomID`; selected `.agent` → that agent's
    /// `roomID`; nothing selected → `nil`.
    func activeRoomID() async -> ChatRoomID?
    /// Emits when the room list or selection changes.
    var changes: AsyncStream<Void> { get }
}
```

`RoomWorkspaceManaging.swift`:

```swift
/// Mutation seam: room CRUD + agent membership, performed on app-owned workspaces (spec §4.6).
public protocol RoomWorkspaceManaging: Sendable {
    /// Creates a `.chatRoom` workspace with a fresh stable `chatRoomID`; returns it.
    func createRoom(name: String) async -> ChatRoomID
    /// Renames the room's backing workspace.
    func renameRoom(_ id: ChatRoomID, to name: String) async
    /// Runs the close-room flow (spec §4.10). Returns `false` if refused (keep ≥1 room).
    func requestCloseRoom(_ id: ChatRoomID) async -> Bool
    /// Moves an agent to another room by rewriting its `roomID`.
    func setRoom(of agent: AgentID, to room: ChatRoomID) async
}
```

`AgentRosterProviding.swift`:

```swift
import Foundation

/// Read seam: the mentionable agents in a room (live `.agent` workspaces with `roomID == room` that
/// are chat-supported), as frozen identity snapshots. No parallel registry — `roomID` membership is
/// the source of truth (spec §4.7).
public protocol AgentRosterProviding: Sendable {
    /// The room's mentionable agents at call time.
    func current(inRoom room: ChatRoomID) async -> [AgentIdentitySnapshot]
    /// Emits when any room's roster changes.
    var changes: AsyncStream<Void> { get }
}
```

`AgentLifecycleChange.swift`:

```swift
/// A single lifecycle transition, yielded by ``AgentLifecycleReading/changes``.
public struct AgentLifecycleChange: Sendable, Equatable {
    /// The agent whose state changed.
    public let agent: AgentID
    /// The new state.
    public let state: AgentLifecycle
    /// Creates a change.
    public init(agent: AgentID, state: AgentLifecycle) { self.agent = agent; self.state = state }
}
```

`AgentLifecycleReading.swift`:

```swift
import Foundation

/// Read seam over the existing `Workspace.agentLifecycleStatesByPanelId` (spec §4.5). The coordinator
/// reads needs-input state here; it keeps no lifecycle dictionary of its own.
public protocol AgentLifecycleReading: Sendable {
    /// Current state of every known agent.
    func current() async -> [AgentID: AgentLifecycle]
    /// Current state of one agent (`.unknown` if absent).
    func state(of agent: AgentID) async -> AgentLifecycle
    /// Emits each lifecycle transition.
    var changes: AsyncStream<AgentLifecycleChange> { get }
}
```

`PromptInjecting.swift`:

```swift
/// Write seam: inject raw text into an agent's terminal surface (wraps `surface.send_text` + submit,
/// non-focus-stealing). Returns `false` if the agent could not be reached (→ `.failedToDispatch`).
public protocol PromptInjecting: Sendable {
    /// Injects `text` into `agent`'s surface and submits it.
    func inject(_ text: String, into agent: AgentID) async -> Bool
}
```

`ChatNotifying.swift`:

```swift
/// Write seam: badge a room for a completed chat-origin turn when that room isn't active (spec §3.12).
/// Needs-input notification targets the agent tab and is lifecycle-driven in the app, not here.
public protocol ChatNotifying: Sendable {
    /// Badge `room` for a new completion.
    func notifyRoomCompletion(_ room: ChatRoomID) async
}
```

`ChatHistoryStore.swift`:

```swift
/// Repository seam: persist exchanges per room, keyed by the stable ``ChatRoomID`` (spec §4.11).
/// Supports paged reads for "Load earlier". Concrete `JSONChatHistoryStore` lives in `CmuxChatRoom`.
public protocol ChatHistoryStore: Sendable {
    /// Append a new exchange to `room`.
    func append(_ exchange: Exchange, in room: ChatRoomID) async
    /// Replace an existing exchange (same `exchangeID`) in `room`.
    func update(_ exchange: Exchange, in room: ChatRoomID) async
    /// The most recent `limit` exchanges in `room`, oldest-first.
    func recent(in room: ChatRoomID, limit: Int) async -> [Exchange]
    /// Up to `limit` exchanges immediately older than `before`, oldest-first.
    func page(in room: ChatRoomID, before: ExchangeID, limit: Int) async -> [Exchange]
}
```

- [ ] **Step 2: Compile**

Run: `swift build --package-path Packages/CmuxChatRoomCore`
Expected: builds.

- [ ] **Step 3: Commit**

```bash
git add Packages/CmuxChatRoomCore
git commit -m "feat(chat-room): add protocol seams"
```

---

## Task 7: Scaffold `CmuxChatRoom` (Domain) + internal correlation types

**Files:**
- Create: `Packages/CmuxChatRoom/Package.swift`
- Create: `Sources/CmuxChatRoom/RoomChannel.swift`, `PendingInjection.swift`, `HeldPrompt.swift`, `TurnBinding.swift`
- Modify: `.github/workflows/ci.yml` (add `CmuxChatRoom`)

- [ ] **Step 1: Write `Package.swift`**

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CmuxChatRoom",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "CmuxChatRoom", targets: ["CmuxChatRoom"]),
    ],
    dependencies: [
        .package(path: "../CmuxChatRoomCore"),
    ],
    targets: [
        .target(
            name: "CmuxChatRoom",
            dependencies: [.product(name: "CmuxChatRoomCore", package: "CmuxChatRoomCore")],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("ExistentialAny"),
                .enableUpcomingFeature("InternalImportsByDefault"),
            ]
        ),
        .testTarget(
            name: "CmuxChatRoomTests",
            dependencies: [
                "CmuxChatRoom",
                .product(name: "CmuxChatRoomCore", package: "CmuxChatRoomCore"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("ExistentialAny"),
                .enableUpcomingFeature("InternalImportsByDefault"),
            ]
        ),
    ]
)
```

- [ ] **Step 2: Write the internal correlation types**

`RoomChannel.swift`:

```swift
internal import CmuxChatRoomCore

/// One room's in-memory view state: a bounded recent window of exchanges (full set is in the store).
struct RoomChannel {
    /// The room.
    var roomID: ChatRoomID
    /// Windowed exchanges, oldest-first.
    var exchanges: [Exchange]
    /// True once the oldest loaded exchange is the oldest in the store (no more "Load earlier").
    var reachedStart: Bool
}
```

`PendingInjection.swift`:

```swift
internal import CmuxChatRoomCore

/// A chat prompt that has been injected and is awaiting `prompt-submit`/`stop`.
struct PendingInjection {
    let requestID: ChatRequestID
    let exchangeID: ExchangeID
    let roomID: ChatRoomID
    let agent: AgentID
}
```

`HeldPrompt.swift`:

```swift
internal import CmuxChatRoomCore

/// A chat prompt held back because its target was `needsInput` at send time (spec §3.11).
struct HeldPrompt {
    let requestID: ChatRequestID
    let exchangeID: ExchangeID
    let roomID: ChatRoomID
    let agent: AgentID
    let bodyWithMarker: String
}
```

`TurnBinding.swift`:

```swift
internal import CmuxChatRoomCore

/// One entry in a surface's FIFO turn queue. `stop` events carry no marker, so the queue (filled at
/// `prompt-submit`, popped at `stop`) is what pairs a completion with its originating exchange.
enum TurnBinding {
    /// A chat-origin turn bound via the marker.
    case chatOrigin(request: ChatRequestID, exchange: ExchangeID, room: ChatRoomID, agent: AgentID)
    /// A direct (user-typed-in-tab) turn — its completion is dropped.
    case direct
}
```

- [ ] **Step 3: Build**

Run: `swift build --package-path Packages/CmuxChatRoom`
Expected: builds.

- [ ] **Step 4: Add to CI**

In `.github/workflows/ci.yml` `PACKAGES`, add below `CmuxChatRoomCore`:

```bash
            CmuxChatRoom
```

- [ ] **Step 5: Commit**

```bash
git add Packages/CmuxChatRoom .github/workflows/ci.yml
git commit -m "feat(chat-room): scaffold CmuxChatRoom + correlation types"
```

---

## Task 8: Test fakes for every seam

**Files:**
- Create: `Tests/CmuxChatRoomTests/Fakes/FakeRoomWorkspace.swift`, `FakeRoster.swift`, `FakeLifecycle.swift`, `FakeInjector.swift`, `FakeNotifier.swift`, `InMemoryHistoryStore.swift`

> Fakes are `actor`s (thread-safe, no locks) or `@MainActor` value-recorders. They expose record
> arrays so tests can assert calls, and `AsyncStream` continuations so tests can drive change events.

- [ ] **Step 1: Write the fakes**

`InMemoryHistoryStore.swift`:

```swift
import Foundation
import CmuxChatRoomCore

/// In-memory ``ChatHistoryStore`` for tests; ordered per room, oldest-first.
actor InMemoryHistoryStore: ChatHistoryStore {
    private var byRoom: [ChatRoomID: [Exchange]] = [:]

    func append(_ exchange: Exchange, in room: ChatRoomID) async {
        byRoom[room, default: []].append(exchange)
    }
    func update(_ exchange: Exchange, in room: ChatRoomID) async {
        guard var list = byRoom[room], let i = list.firstIndex(where: { $0.id == exchange.id }) else { return }
        list[i] = exchange; byRoom[room] = list
    }
    func recent(in room: ChatRoomID, limit: Int) async -> [Exchange] {
        let list = byRoom[room] ?? []
        return Array(list.suffix(limit))
    }
    func page(in room: ChatRoomID, before: ExchangeID, limit: Int) async -> [Exchange] {
        let list = byRoom[room] ?? []
        guard let i = list.firstIndex(where: { $0.id == before }) else { return [] }
        return Array(list[..<i].suffix(limit))
    }
}
```

`FakeRoomWorkspace.swift`:

```swift
import Foundation
import CmuxChatRoomCore

/// Fake implementing both room seams. Tests set `roomsValue`/`activeValue` and read the call records.
actor FakeRoomWorkspace: RoomWorkspaceReading, RoomWorkspaceManaging {
    var roomsValue: [ChatRoom] = []
    var activeValue: ChatRoomID?
    private(set) var created: [String] = []
    private(set) var renamed: [(ChatRoomID, String)] = []
    private(set) var closeRequested: [ChatRoomID] = []
    private(set) var moved: [(AgentID, ChatRoomID)] = []
    var closeResult = true

    // NOTE: tuple-pattern stored properties (`let (a, b) = …`) do not compile as actor stored
    // properties — declare them separately and assign the tuple in `init`.
    private let stream: AsyncStream<Void>
    private let cont: AsyncStream<Void>.Continuation
    init() { (stream, cont) = AsyncStream<Void>.makeStream() }
    nonisolated var changes: AsyncStream<Void> { stream }
    func emitChange() { cont.yield(()) }

    func setRooms(_ r: [ChatRoom]) { roomsValue = r }
    func setActive(_ id: ChatRoomID?) { activeValue = id }

    func rooms() async -> [ChatRoom] { roomsValue }
    func activeRoomID() async -> ChatRoomID? { activeValue }

    func createRoom(name: String) async -> ChatRoomID {
        created.append(name)
        let id = ChatRoomID(raw: UUID())
        roomsValue.append(ChatRoom(id: id, name: name))
        return id
    }
    func renameRoom(_ id: ChatRoomID, to name: String) async { renamed.append((id, name)) }
    func requestCloseRoom(_ id: ChatRoomID) async -> Bool { closeRequested.append(id); return closeResult }
    func setRoom(of agent: AgentID, to room: ChatRoomID) async { moved.append((agent, room)) }
}
```

`FakeRoster.swift`:

```swift
import Foundation
import CmuxChatRoomCore

/// Fake roster. Tests set `byRoom` to control who is mentionable per room.
actor FakeRoster: AgentRosterProviding {
    var byRoom: [ChatRoomID: [AgentIdentitySnapshot]] = [:]
    private let stream: AsyncStream<Void>
    private let cont: AsyncStream<Void>.Continuation
    init() { (stream, cont) = AsyncStream<Void>.makeStream() }
    nonisolated var changes: AsyncStream<Void> { stream }

    func set(_ snaps: [AgentIdentitySnapshot], inRoom room: ChatRoomID) { byRoom[room] = snaps }
    func current(inRoom room: ChatRoomID) async -> [AgentIdentitySnapshot] { byRoom[room] ?? [] }
}
```

`FakeLifecycle.swift`:

```swift
import Foundation
import CmuxChatRoomCore

/// Fake lifecycle store. Tests set states and call `emit` to drive transitions.
actor FakeLifecycle: AgentLifecycleReading {
    var states: [AgentID: AgentLifecycle] = [:]
    private let stream: AsyncStream<AgentLifecycleChange>
    private let cont: AsyncStream<AgentLifecycleChange>.Continuation
    init() { (stream, cont) = AsyncStream<AgentLifecycleChange>.makeStream() }
    nonisolated var changes: AsyncStream<AgentLifecycleChange> { stream }

    func set(_ s: AgentLifecycle, for agent: AgentID) { states[agent] = s }
    func emit(_ s: AgentLifecycle, for agent: AgentID) { states[agent] = s; cont.yield(.init(agent: agent, state: s)) }
    func current() async -> [AgentID: AgentLifecycle] { states }
    func state(of agent: AgentID) async -> AgentLifecycle { states[agent] ?? .unknown }
}
```

`FakeInjector.swift`:

```swift
import Foundation
import CmuxChatRoomCore

/// Fake injector recording every injected `(text, agent)`; tests can force a dispatch failure.
actor FakeInjector: PromptInjecting {
    private(set) var injected: [(text: String, agent: AgentID)] = []
    var failFor: Set<AgentID> = []
    func failNext(for agent: AgentID) { failFor.insert(agent) }
    func inject(_ text: String, into agent: AgentID) async -> Bool {
        injected.append((text, agent))
        if failFor.contains(agent) { failFor.remove(agent); return false }
        return true
    }
    func lastText() -> String? { injected.last?.text }
}
```

`FakeNotifier.swift`:

```swift
import Foundation
import CmuxChatRoomCore

/// Fake notifier recording which rooms were badged.
actor FakeNotifier: ChatNotifying {
    private(set) var badged: [ChatRoomID] = []
    func notifyRoomCompletion(_ room: ChatRoomID) async { badged.append(room) }
}
```

- [ ] **Step 2: Build the test target (fakes must compile against the seams)**

Run: `swift build --package-path Packages/CmuxChatRoom --build-tests`
Expected: builds. (No tests run yet.)

- [ ] **Step 3: Commit**

```bash
git add Packages/CmuxChatRoom
git commit -m "test(chat-room): add seam fakes"
```

---

## Task 9: `RoomsCoordinator` — skeleton + `send` + first correlation test (TDD)

**Files:**
- Create: `Sources/CmuxChatRoom/RoomsCoordinator.swift`
- Create: `Tests/CmuxChatRoomTests/CorrelationTests.swift`

> This task builds the full coordinator in one file (it's one cohesive type), then the remaining
> test tasks (10–16) add **only test files** that exercise already-written branches. The complete
> implementation is given here so later tasks never say "similar to Task 9".

- [ ] **Step 1: Write the complete `RoomsCoordinator`**

```swift
import Foundation
public import CmuxChatRoomCore

/// `@MainActor @Observable` orchestrator for the chat room. Owns channel/correlation/history state
/// only; rooms, roster, and lifecycle are **derived** through read seams (spec §4.6).
///
/// Correlation is marker-based and room-scoped: a reply routes back to a channel **only** if its
/// prompt carried a ``ChatPromptMarker`` minted by ``send(in:_:to:origin:)``. Direct (user-typed)
/// turns carry no marker and are dropped.
@MainActor @Observable
public final class RoomsCoordinator {
    /// Per-room windowed channel state.
    public private(set) var channels: [ChatRoomID: [Exchange]] = [:]

    private var window: [ChatRoomID: RoomChannel] = [:]
    private var turnQueueBySurface: [SurfaceID: [TurnBinding]] = [:]
    private var pendingByRequest: [ChatRequestID: PendingInjection] = [:]
    private var heldForNeedsInput: [AgentID: [HeldPrompt]] = [:]

    private let roomsReading: any RoomWorkspaceReading
    private let roomsManaging: any RoomWorkspaceManaging
    private let roster: any AgentRosterProviding
    private let lifecycle: any AgentLifecycleReading
    private let injector: any PromptInjecting
    private let notifier: any ChatNotifying
    private let history: any ChatHistoryStore
    private let now: @Sendable () -> Date
    private let makeRequestID: @Sendable () -> ChatRequestID
    private let makeExchangeID: @Sendable () -> ExchangeID
    private let makeMessageID: @Sendable () -> MessageID
    /// Recent-window size for ``loadEarlier(in:)`` paging.
    public let windowSize: Int

    /// Creates a coordinator. All collaborators are injected (constructor DI). The `make*`/`now`
    /// closures are injectable so tests are deterministic.
    public init(
        roomsReading: any RoomWorkspaceReading,
        roomsManaging: any RoomWorkspaceManaging,
        roster: any AgentRosterProviding,
        lifecycle: any AgentLifecycleReading,
        injector: any PromptInjecting,
        notifier: any ChatNotifying,
        history: any ChatHistoryStore,
        windowSize: Int = 50,
        now: @escaping @Sendable () -> Date = { Date() },
        makeRequestID: @escaping @Sendable () -> ChatRequestID = { ChatRequestID(raw: UUID()) },
        makeExchangeID: @escaping @Sendable () -> ExchangeID = { ExchangeID(raw: UUID()) },
        makeMessageID: @escaping @Sendable () -> MessageID = { MessageID(raw: UUID()) }
    ) {
        self.roomsReading = roomsReading; self.roomsManaging = roomsManaging
        self.roster = roster; self.lifecycle = lifecycle; self.injector = injector
        self.notifier = notifier; self.history = history; self.windowSize = windowSize
        self.now = now; self.makeRequestID = makeRequestID
        self.makeExchangeID = makeExchangeID; self.makeMessageID = makeMessageID
    }

    // MARK: Room CRUD (forwarded — rooms are derived, not owned)

    /// Forwards to the managing seam; returns the new room's stable id.
    @discardableResult
    public func createRoom(name: String) async -> ChatRoomID { await roomsManaging.createRoom(name: name) }
    /// Forwards a rename.
    public func renameRoom(_ id: ChatRoomID, to name: String) async { await roomsManaging.renameRoom(id, to: name) }
    /// Forwards the close-room flow (keep-≥1 enforced by the app seam).
    public func closeRoom(_ id: ChatRoomID) async { _ = await roomsManaging.requestCloseRoom(id) }
    /// Forwards an agent move; in-flight turns stay bound to their originating room.
    public func move(_ agent: AgentID, to room: ChatRoomID) async { await roomsManaging.setRoom(of: agent, to: room) }
    /// The active room derived from selection.
    public func activeRoomID() async -> ChatRoomID? { await roomsReading.activeRoomID() }

    // MARK: Sending

    /// Sends `body` to `mentions` (resolved against `room`'s agents only) as one exchange.
    public func send(in room: ChatRoomID, _ body: String,
                     to mentions: [AgentMention], origin: PromptOrigin) async {
        let roomAgents = await roster.current(inRoom: room)
        let byID = Dictionary(uniqueKeysWithValues: roomAgents.map { ($0.agentID, $0) })
        // Resolve at send time, scoped to the room; unknown mentions are dropped.
        let targets = mentions.compactMap { byID[$0.agentID] }
        guard !targets.isEmpty else { return }

        let exchangeID = makeExchangeID()
        let prompt = OutgoingPrompt(exchangeID: exchangeID, roomID: room, origin: origin,
                                    bodyText: body, targets: targets, sentAt: now())
        var outcomes: [AgentID: ReplyOutcome] = [:]
        for t in targets { outcomes[t.agentID] = .pending }
        let exchange = Exchange(prompt: prompt, outcomes: outcomes)

        await history.append(exchange, in: room)
        appendToWindow(exchange, in: room)

        for t in targets {
            let requestID = makeRequestID()
            let bodyWithMarker = ChatPromptMarker.inject(requestID, into: body)
            let state = await lifecycle.state(of: t.agentID)
            if state == .needsInput {
                heldForNeedsInput[t.agentID, default: []].append(
                    HeldPrompt(requestID: requestID, exchangeID: exchangeID, roomID: room,
                               agent: t.agentID, bodyWithMarker: bodyWithMarker))
            } else {
                pendingByRequest[requestID] = PendingInjection(
                    requestID: requestID, exchangeID: exchangeID, roomID: room, agent: t.agentID)
                let ok = await injector.inject(bodyWithMarker, into: t.agentID)
                if !ok {
                    pendingByRequest[requestID] = nil
                    setOutcome(.failedToDispatch, agent: t.agentID, exchange: exchangeID, room: room)
                }
            }
        }
    }

    /// Forwards an earlier reply (quoted + note) to new targets as a fresh exchange.
    public func forward(_ source: MessageID, quoted: String, note: String,
                        to mentions: [AgentMention], in room: ChatRoomID) async {
        let body = "\"\(quoted)\"\n\(note)"
        await send(in: room, body, to: mentions, origin: .forward(sourceMessageID: source))
    }

    // MARK: Turn events

    /// Consumes a normalized turn event from the app bridge.
    public func handle(_ event: AgentTurnEvent) {
        switch event {
        case let .promptSubmitted(surface, rawPromptText):
            let (id, _) = ChatPromptMarker.extract(from: rawPromptText)
            if let id, let pending = pendingByRequest.removeValue(forKey: id) {
                turnQueueBySurface[surface, default: []].append(
                    .chatOrigin(request: id, exchange: pending.exchangeID,
                                room: pending.roomID, agent: pending.agent))
            } else {
                turnQueueBySurface[surface, default: []].append(.direct)
            }
        case let .turnCompleted(surface, finalMessage):
            guard var queue = turnQueueBySurface[surface], !queue.isEmpty else { return }
            let binding = queue.removeFirst()
            turnQueueBySurface[surface] = queue
            guard case let .chatOrigin(_, exchangeID, room, agent) = binding else { return } // .direct → drop
            attachReply(finalMessage, agent: agent, exchange: exchangeID, room: room)
        }
    }

    /// Flushes held prompts when an agent leaves `needsInput`.
    public func onLifecycleChange(_ change: AgentLifecycleChange) async {
        guard change.state == .running || change.state == .idle else { return }
        guard let held = heldForNeedsInput.removeValue(forKey: change.agent), !held.isEmpty else { return }
        for h in held {
            pendingByRequest[h.requestID] = PendingInjection(
                requestID: h.requestID, exchangeID: h.exchangeID, roomID: h.roomID, agent: h.agent)
            let ok = await injector.inject(h.bodyWithMarker, into: h.agent)
            if !ok {
                pendingByRequest[h.requestID] = nil
                setOutcome(.failedToDispatch, agent: h.agent, exchange: h.exchangeID, room: h.roomID)
            }
        }
    }

    /// Marks an agent's in-flight chat work `.tabClosed` and clears its queues/holds.
    public func onAgentClosed(_ agent: AgentID) {
        // Pending injections.
        for (req, p) in pendingByRequest where p.agent == agent {
            pendingByRequest[req] = nil
            setOutcome(.tabClosed, agent: agent, exchange: p.exchangeID, room: p.roomID)
        }
        // Held prompts.
        if let held = heldForNeedsInput.removeValue(forKey: agent) {
            for h in held { setOutcome(.tabClosed, agent: agent, exchange: h.exchangeID, room: h.roomID) }
        }
        // Queued bindings on any surface for this agent.
        for (surface, queue) in turnQueueBySurface {
            turnQueueBySurface[surface] = queue.filter { binding in
                if case let .chatOrigin(_, _, _, a) = binding { return a != agent }
                return true
            }
        }
    }

    // MARK: Paging

    /// Pages older exchanges for `room` from the store into the window.
    public func loadEarlier(in room: ChatRoomID) async {
        guard var ch = window[room], let oldest = ch.exchanges.first else {
            // Empty window: load the most recent page.
            let recent = await history.recent(in: room, limit: windowSize)
            window[room] = RoomChannel(roomID: room, exchanges: recent, reachedStart: recent.count < windowSize)
            channels[room] = recent
            return
        }
        let older = await history.page(in: room, before: oldest.id, limit: windowSize)
        ch.exchanges = older + ch.exchanges
        ch.reachedStart = older.count < windowSize
        window[room] = ch
        channels[room] = ch.exchanges
    }

    // MARK: Private helpers

    private func appendToWindow(_ exchange: Exchange, in room: ChatRoomID) {
        var ch = window[room] ?? RoomChannel(roomID: room, exchanges: [], reachedStart: false)
        ch.exchanges.append(exchange)
        if ch.exchanges.count > windowSize { ch.exchanges.removeFirst(ch.exchanges.count - windowSize) }
        window[room] = ch
        channels[room] = ch.exchanges
    }

    private func setOutcome(_ outcome: ReplyOutcome, agent: AgentID, exchange: ExchangeID, room: ChatRoomID) {
        guard var ch = window[room], let i = ch.exchanges.firstIndex(where: { $0.id == exchange }) else { return }
        ch.exchanges[i].outcomes[agent] = outcome
        window[room] = ch
        channels[room] = ch.exchanges
        let updated = ch.exchanges[i]
        Task { await history.update(updated, in: room) }
    }

    private func attachReply(_ finalMessage: String, agent: AgentID, exchange: ExchangeID, room: ChatRoomID) {
        guard var ch = window[room], let i = ch.exchanges.firstIndex(where: { $0.id == exchange }) else { return }
        let from = ch.exchanges[i].prompt.targets.first { $0.agentID == agent }
            ?? AgentIdentitySnapshot(agentID: agent, title: "", kind: .claudeCode, cwdDisplay: "", branch: nil)
        let reply = Reply(id: makeMessageID(), exchangeID: exchange, from: from,
                          markdownBody: finalMessage, receivedAt: now())
        ch.exchanges[i].outcomes[agent] = .replied(reply)
        window[room] = ch
        channels[room] = ch.exchanges
        let updated = ch.exchanges[i]
        Task { await history.update(updated, in: room) }
        Task { [notifier, roomsReading] in
            if await roomsReading.activeRoomID() != room { await notifier.notifyRoomCompletion(room) }
        }
    }
}
```

> **Implementer notes:**
> - `channels` is the `@Observable` published view state (UI reads it in Plan 2). Tests assert on it.
> - The `setOutcome`/`attachReply` `Task { await history.update }` calls are fire-and-forget persistence; tests assert on `channels` (synchronous) and, where they need the store, `await` a small yield (see test helpers). This is acceptable because the in-memory window is the source of truth for display and the store is eventually-consistent for restore.
> - `attachReply`'s fallback snapshot only triggers if the exchange somehow lost its target (defensive); the routing tests prove the normal path uses the frozen send-time snapshot.

- [ ] **Step 2: Write the first correlation test**

`CorrelationTests.swift`:

```swift
import Foundation
import Testing
@testable import CmuxChatRoom
import CmuxChatRoomCore

@MainActor
@Suite struct CorrelationTests {
    // Builds a coordinator wired to fakes, with one room and one agent already in the roster.
    func makeFixture() async -> (RoomsCoordinator, FakeRoomWorkspace, FakeRoster, FakeLifecycle,
                                 FakeInjector, FakeNotifier, InMemoryHistoryStore,
                                 room: ChatRoomID, agent: AgentID, snap: AgentIdentitySnapshot) {
        let rooms = FakeRoomWorkspace(); let roster = FakeRoster(); let life = FakeLifecycle()
        let inj = FakeInjector(); let notif = FakeNotifier(); let hist = InMemoryHistoryStore()
        let room = ChatRoomID(raw: UUID()); let agent = AgentID(raw: UUID())
        let snap = AgentIdentitySnapshot(agentID: agent, title: "claude code 1",
                                         kind: .claudeCode, cwdDisplay: "~/work/cmux", branch: "main")
        await roster.set([snap], inRoom: room)
        await rooms.setActive(room)
        let coord = RoomsCoordinator(roomsReading: rooms, roomsManaging: rooms, roster: roster,
                                     lifecycle: life, injector: inj, notifier: notif, history: hist)
        return (coord, rooms, roster, life, inj, notif, hist, room, agent, snap)
    }

    @Test func chatOriginCompletionRoutesToExchange() async {
        let f = await makeFixture()
        await f.0.send(in: f.room, "review this", to: [AgentMention(agentID: f.agent)], origin: .userMention)

        // The injector saw a marker-bearing prompt; recover the marker the agent would echo at submit.
        let injectedText = await f.4.lastText()
        #expect(injectedText != nil)
        let surface = SurfaceID(raw: UUID())
        f.0.handle(.promptSubmitted(surface, rawPromptText: injectedText!))
        f.0.handle(.turnCompleted(surface, finalMessage: "All done."))

        let exchanges = f.0.channels[f.room] ?? []
        #expect(exchanges.count == 1)
        if case let .replied(reply) = exchanges[0].outcomes[f.agent] {
            #expect(reply.markdownBody == "All done.")
            #expect(reply.from.title == "claude code 1")   // frozen send-time snapshot
        } else {
            Issue.record("expected .replied outcome, got \(String(describing: exchanges[0].outcomes[f.agent]))")
        }
    }
}
```

- [ ] **Step 3: Run**

Run: `swift test --package-path Packages/CmuxChatRoom --filter CorrelationTests`
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add Packages/CmuxChatRoom
git commit -m "feat(chat-room): RoomsCoordinator + chat-origin routing test"
```

---

## Task 10: Direct-turn & byte-identical correlation tests

**Files:**
- Modify: `Tests/CmuxChatRoomTests/CorrelationTests.swift`

- [ ] **Step 1: Add the tests**

```swift
    @Test func directTurnWithNoMarkerIsDropped() async {
        let f = await makeFixture()
        let surface = SurfaceID(raw: UUID())
        f.0.handle(.promptSubmitted(surface, rawPromptText: "user typed this directly"))
        f.0.handle(.turnCompleted(surface, finalMessage: "direct result"))
        #expect((f.0.channels[f.room] ?? []).isEmpty)   // nothing posted to any channel
    }

    @Test func directTurnCompletingFirstWhileChatPendingDoesNotAttach() async {
        let f = await makeFixture()
        await f.0.send(in: f.room, "chat prompt", to: [AgentMention(agentID: f.agent)], origin: .userMention)
        let chatInjected = await f.4.lastText()!
        let surface = SurfaceID(raw: UUID())

        // A direct turn is submitted AFTER the chat prompt but completes FIRST.
        f.0.handle(.promptSubmitted(surface, rawPromptText: chatInjected))     // chat → queue[0]
        f.0.handle(.promptSubmitted(surface, rawPromptText: "direct"))         // direct → queue[1]
        f.0.handle(.turnCompleted(surface, finalMessage: "chat done"))         // pops queue[0] = chat
        f.0.handle(.turnCompleted(surface, finalMessage: "direct done"))       // pops queue[1] = direct → drop

        let ex = (f.0.channels[f.room] ?? [])[0]
        if case let .replied(r) = ex.outcomes[f.agent] { #expect(r.markdownBody == "chat done") }
        else { Issue.record("chat reply not attached") }
    }

    @Test func byteIdenticalDirectPromptDoesNotBind() async {
        let f = await makeFixture()
        // Send a chat prompt, then a DIRECT prompt with the exact same user text (no marker).
        await f.0.send(in: f.room, "do the thing", to: [AgentMention(agentID: f.agent)], origin: .userMention)
        let surface = SurfaceID(raw: UUID())
        f.0.handle(.promptSubmitted(surface, rawPromptText: "do the thing"))   // identical text, NO marker
        f.0.handle(.turnCompleted(surface, finalMessage: "leaked?"))           // must NOT attach

        let ex = (f.0.channels[f.room] ?? [])[0]
        #expect(ex.outcomes[f.agent] == .pending)   // still pending; the direct turn was dropped
    }
```

- [ ] **Step 2: Run**

Run: `swift test --package-path Packages/CmuxChatRoom --filter CorrelationTests`
Expected: PASS (4 tests in the suite now).

- [ ] **Step 3: Commit**

```bash
git add Packages/CmuxChatRoom
git commit -m "test(chat-room): direct-drop + byte-identical no-bind"
```

---

## Task 11: Per-surface FIFO with multiple panels

**Files:**
- Modify: `Tests/CmuxChatRoomTests/CorrelationTests.swift`

- [ ] **Step 1: Add the test**

```swift
    @Test func fifoIsPerSurfaceAcrossTwoAgents() async {
        // Two agents in the same room, two distinct surfaces; interleaved turns must not cross.
        let rooms = FakeRoomWorkspace(); let roster = FakeRoster(); let life = FakeLifecycle()
        let inj = FakeInjector(); let notif = FakeNotifier(); let hist = InMemoryHistoryStore()
        let room = ChatRoomID(raw: UUID())
        let a1 = AgentID(raw: UUID()); let a2 = AgentID(raw: UUID())
        let s1 = AgentIdentitySnapshot(agentID: a1, title: "claude code 1", kind: .claudeCode, cwdDisplay: "~/a", branch: nil)
        let s2 = AgentIdentitySnapshot(agentID: a2, title: "codex 1", kind: .codex, cwdDisplay: "~/b", branch: nil)
        await roster.set([s1, s2], inRoom: room); await rooms.setActive(room)
        let coord = RoomsCoordinator(roomsReading: rooms, roomsManaging: rooms, roster: roster,
                                     lifecycle: life, injector: inj, notifier: notif, history: hist)

        await coord.send(in: room, "q", to: [AgentMention(agentID: a1), AgentMention(agentID: a2)], origin: .userMention)
        let injected = await inj.injected   // [(text,a1),(text,a2)] in target order
        let text1 = injected.first(where: { $0.agent == a1 })!.text
        let text2 = injected.first(where: { $0.agent == a2 })!.text

        let surf1 = SurfaceID(raw: UUID()); let surf2 = SurfaceID(raw: UUID())
        coord.handle(.promptSubmitted(surf1, rawPromptText: text1))
        coord.handle(.promptSubmitted(surf2, rawPromptText: text2))
        coord.handle(.turnCompleted(surf2, finalMessage: "from codex"))
        coord.handle(.turnCompleted(surf1, finalMessage: "from claude"))

        let ex = (coord.channels[room] ?? [])[0]
        if case let .replied(r) = ex.outcomes[a1] { #expect(r.markdownBody == "from claude") } else { Issue.record("a1") }
        if case let .replied(r) = ex.outcomes[a2] { #expect(r.markdownBody == "from codex") } else { Issue.record("a2") }
    }
```

- [ ] **Step 2: Run & commit**

Run: `swift test --package-path Packages/CmuxChatRoom --filter CorrelationTests`
Expected: PASS.

```bash
git add Packages/CmuxChatRoom
git commit -m "test(chat-room): per-surface FIFO across panels"
```

---

## Task 12: Room scoping & isolation

**Files:**
- Create: `Tests/CmuxChatRoomTests/RoomScopingTests.swift`

- [ ] **Step 1: Write the tests**

```swift
import Foundation
import Testing
@testable import CmuxChatRoom
import CmuxChatRoomCore

@MainActor
@Suite struct RoomScopingTests {
    @Test func mentionsResolveOnlyToActiveRoomAgents() async {
        let rooms = FakeRoomWorkspace(); let roster = FakeRoster(); let life = FakeLifecycle()
        let inj = FakeInjector(); let notif = FakeNotifier(); let hist = InMemoryHistoryStore()
        let roomA = ChatRoomID(raw: UUID()); let roomB = ChatRoomID(raw: UUID())
        let inA = AgentID(raw: UUID()); let inB = AgentID(raw: UUID())
        await roster.set([AgentIdentitySnapshot(agentID: inA, title: "A", kind: .claudeCode, cwdDisplay: "~/a", branch: nil)], inRoom: roomA)
        await roster.set([AgentIdentitySnapshot(agentID: inB, title: "B", kind: .codex, cwdDisplay: "~/b", branch: nil)], inRoom: roomB)
        let coord = RoomsCoordinator(roomsReading: rooms, roomsManaging: rooms, roster: roster,
                                     lifecycle: life, injector: inj, notifier: notif, history: hist)

        // @all in room A passing BOTH agents must hit only A's agent.
        await coord.send(in: roomA, "hi", to: [AgentMention(agentID: inA), AgentMention(agentID: inB)], origin: .userMention)
        let injected = await inj.injected
        #expect(injected.count == 1)
        #expect(injected[0].agent == inA)
        #expect((coord.channels[roomB] ?? []).isEmpty)   // room B untouched
    }

    @Test func completionRoutesToOriginatingRoomNotActiveRoom() async {
        let rooms = FakeRoomWorkspace(); let roster = FakeRoster(); let life = FakeLifecycle()
        let inj = FakeInjector(); let notif = FakeNotifier(); let hist = InMemoryHistoryStore()
        let roomA = ChatRoomID(raw: UUID()); let roomB = ChatRoomID(raw: UUID())
        let aB = AgentID(raw: UUID())
        await roster.set([AgentIdentitySnapshot(agentID: aB, title: "B", kind: .codex, cwdDisplay: "~/b", branch: nil)], inRoom: roomB)
        await rooms.setActive(roomA)   // user is looking at room A
        let coord = RoomsCoordinator(roomsReading: rooms, roomsManaging: rooms, roster: roster,
                                     lifecycle: life, injector: inj, notifier: notif, history: hist)

        await coord.send(in: roomB, "for B", to: [AgentMention(agentID: aB)], origin: .userMention)
        let text = await inj.lastText()!
        let surf = SurfaceID(raw: UUID())
        coord.handle(.promptSubmitted(surf, rawPromptText: text))
        coord.handle(.turnCompleted(surf, finalMessage: "B reply"))

        #expect((coord.channels[roomA] ?? []).isEmpty)         // not in A
        #expect((coord.channels[roomB] ?? []).count == 1)      // in B
        // And B (non-active) gets a completion badge.
        try? await Task.sleep(nanoseconds: 50_000_000)
        #expect(await notif.badged.contains(roomB))
    }
}
```

> The single `Task.sleep` here waits for the fire-and-forget badge `Task` in `attachReply`. This is the one place a real signal isn't exposed; it is bounded and used only to observe an async side effect, not to poll a condition. If flakiness appears, switch `ChatNotifying` to expose an `AsyncStream` and await the first element instead. (Plan 2's app notifier is synchronous-enough that this never matters in production.)

- [ ] **Step 2: Run & commit**

Run: `swift test --package-path Packages/CmuxChatRoom --filter RoomScopingTests`
Expected: PASS.

```bash
git add Packages/CmuxChatRoom
git commit -m "test(chat-room): room scoping + cross-room routing + badge"
```

---

## Task 13: Needs-input hold & flush

**Files:**
- Create: `Tests/CmuxChatRoomTests/NeedsInputHoldTests.swift`

- [ ] **Step 1: Write the tests**

```swift
import Foundation
import Testing
@testable import CmuxChatRoom
import CmuxChatRoomCore

@MainActor
@Suite struct NeedsInputHoldTests {
    func fixture() async -> (RoomsCoordinator, FakeLifecycle, FakeInjector, room: ChatRoomID, agent: AgentID) {
        let rooms = FakeRoomWorkspace(); let roster = FakeRoster(); let life = FakeLifecycle()
        let inj = FakeInjector(); let notif = FakeNotifier(); let hist = InMemoryHistoryStore()
        let room = ChatRoomID(raw: UUID()); let agent = AgentID(raw: UUID())
        await roster.set([AgentIdentitySnapshot(agentID: agent, title: "A", kind: .claudeCode, cwdDisplay: "~/a", branch: nil)], inRoom: room)
        await rooms.setActive(room)
        let coord = RoomsCoordinator(roomsReading: rooms, roomsManaging: rooms, roster: roster,
                                     lifecycle: life, injector: inj, notifier: notif, history: hist)
        return (coord, life, inj, room, agent)
    }

    @Test func sendingToNeedsInputTargetHoldsWithoutInjecting() async {
        let f = await fixture()
        await f.1.set(.needsInput, for: f.agent)
        await f.0.send(in: f.room, "held prompt", to: [AgentMention(agentID: f.agent)], origin: .userMention)
        #expect(await f.2.injected.isEmpty)                 // nothing injected
        #expect((f.0.channels[f.room] ?? [])[0].outcomes[f.agent] == .pending)
    }

    @Test func leavingNeedsInputFlushesAndInjects() async {
        let f = await fixture()
        await f.1.set(.needsInput, for: f.agent)
        await f.0.send(in: f.room, "held", to: [AgentMention(agentID: f.agent)], origin: .userMention)
        #expect(await f.2.injected.isEmpty)

        await f.0.onLifecycleChange(AgentLifecycleChange(agent: f.agent, state: .idle))
        let injected = await f.2.injected
        #expect(injected.count == 1)
        // Recovered marker proves the held body was injected with its correlation token.
        let (id, _) = ChatPromptMarker.extract(from: injected[0].text)
        #expect(id != nil)
    }

    @Test func heldPromptOnClosedTabResolvesTabClosed() async {
        let f = await fixture()
        await f.1.set(.needsInput, for: f.agent)
        await f.0.send(in: f.room, "held", to: [AgentMention(agentID: f.agent)], origin: .userMention)
        f.0.onAgentClosed(f.agent)
        #expect((f.0.channels[f.room] ?? [])[0].outcomes[f.agent] == .tabClosed)
    }
}
```

- [ ] **Step 2: Run & commit**

Run: `swift test --package-path Packages/CmuxChatRoom --filter NeedsInputHoldTests`
Expected: PASS.

```bash
git add Packages/CmuxChatRoom
git commit -m "test(chat-room): needs-input hold/flush/tab-closed"
```

---

## Task 14: Forward, quote-at-send, failedToDispatch, identity-frozen

**Files:**
- Create: `Tests/CmuxChatRoomTests/ForwardQuoteTests.swift`

- [ ] **Step 1: Write the tests**

```swift
import Foundation
import Testing
@testable import CmuxChatRoom
import CmuxChatRoomCore

@MainActor
@Suite struct ForwardQuoteTests {
    func fixture() async -> (RoomsCoordinator, FakeRoster, FakeInjector, room: ChatRoomID, agent: AgentID) {
        let rooms = FakeRoomWorkspace(); let roster = FakeRoster(); let life = FakeLifecycle()
        let inj = FakeInjector(); let notif = FakeNotifier(); let hist = InMemoryHistoryStore()
        let room = ChatRoomID(raw: UUID()); let agent = AgentID(raw: UUID())
        await roster.set([AgentIdentitySnapshot(agentID: agent, title: "A", kind: .claudeCode, cwdDisplay: "~/a", branch: "main")], inRoom: room)
        await rooms.setActive(room)
        let coord = RoomsCoordinator(roomsReading: rooms, roomsManaging: rooms, roster: roster,
                                     lifecycle: life, injector: inj, notifier: notif, history: hist)
        return (coord, roster, inj, room, agent)
    }

    @Test func forwardWrapsQuoteAndNoteAsNewExchange() async {
        let f = await fixture()
        let src = MessageID(raw: UUID())
        await f.0.forward(src, quoted: "3 issues found", note: "fix #2 first",
                          to: [AgentMention(agentID: f.agent)], in: f.room)
        let ex = (f.0.channels[f.room] ?? [])[0]
        #expect(ex.prompt.bodyText == "\"3 issues found\"\nfix #2 first")
        #expect(ex.prompt.origin == .forward(sourceMessageID: src))
    }

    @Test func targetRemovedBeforeSendFailsToDispatch() async {
        let f = await fixture()
        // Send to an agent not in the room → resolved targets empty → no exchange created.
        let ghost = AgentID(raw: UUID())
        await f.0.send(in: f.room, "hi", to: [AgentMention(agentID: ghost)], origin: .userMention)
        #expect((f.0.channels[f.room] ?? []).isEmpty)
    }

    @Test func injectorFailureMarksFailedToDispatch() async {
        let f = await fixture()
        await f.2.failNext(for: f.agent)
        await f.0.send(in: f.room, "hi", to: [AgentMention(agentID: f.agent)], origin: .userMention)
        #expect((f.0.channels[f.room] ?? [])[0].outcomes[f.agent] == .failedToDispatch)
    }

    @Test func identitySnapshotFrozenAtSendTime() async {
        let f = await fixture()
        await f.0.send(in: f.room, "q", to: [AgentMention(agentID: f.agent)], origin: .userMention)
        // Mutate the roster (branch switch) AFTER send.
        await f.1.set([AgentIdentitySnapshot(agentID: f.agent, title: "A", kind: .claudeCode, cwdDisplay: "~/a", branch: "feature")], inRoom: f.room)
        let text = await f.2.lastText()!
        let surf = SurfaceID(raw: UUID())
        f.0.handle(.promptSubmitted(surf, rawPromptText: text))
        f.0.handle(.turnCompleted(surf, finalMessage: "done"))
        if case let .replied(r) = (f.0.channels[f.room] ?? [])[0].outcomes[f.agent] {
            #expect(r.from.branch == "main")   // frozen at send time, not "feature"
        } else { Issue.record("no reply") }
    }
}
```

- [ ] **Step 2: Run & commit**

Run: `swift test --package-path Packages/CmuxChatRoom --filter ForwardQuoteTests`
Expected: PASS.

```bash
git add Packages/CmuxChatRoom
git commit -m "test(chat-room): forward/quote/failedToDispatch/frozen-identity"
```

---

## Task 15: Move-mid-flight & tab-closed routing

**Files:**
- Create: `Tests/CmuxChatRoomTests/MoveAndCloseTests.swift`

- [ ] **Step 1: Write the tests**

```swift
import Foundation
import Testing
@testable import CmuxChatRoom
import CmuxChatRoomCore

@MainActor
@Suite struct MoveAndCloseTests {
    @Test func inFlightReplyLandsInOriginatingRoomAfterMove() async {
        let rooms = FakeRoomWorkspace(); let roster = FakeRoster(); let life = FakeLifecycle()
        let inj = FakeInjector(); let notif = FakeNotifier(); let hist = InMemoryHistoryStore()
        let roomA = ChatRoomID(raw: UUID()); let roomB = ChatRoomID(raw: UUID())
        let agent = AgentID(raw: UUID())
        let snap = AgentIdentitySnapshot(agentID: agent, title: "A", kind: .claudeCode, cwdDisplay: "~/a", branch: nil)
        await roster.set([snap], inRoom: roomA)
        await rooms.setActive(roomA)
        let coord = RoomsCoordinator(roomsReading: rooms, roomsManaging: rooms, roster: roster,
                                     lifecycle: life, injector: inj, notifier: notif, history: hist)

        await coord.send(in: roomA, "from A", to: [AgentMention(agentID: agent)], origin: .userMention)
        let text = await inj.lastText()!
        // Agent moves to room B mid-flight.
        await coord.move(agent, to: roomB)
        #expect(await rooms.moved.contains(where: { $0.0 == agent && $0.1 == roomB }))

        let surf = SurfaceID(raw: UUID())
        coord.handle(.promptSubmitted(surf, rawPromptText: text))
        coord.handle(.turnCompleted(surf, finalMessage: "reply"))
        // Reply still routes to room A (binding carried its originating room).
        #expect((coord.channels[roomA] ?? []).count == 1)
        #expect((coord.channels[roomB] ?? []).isEmpty)
    }

    @Test func tabClosedWithPendingMarksTabClosed() async {
        let rooms = FakeRoomWorkspace(); let roster = FakeRoster(); let life = FakeLifecycle()
        let inj = FakeInjector(); let notif = FakeNotifier(); let hist = InMemoryHistoryStore()
        let room = ChatRoomID(raw: UUID()); let agent = AgentID(raw: UUID())
        await roster.set([AgentIdentitySnapshot(agentID: agent, title: "A", kind: .claudeCode, cwdDisplay: "~/a", branch: nil)], inRoom: room)
        await rooms.setActive(room)
        let coord = RoomsCoordinator(roomsReading: rooms, roomsManaging: rooms, roster: roster,
                                     lifecycle: life, injector: inj, notifier: notif, history: hist)
        await coord.send(in: room, "q", to: [AgentMention(agentID: agent)], origin: .userMention)
        coord.onAgentClosed(agent)
        #expect((coord.channels[room] ?? [])[0].outcomes[agent] == .tabClosed)
    }
}
```

- [ ] **Step 2: Run & commit**

Run: `swift test --package-path Packages/CmuxChatRoom --filter MoveAndCloseTests`
Expected: PASS.

```bash
git add Packages/CmuxChatRoom
git commit -m "test(chat-room): move-mid-flight + tab-closed routing"
```

---

## Task 16: Windowing + room-CRUD forwarding

**Files:**
- Create: `Tests/CmuxChatRoomTests/WindowingAndRoomCRUDTests.swift`

- [ ] **Step 1: Write the tests**

```swift
import Foundation
import Testing
@testable import CmuxChatRoom
import CmuxChatRoomCore

@MainActor
@Suite struct WindowingAndRoomCRUDTests {
    @Test func roomCRUDForwardsToManagingSeam() async {
        let rooms = FakeRoomWorkspace(); let roster = FakeRoster(); let life = FakeLifecycle()
        let inj = FakeInjector(); let notif = FakeNotifier(); let hist = InMemoryHistoryStore()
        let coord = RoomsCoordinator(roomsReading: rooms, roomsManaging: rooms, roster: roster,
                                     lifecycle: life, injector: inj, notifier: notif, history: hist)
        let id = await coord.createRoom(name: "feature-auth")
        await coord.renameRoom(id, to: "feature-auth-2")
        await coord.closeRoom(id)
        #expect(await rooms.created == ["feature-auth"])
        #expect(await rooms.renamed.contains(where: { $0.0 == id && $0.1 == "feature-auth-2" }))
        #expect(await rooms.closeRequested.contains(id))
        // No shadow room state on the coordinator: active room comes from the seam.
        await rooms.setActive(id)
        #expect(await coord.activeRoomID() == id)
    }

    @Test func loadEarlierPagesOlderExchangesRespectingWindow() async {
        let rooms = FakeRoomWorkspace(); let roster = FakeRoster(); let life = FakeLifecycle()
        let inj = FakeInjector(); let notif = FakeNotifier(); let hist = InMemoryHistoryStore()
        let room = ChatRoomID(raw: UUID())
        // Seed 5 exchanges directly into the store.
        for i in 0..<5 {
            let ex = ExchangeID(raw: UUID())
            let p = OutgoingPrompt(exchangeID: ex, roomID: room, origin: .userMention,
                                   bodyText: "m\(i)", targets: [], sentAt: Date(timeIntervalSince1970: Double(i)))
            await hist.append(Exchange(prompt: p, outcomes: [:]), in: room)
        }
        let coord = RoomsCoordinator(roomsReading: rooms, roomsManaging: rooms, roster: roster,
                                     lifecycle: life, injector: inj, notifier: notif, history: hist,
                                     windowSize: 2)
        // First loadEarlier on empty window loads the most recent 2.
        await coord.loadEarlier(in: room)
        #expect((coord.channels[room] ?? []).map(\.prompt.bodyText) == ["m3", "m4"])
        // Next loadEarlier pages 2 older in front.
        await coord.loadEarlier(in: room)
        #expect((coord.channels[room] ?? []).map(\.prompt.bodyText) == ["m1", "m2", "m3", "m4"])
    }
}
```

- [ ] **Step 2: Run & commit**

Run: `swift test --package-path Packages/CmuxChatRoom --filter WindowingAndRoomCRUDTests`
Expected: PASS.

```bash
git add Packages/CmuxChatRoom
git commit -m "test(chat-room): windowing + room CRUD forwarding"
```

---

## Task 17: `JSONChatHistoryStore` (concrete repository) — TDD

**Files:**
- Create: `Sources/CmuxChatRoom/JSONChatHistoryStore.swift`
- Create: `Tests/CmuxChatRoomTests/JSONChatHistoryStoreTests.swift`

> Concrete `ChatHistoryStore` backed by one JSON file per room, keyed by the stable `ChatRoomID`,
> under an **injected** directory (CLAUDE.md testability rule). Plan 2 constructs it with the
> Application Support path; tests inject a temp dir.

- [ ] **Step 1: Write the failing tests**

`JSONChatHistoryStoreTests.swift`:

```swift
import Foundation
import Testing
@testable import CmuxChatRoom
import CmuxChatRoomCore

@Suite struct JSONChatHistoryStoreTests {
    func tempDir() -> URL {
        let base = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("chatroom-hist-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }
    func exchange(_ body: String, room: ChatRoomID, at t: Double) -> Exchange {
        let p = OutgoingPrompt(exchangeID: ExchangeID(raw: UUID()), roomID: room, origin: .userMention,
                               bodyText: body, targets: [], sentAt: Date(timeIntervalSince1970: t))
        return Exchange(prompt: p, outcomes: [:])
    }

    @Test func appendThenRecentRoundTripsAcrossInstances() async throws {
        let dir = tempDir(); let room = ChatRoomID(raw: UUID())
        let store = JSONChatHistoryStore(directory: dir)
        await store.append(exchange("a", room: room, at: 1), in: room)
        await store.append(exchange("b", room: room, at: 2), in: room)
        // New instance reads from disk → durable.
        let store2 = JSONChatHistoryStore(directory: dir)
        let recent = await store2.recent(in: room, limit: 10)
        #expect(recent.map(\.prompt.bodyText) == ["a", "b"])
    }

    @Test func updateReplacesSameExchange() async {
        let dir = tempDir(); let room = ChatRoomID(raw: UUID())
        let store = JSONChatHistoryStore(directory: dir)
        var ex = exchange("a", room: room, at: 1)
        await store.append(ex, in: room)
        let agent = AgentID(raw: UUID())
        ex.outcomes[agent] = .tabClosed
        await store.update(ex, in: room)
        let recent = await store.recent(in: room, limit: 10)
        #expect(recent.count == 1)
        #expect(recent[0].outcomes[agent] == .tabClosed)
    }

    @Test func pageReturnsOlderBeforeCursor() async {
        let dir = tempDir(); let room = ChatRoomID(raw: UUID())
        let store = JSONChatHistoryStore(directory: dir)
        let exs = (0..<5).map { exchange("m\($0)", room: room, at: Double($0)) }
        for e in exs { await store.append(e, in: room) }
        let page = await store.page(in: room, before: exs[3].id, limit: 2)
        #expect(page.map(\.prompt.bodyText) == ["m1", "m2"])
    }

    @Test func roomsAreIsolatedByID() async {
        let dir = tempDir(); let a = ChatRoomID(raw: UUID()); let b = ChatRoomID(raw: UUID())
        let store = JSONChatHistoryStore(directory: dir)
        await store.append(exchange("inA", room: a, at: 1), in: a)
        #expect(await store.recent(in: b, limit: 10).isEmpty)
        #expect(await store.recent(in: a, limit: 10).map(\.prompt.bodyText) == ["inA"])
    }
}
```

- [ ] **Step 2: Run to confirm failure**

Run: `swift test --package-path Packages/CmuxChatRoom --filter JSONChatHistoryStoreTests`
Expected: FAIL — `JSONChatHistoryStore` does not exist.

- [ ] **Step 3: Implement the store**

```swift
import Foundation
public import CmuxChatRoomCore

/// JSON-file-per-room ``ChatHistoryStore``, keyed by the stable ``ChatRoomID`` so history reconnects
/// after restore even though `Workspace.id` is re-minted (spec §4.11).
///
/// Each room is one file `<directory>/<chatRoomID>.json` holding an ordered (oldest-first) array of
/// ``Exchange``. The directory is injected for testability.
public actor JSONChatHistoryStore: ChatHistoryStore {
    private let directory: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private var cache: [ChatRoomID: [Exchange]] = [:]

    /// Creates a store rooted at `directory` (created on first write if absent).
    public init(directory: URL, fileManager: FileManager = .default) {
        self.directory = directory
        self.fileManager = fileManager
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
    }

    private func fileURL(_ room: ChatRoomID) -> URL {
        directory.appendingPathComponent("\(room.raw.uuidString).json")
    }

    private func load(_ room: ChatRoomID) -> [Exchange] {
        if let cached = cache[room] { return cached }
        guard let data = try? Data(contentsOf: fileURL(room)),
              let list = try? decoder.decode([Exchange].self, from: data) else {
            cache[room] = []; return []
        }
        cache[room] = list; return list
    }

    private func persist(_ list: [Exchange], _ room: ChatRoomID) {
        cache[room] = list
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        if let data = try? encoder.encode(list) {
            try? data.write(to: fileURL(room), options: .atomic)
        }
    }

    public func append(_ exchange: Exchange, in room: ChatRoomID) {
        var list = load(room); list.append(exchange); persist(list, room)
    }

    public func update(_ exchange: Exchange, in room: ChatRoomID) {
        var list = load(room)
        guard let i = list.firstIndex(where: { $0.id == exchange.id }) else { return }
        list[i] = exchange; persist(list, room)
    }

    public func recent(in room: ChatRoomID, limit: Int) -> [Exchange] {
        Array(load(room).suffix(limit))
    }

    public func page(in room: ChatRoomID, before: ExchangeID, limit: Int) -> [Exchange] {
        let list = load(room)
        guard let i = list.firstIndex(where: { $0.id == before }) else { return [] }
        return Array(list[..<i].suffix(limit))
    }
}
```

- [ ] **Step 4: Run to confirm pass**

Run: `swift test --package-path Packages/CmuxChatRoom --filter JSONChatHistoryStoreTests`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add Packages/CmuxChatRoom
git commit -m "feat(chat-room): JSONChatHistoryStore with persistence tests"
```

---

## Task 18: Full-suite green + self-review

**Files:** none (verification only)

- [ ] **Step 1: Run both package suites**

```bash
swift test --package-path Packages/CmuxChatRoomCore
swift test --package-path Packages/CmuxChatRoom
```
Expected: ALL PASS.

- [ ] **Step 2: Confirm CI wiring**

```bash
grep -n -E "CmuxChatRoomCore|CmuxChatRoom" .github/workflows/ci.yml
```
Expected: both appear in the `PACKAGES` array.

- [ ] **Step 3: Confirm no forbidden primitives crept in**

```bash
grep -rn -E "DispatchQueue|@Published|ObservableObject|NSLock|os_unfair_lock|\.sync \{" Packages/CmuxChatRoomCore/Sources Packages/CmuxChatRoom/Sources
```
Expected: no matches (Swift 6 concurrency only).

- [ ] **Step 4: Spec coverage check (manual read-through)**

Confirm each maps to a task: §4.3 DTOs (Tasks 1–4) · `ChatPromptMarker` (Task 5) · seams (Task 6) · §4.6 correlation incl. marker bind, FIFO, direct-drop, byte-identical, @all scope, cross-room route, move-mid-flight, needs-input hold/flush, forward/quote, resolve-at-send, tab-closed, frozen identity (Tasks 9–16) · §4.11 persistence + paged reads (Task 17). UI (§4.8/§3.x rendering) and all app wiring are **Plan 2**.

- [ ] **Step 5: Final commit (if any doc/notes added)**

```bash
git add -A
git commit -m "chore(chat-room): foundation suite green" --allow-empty
```

---

## What Plan 2 covers (for reference, not this plan)

Spec Step 0 audit + Steps 5–16: the app-side hook bridge (`surface_id` + raw pre-redaction events → `AgentTurnEvent`), `WorkspaceRole`/`chatRoomID`/`roomID`/`AgentKind` fields on `Workspace`, `TabManager` concrete seams, the net-new two-section sidebar renderer, `CmuxChatRoomUI` views, the fail-closed creation policy across ~27 `addWorkspace` sites, `closeWorkspace(force:)` + `closeRoom`, notifications, persistence-snapshot migration, the Claude→Codex→Cursor adapters (gated on G1), localization, and DocC/READMEs. Plan 2 is authored after this foundation merges and Step 0's empirical findings are in hand.
