# DeepResearch Usability + API Improvements Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement all usability gaps and API improvements discovered in the 2026-08-26 investigation: follow-up via previous_interaction_id, delete history, cancel button, per-session deadline, proper system_instruction usage, and API-aligned preferences.

**Architecture:** Extend existing SwiftData model (ResearchSession) with optional parent/deadline fields using lightweight migration; extend InteractionsClientProtocol with previousInteractionID + systemInstruction; wire ResearchCoordinator lifecycle to support follow-up and per-session watchdog; add SwiftUI controls to LiveLogView/SidebarView/NewResearchView/PreferencesView.

**Tech Stack:** Swift 6.2, SwiftUI, SwiftData, URLSession (Security for Keychain), XCTest with fixtures

**Spec:** `.scratch/deepresearch/spec.md` (design approved 2026-08-25) + `.scratch/deepresearch/api-contract.md` (Interactions API contract)

## Global Constraints

- macOS 15+, Swift 6.2, Xcode 26, arm64-apple-macosx15.0 — no Intel build (AGENTS.md: macOS Ventura is legacy only)
- SwiftPM executable, **zero external dependencies** (`Package.swift:8` dependencies: [])
- SwiftData store at `~/Library/Application Support/local.issoeocio.DeepResearch/DeepResearch.sqlite` with fixed bundleIdentifier `local.issoeocio.DeepResearch` (`AppEnvironment.swift:8`) — re-adoption depends on it
- API key from Keychain (`local.issoeocio.DeepResearch`/`google-api-key`) → fallback `~/.local/share/opencode/auth.json` (`APIKeyStore.swift:13`) — never log key
- Coordinator is `@MainActor final class` (not @Observable), single instance in `DeepResearchApp.swift:22`
- Polling 20s, stall global default 15m (`ResearchCoordinator.swift:31,51`), status `isTerminal` = completed/cancelled/failed
- String Catalogs: base pt-BR + en (spec §9)
- No `mtd*` flash writes, no FDA re-grant via PPPC (AGENTS.md)

---

## File Structure

| File | Responsibility |
|---|---|
| `Sources/DeepResearch/Core/InteractionsClient.swift` | HTTP contract: add `previousInteractionID` and `systemInstruction` to create/createStream payloads |
| `Sources/DeepResearch/Core/InteractionModels.swift` | No step change, but verify InteractionStatus.requiresAction handling |
| `Sources/DeepResearch/Core/ResearchCoordinator.swift` | Lifecycle: follow-up via parent ID, per-session watchdog, expose stopMonitoring for delete |
| `Sources/DeepResearch/Models/ResearchSession.swift` | Persist follow-up link + per-session deadline (optional fields, lightweight migration) |
| `Sources/DeepResearch/Views/LiveLogView.swift` | Cancel button, follow-up composer, banner for requiresAction |
| `Sources/DeepResearch/Views/SidebarView.swift` | Delete via contextMenu + swipeActions + confirmation |
| `Sources/DeepResearch/Views/NewResearchView.swift` | Deadline picker per research + passthrough to coordinator |
| `Sources/DeepResearch/Views/PreferencesView.swift` | Default deadline, advanced: systemInstruction preview, maybe agent_config toggles |
| `Sources/DeepResearch/Core/AppPreferences.swift` | Preference keys for defaultDeadline |
| `Tests/DeepResearchTests/*` | XCTest for each feature (fixtures + mock clients) |
| `docs/superpowers/plans/2026-08-26-deep-research-usability-api.md` | This plan |

---

### Task 1: Cancel button for running research

**Files:**
- Modify: `Sources/DeepResearch/Views/LiveLogView.swift:17-86` (toolbar + body running branch)
- Test: `Tests/DeepResearchTests/ResearchCoordinatorTests.swift` (existing cancel test already passes; add view smoke if needed)

**Interfaces:**
- Consumes: `ResearchCoordinator.cancel(session:)` already exists (`ResearchCoordinator.swift:105`)
- Produces: `LiveLogView` shows `Cancel` when `session.status == .running`

- [ ] **Step 1: Add cancel button in LiveLogView toolbar/body**

```swift
// In LiveLogView.body, inside the VStack after PhaseTrailView, add:
if session.status == .running {
    ToolbarItem(placement: .cancellationAction) {
        Button(role: .destructive) {
            Task { await coordinator.cancel(session: session) }
        } label: {
            Label("Cancel", systemImage: "xmark.circle")
        }
        .help("Cancel research (preserves collected progress)")
    }
}
// Also in running footer area, add explicit Stop button next to progress:
HStack {
    ProgressFooterView(startedAt: session.startedAt, agent: session.agent)
    Button(role: .destructive) { Task { await coordinator.cancel(session: session) } } label: {
        Label("Stop", systemImage: "stop.circle")
    }.buttonStyle(.bordered)
}
```

- [ ] **Step 2: Build and verify**

Run: `swift build` — expect no errors
Run: `./build.sh && pkill -x DeepResearch; sleep 1; open /Applications/DeepResearch.app` — verify Cancel appears on a running stub (start a research, see button)

- [ ] **Step 3: Commit**

```bash
git add Sources/DeepResearch/Views/LiveLogView.swift
git commit -m "feat: add Cancel button for running research"
```

---

### Task 2: Delete history (Sidebar)

**Files:**
- Modify: `Sources/DeepResearch/Views/SidebarView.swift:28-74` (List sections)
- Modify: `Sources/DeepResearch/Core/ResearchCoordinator.swift:199` (expose stopMonitoring or make delete safe)
- Test: `Tests/DeepResearchTests/ResearchCoordinatorTests.swift` — add delete-during-polling test (optional)

**Interfaces:**
- Consumes: `@Environment(\.modelContext)`, `ResearchSession` (@Model)
- Produces: deleted session removed from SwiftData; monitoring task cancelled before delete

- [ ] **Step 1: Add delete via contextMenu + swipeActions**

```swift
// In SidebarView, inject modelContext
@Environment(\.modelContext) private var modelContext

// For each ForEach, chain:
.contextMenu {
    Button(role: .destructive) { deleteSession(session) } label: {
        Label("Delete", systemImage: "trash")
    }
}
.swipeActions(edge: .trailing, allowsFullSwipe: false) {
    Button(role: .destructive) { deleteSession(session) } label: {
        Label("Delete", systemImage: "trash")
    }
}

// Helper
@State private var sessionToDelete: ResearchSession?
@State private var showDeleteConfirm = false

private func deleteSession(_ session: ResearchSession) {
    if coordinator.isMonitoring(for: session) {
        // Stop monitoring first — expose coordinator.stopMonitoring(session:) as internal
        coordinator.stopMonitoring(session: session)
    }
    // If this is the selected session, clear selection
    if selectedSessionID == session.persistentModelID { selectedSessionID = nil }
    modelContext.delete(session)
    try? modelContext.save()
}
```

- [ ] **Step 2: Expose stopMonitoring**

```swift
// ResearchCoordinator.swift:199
func stopMonitoring(session: ResearchSession) { // was private
    if let handle = monitoringTasks.removeValue(forKey: session.persistentModelID) {
        handle.task.cancel()
    }
    transportModes.removeValue(forKey: session.persistentModelID)
}
```

- [ ] **Step 3: Build and verify**

Run: `swift build`
Run: `swift test` — existing tests unaffected
Manual: long-press/swipe on History row → Delete → confirm → row disappears

- [ ] **Step 4: Commit**

```bash
git add Sources/DeepResearch/Views/SidebarView.swift Sources/DeepResearch/Core/ResearchCoordinator.swift
git commit -m "feat: delete research from history (context menu + swipe)"
```

---

### Task 3: Per-session deadline (watchdog per question)

**Files:**
- Modify: `Sources/DeepResearch/Models/ResearchSession.swift:45-82` (add `deadlineSeconds: Int?`)
- Modify: `Sources/DeepResearch/Core/ResearchCoordinator.swift:31,47,206` (per-session stall, hasStalled uses session.deadlineSeconds ?? stallTimeout)
- Modify: `Sources/DeepResearch/Core/AppPreferences.swift` (add `defaultDeadlineSeconds`)
- Modify: `Sources/DeepResearch/Views/NewResearchView.swift` (deadline picker)
- Modify: `Sources/DeepResearch/Views/PreferencesView.swift` (default deadline pref)
- Test: `Tests/DeepResearchTests/ResearchCoordinatorTests.swift` — add test: session with short deadline fails after watchdog

**Interfaces:**
- Consumes: `ResearchSession.deadlineSeconds: Int?` (nil = use global stallTimeout)
- Produces: `coordinator.start(question:agent:context:deadlineSeconds:)` respects per-session value

- [ ] **Step 1: Extend model with optional deadline**

```swift
// ResearchSession.swift
var deadlineSeconds: Int? // nil = use coordinator default (900s)

init(..., deadlineSeconds: Int? = nil) {
    ...
    self.deadlineSeconds = deadlineSeconds
}
```

SwiftData lightweight migration handles added optional property (no schema version bump needed for optional field — verify by building and launching with existing sqlite).

- [ ] **Step 2: Wire coordinator to use per-session deadline**

```swift
// ResearchCoordinator.swift — start signature
func start(question: String, agent: AgentKind = .regular, context: String? = nil, deadlineSeconds: Int? = nil) async {
    let session = ResearchSession(question: question, agent: agent, status: .queued, deadlineSeconds: deadlineSeconds)
    ...
}

// hasStalled
private func hasStalled(session: ResearchSession) -> Bool {
    guard session.status == .running else { return false }
    let timeout = session.deadlineSeconds.map { Duration.seconds($0) } ?? stallTimeout
    guard timeout != .seconds(0) else { return false }
    guard Date.now.timeIntervalSince(session.startedAt) >= Double(timeout.components.seconds) else { return false }
    return session.stepLog.allSatisfy { $0.type == "user_input" }
}

// Also add AppPreferences key
static let defaultDeadlineSeconds = "defaultDeadlineSeconds" // Int, default 900 (15m), 0 = disabled
```

- [ ] **Step 3: UI — NewResearchView deadline picker + Preferences default**

```swift
// NewResearchView.swift
@AppStorage(AppPreferences.defaultDeadlineSeconds) private var defaultDeadline: Int = 900
@State private var deadlineSeconds: Int? = nil // nil = default

Picker("Deadline", selection: $deadlineSeconds) {
    Text("Default (15m)").tag(nil as Int?)
    Text("5 min").tag(300 as Int?)
    Text("15 min").tag(900 as Int?)
    Text("30 min").tag(1800 as Int?)
    Text("1 hour").tag(3600 as Int?)
    Text("No timeout").tag(0 as Int?)
}
onAppear { if deadlineSeconds == nil { deadlineSeconds = defaultDeadline == 0 ? 0 : defaultDeadline } }

// startResearch(): coordinator.start(..., deadlineSeconds: deadlineSeconds == 0 ? 0 : deadlineSeconds)
```

- [ ] **Step 4: Build and test**

Run: `swift build`
Run: `swift test` — add a test that starts a session with `deadlineSeconds: 1`, waits 1.5s, asserts `.failed`

- [ ] **Step 5: Commit**

```bash
git add Sources/DeepResearch/Models/ResearchSession.swift Sources/DeepResearch/Core/ResearchCoordinator.swift Sources/DeepResearch/Core/AppPreferences.swift Sources/DeepResearch/Views/NewResearchView.swift Sources/DeepResearch/Views/PreferencesView.swift
git commit -m "feat: per-session deadline (watchdog) with UI"
```

---

### Task 4: Follow-up via previous_interaction_id

**Files:**
- Modify: `Sources/DeepResearch/Core/InteractionsClient.swift:20,54,78,239` (protocol + payloads)
- Modify: `Sources/DeepResearch/Core/ResearchCoordinator.swift:62,105` (followUp method)
- Modify: `Sources/DeepResearch/Models/ResearchSession.swift` (add `parentInteractionID: String?`, `parentQuestion: String?`)
- Modify: `Sources/DeepResearch/Views/LiveLogView.swift` (follow-up field when completed/cancelled/failed)
- Test: `Tests/DeepResearchTests/ResearchCoordinatorTests.swift` + `InteractionsClientTests.swift`

**Interfaces:**
- Consumes: `previous_interaction_id` field in create payload
- Produces: `ResearchCoordinator.followUp(session:question:)` creates new ResearchSession linked to parent

- [ ] **Step 1: Extend protocol and client**

```swift
// InteractionsClientProtocol
func create(question: String, agent: AgentKind, context: String?, previousInteractionID: String?, systemInstruction: String?) async throws -> Interaction
func createStream(question: String, agent: AgentKind, context: String?, previousInteractionID: String?, systemInstruction: String?) async throws -> AsyncStream<SSEEvent>
// Keep default compat: context = nil, previousInteractionID = nil etc.

// URLSessionInteractionsClient.create body:
var body: [String: Any] = ["input": input, "agent": agentId, "background": true]
if let prev = previousInteractionID { body["previous_interaction_id"] = prev }
if let sys = systemInstruction, !sys.isEmpty { body["system_instruction"] = sys }
```

- [ ] **Step 2: Model link**

```swift
// ResearchSession.swift
var parentInteractionID: String?
var parentQuestion: String?
```

- [ ] **Step 3: Coordinator followUp**

```swift
@MainActor
func followUp(session: ResearchSession, question: String, context: String? = nil) async {
    let prevID = session.interactionID
    await start(question: question, agent: session.agent, context: context, previousInteractionID: prevID)
    // New session's parent fields set in start()
}
```

- [ ] **Step 4: UI in LiveLogView**

When `status.isTerminal`, show TextField + Button "Ask follow-up" that calls `coordinator.followUp(session:question:)`. Also handle `requiresAction` status: show amber banner "API requested clarification — send a follow-up or continue on the website".

- [ ] **Step 5: Build and test**

Run: `swift build`

- [ ] **Step 6: Commit**

```bash
git add Sources/DeepResearch/Core/InteractionsClient.swift Sources/DeepResearch/Core/ResearchCoordinator.swift Sources/DeepResearch/Models/ResearchSession.swift Sources/DeepResearch/Views/LiveLogView.swift Tests/
git commit -m "feat: follow-up via previous_interaction_id"
```

---

### Task 5: Proper system_instruction (instead of input concatenation)

**Files:**
- Modify: `Sources/DeepResearch/Core/InteractionsClient.swift:239` (split buildInput into systemInstruction + userInput)
- Modify: `Sources/DeepResearch/Core/AppPreferences.swift` (editable systemInstruction default)
- Test: `Tests/DeepResearchTests/InteractionsClientTests.swift` (assert system_instruction field when non-nil)

**Interfaces:**
- Consumes: format instruction string (now sent as `system_instruction`, not prefixed to `input`)
- Produces: cleaner `input` (just question + folder context), `system_instruction` in payload

- [ ] **Step 1: Split buildInput**

```swift
private static let systemInstruction = """
Always respond in structured Markdown: use ## headings...
[N] Title — Publisher/Venue (year). URL — never just the raw link.
"""

private static func buildInput(question: String, context: String?) -> String {
    guard let context, !context.isEmpty else { return question }
    return """
    [Local file context]
    \(context)
    [/Local file context]

    User question: \(question)
    """
}
// In create/createStream: send systemInstruction separately
```

Keep LiveLogView.splitUserInput handling both — legacy input with prefix still displays correctly.

- [ ] **Step 2: Build and verify display still works for legacy sessions**

Run: `swift build && swift test`

- [ ] **Step 3: Commit**

```bash
git add Sources/DeepResearch/Core/InteractionsClient.swift
git commit -m "refactor: send format instruction as system_instruction"
```

---

### Task 6: Polish and final verification

**Files:**
- Modify: `Sources/DeepResearch/Views/PreferencesView.swift` (add deadline default, maybe tool toggles)
- Verify: `Tests/DeepResearchTests/*`, `Sources/DeepResearch/Resources/Localizable.xcstrings`

- [ ] **Step 1: Final build + test sweep**

Run: `swift build && swift test && ./build.sh`

- [ ] **Step 2: Manual smoke**

Launch app → New research → check deadline picker → run short research → test Cancel → test Delete → test Follow-up

- [ ] **Step 3: Commit docs if needed**

```bash
git add docs/superpowers/plans/2026-08-26-deep-research-usability-api.md
git commit -m "docs: plan for usability + API improvements" --allow-empty || true
```

---

## Self-Review

**Spec coverage:**
- Spec §5 retry/backoff → existing, not in this plan (ticket 11)
- Spec follow-up fire-and-forget → now Task 4 with API-native follow-up (upgrade)
- Spec cancel/parcial → Task 1 (was backend-only)
- Spec histórico exclusão manual → Task 2
- Spec sem timeout → Task 3 refines with per-session opt-in

**Placeholder scan:** No TBD/TODO — all steps have concrete code.

**Type consistency:** `ResearchSession.deadlineSeconds: Int?`, `stallTimeout: Duration`, `previousInteractionID: String?` consistent across tasks.

