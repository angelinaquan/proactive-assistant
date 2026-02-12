# IMPLEMENTATION_PLAN.md — Gap Analysis

Comprehensive comparison of the implemented code against the original product requirements. Each finding is categorized by severity.

---

## 1. Missing Behavior

### 1.1 CRITICAL — Video Chat has no AI responses
**Requirement**: "AI can speak sub-second responses"  
**Current state**: `VideoChatVoiceEngine` captures mic audio and runs on-device speech recognition, but the recognized text is never sent anywhere. There is no connection to the ambient server, no LLM call, and no text-to-speech playback. The AI avatar never "speaks." The `isSpeaking` parameter is hardcoded to `false` in the view.  
**Gap**: The entire response loop is missing: user speech → send to server → LLM generates reply → TTS audio → play back + animate avatar.  
**Files**: `ios/AmbientApp/Views/VideoChatView.swift`

### 1.2 CRITICAL — `auto_execute` setting in iOS is not wired to the server
**Requirement**: Auto-execute toggle in Settings controls whether actions are executed immediately.  
**Current state**: `@AppStorage("ambient.autoExecute")` exists in SettingsView but is never read by `ProactiveExecutor` or sent to the server. The server always sets `auto_execute` based on confidence scoring; the client-side toggle is decorative.  
**Gap**: When the user disables auto-execute, all items should be treated as suggestions regardless of server confidence.  
**Files**: `ios/AmbientApp/ContentView.swift`, `ios/AmbientApp/Ambient/ProactiveExecutor.swift`

### 1.3 HIGH — No listening indicator on Lock Screen / Control Center
**Requirement**: "A clear, accessible 'Pause Listening' control is always available (Lock Screen widget, Control Center toggle, in-app button)."  
**Current state**: In-app pause button exists. No Lock Screen widget, no Control Center toggle, no Live Activity.  
**Gap**: iOS Lock Screen / Control Center integration is entirely missing.  
**Files**: None exist yet.

### 1.4 HIGH — No notifications when actions are auto-executed
**Requirement**: "Users open the app to see what the system has inferred or prepared on their behalf."  
**Current state**: Actions are silently added to the store. If the app is backgrounded, the user has no way to know something was created until they open the app.  
**Gap**: Should send a local notification like "✅ Created reminder: Send report to Sarah" so the user knows to review.  
**Files**: `ios/AmbientApp/Ambient/ProactiveExecutor.swift`

### 1.5 MEDIUM — Edit action not implemented in the iOS UI
**Requirement**: Users can "Edit" an action plan.  
**Current state**: `AmbientItemRow` and `AmbientItemDetailView` have Keep/Undo/Execute/Discard buttons but no Edit button. The server model supports `FeedbackAction.EDIT` with `edited_params`, but there's no UI to modify the title, deadline, or notes before confirming.  
**Gap**: No editing flow in the client.  
**Files**: `ios/AmbientApp/Views/AmbientItemRow.swift`, `ios/AmbientApp/Views/AmbientItemDetailView.swift`

### 1.6 MEDIUM — No transcript history view
**Requirement**: "Provide a visible log of: What was captured"  
**Current state**: `PrivacyView` mentions transcripts are deleted within 60s, but there's no way to view the raw transcript log. The server stores `transcript_history` per session but doesn't expose it. `AmbientListeningManager.lastTranscript` only holds the most recent segment.  
**Gap**: No UI for viewing transcript history.  
**Files**: `ios/AmbientApp/Views/PrivacyView.swift`

### 1.7 LOW — No data export
**Requirement**: Privacy section should support "Export data option."  
**Current state**: `PrivacyView` has delete but no export.  
**Gap**: Missing export-to-file or share sheet functionality.  
**Files**: `ios/AmbientApp/Views/PrivacyView.swift`

---

## 2. Weak Tests

### 2.1 No server integration tests (WebSocket lifecycle)
**Current**: `test_e2e.py` is a manual script, not a pytest test. It requires a running server.  
**Gap**: No automated test for WebSocket connect → send audio → receive transcript → receive action plan → feedback → disconnect. Should use FastAPI's `TestClient` with `WebSocketTestSession`.

### 2.2 No test for the auth rejection path
**Current**: API key auth is implemented but untested.  
**Gap**: No test verifying that an invalid API key results in a 4001 close code.

### 2.3 No test for concurrent sessions
**Current**: `sessions` dict is global mutable state. No test verifies two simultaneous WebSocket connections don't corrupt each other's data.  
**Gap**: Missing concurrency test.

### 2.4 No test for extraction with actual OpenAI call (even mocked)
**Current**: `test_extraction.py` tests `_parse_extraction_response` (the parser) but not `extract_actions` (the full function that calls OpenAI).  
**Gap**: Should mock `AsyncOpenAI` and test the full extraction flow including error handling, empty transcript, and API timeout.

### 2.5 No test for AmbientSession._handle_transcript → _run_extraction pipeline
**Current**: Server's main processing pipeline (transcript → buffer → extraction → plan → send) has zero test coverage. Only the individual components are tested.  
**Gap**: Missing integration-level test for the pipeline.

### 2.6 TranscriptBuffer tests don't cover multiple consecutive flushes
**Current**: Tests cover single flush and auto-flush, but not the sequence: add segments → flush → add more → flush again.  
**Gap**: Missing state continuity test.

---

## 3. Performance Risks

### 3.1 Whisper model loaded per session
**Current**: `AmbientTranscriber.start()` calls `get_model()` which is cached globally, so this is actually OK for single-server deployments. But the model lives in GPU memory (~75MB for tiny.en) and is never unloaded.  
**Risk**: Memory pressure if the server runs alongside other GPU workloads.

### 3.2 LLM extraction called every 45 seconds, always
**Current**: Every 45s of non-silence audio triggers an OpenAI API call. Even if the conversation is just background noise that Whisper transcribes as gibberish.  
**Risk**: Unnecessary API costs. Should add a minimum transcript quality/length threshold before calling the LLM.

### 3.3 ActionPlan objects accumulate in memory forever
**Current**: `session.action_plans` dict only grows, never shrinks. On a long-running session (hours), this is a memory leak.  
**Risk**: Memory growth proportional to session duration.

### 3.4 RollbackStore on iOS has no size limit
**Current**: Entries accumulate indefinitely. Old confirmed/undone entries are never cleaned up.  
**Risk**: File grows unbounded over weeks of use.

### 3.5 PCM resampling is naive
**Current**: `processAudio` does nearest-neighbor downsampling from device sample rate to 16kHz. This introduces aliasing artifacts that degrade Whisper accuracy.  
**Risk**: Lower transcription quality than necessary. Should use proper anti-aliased resampling (e.g., linear interpolation at minimum).

---

## 4. Remaining TODOs / Placeholders

### 4.1 `sk-not-configured` fallback API key
**File**: `server/extraction.py:64`  
**Issue**: When no API key is set, the OpenAI client is created with `sk-not-configured`. The first extraction call will fail with an auth error, which is caught and logged — but the user gets no UI feedback that the server isn't properly configured.  
**Suggestion**: Add a startup health check that warns if `OPENAI_API_KEY` is empty.

### 4.2 Server has no graceful shutdown
**File**: `server/main.py`  
**Issue**: No `@app.on_event("shutdown")` handler. Active transcription sessions won't be cleaned up if the server is killed.

### 4.3 No rate limiting on WebSocket or REST endpoints
**File**: `server/main.py`  
**Issue**: A malicious client can flood the server with audio data or feedback requests.

---

## 5. Architectural Inconsistencies

### 5.1 Dual state tracking: server and client both track execution status
**Issue**: The server's `ActionPlan.execution_status` and the iOS `AmbientActionItem.executionStatus` track the same state independently. Feedback from the client updates the server, but if the client crashes before sending feedback, the states diverge permanently.  
**Impact**: No single source of truth for action lifecycle.  
**Suggestion**: Either make the server authoritative (client always fetches current state) or make the client authoritative (server is stateless after sending the plan).

### 5.2 Sessions are ephemeral — all state lost on disconnect
**Issue**: When the WebSocket disconnects, `sessions.pop(session_id)` deletes all action plans and transcript history. If the user's phone sleeps and reconnects, all pending actions are gone from the server side.  
**Impact**: Client must be the sole source of truth (which it currently is, via AmbientStore), but the server's `/items` endpoint is then misleading since it only shows items from active sessions.  
**Suggestion**: Either persist server-side state to disk, or remove the `/items` REST endpoint (it gives a false impression of persistence).

### 5.3 AmbientListeningManager.wsClient is `let` but publicly accessible
**File**: `ios/AmbientApp/Ambient/AmbientListeningManager.swift`  
**Issue**: `let wsClient = AmbientWebSocketClient()` is not private. External code could call `wsClient.connect()` or `wsClient.disconnect()` directly, bypassing the manager's state machine.  
**Suggestion**: Make it `private let`.

### 5.4 AppModel uses force-unwrapped `proactiveExecutor`
**File**: `ios/AmbientApp/AppModel.swift`  
**Issue**: `private(set) var proactiveExecutor: ProactiveExecutor!` — the `!` force-unwrap is necessary because `self` isn't available during property init, but it's a code smell. If anyone accesses `proactiveExecutor` before `init()` completes, it crashes.  
**Suggestion**: Use a two-phase init or `@ObservationIgnored lazy var` (which was attempted earlier but has its own issues with `@Observable`).

### 5.5 Config is class-level constants, not instance
**File**: `server/config.py`  
**Issue**: `AmbientConfig` uses class-level attributes, read once at import time. Environment variable changes after import are not reflected. This is fine for most deployments but prevents runtime config reloading.

---

## 6. Summary of Recommended Implementation Priority

| Priority | Item | Effort |
|----------|------|--------|
| **P0** | Wire video chat to actually generate AI responses (1.1) | Large |
| **P0** | Wire auto-execute toggle to ProactiveExecutor (1.2) | Small |
| **P1** | Add local notifications on auto-execute (1.4) | Small |
| **P1** | Add automated WebSocket integration test (2.1) | Medium |
| **P1** | Add minimum transcript length before LLM call (3.2) | Small |
| **P1** | Clean up old action plans from server memory (3.3) | Small |
| **P2** | Add Edit UI for action plans (1.5) | Medium |
| **P2** | Mock-based test for extract_actions (2.4) | Medium |
| **P2** | Add RollbackStore cleanup of old entries (3.4) | Small |
| **P2** | Make wsClient private (5.3) | Trivial |
| **P3** | Lock Screen widget / Control Center toggle (1.3) | Large |
| **P3** | Transcript history view (1.6) | Medium |
| **P3** | Data export (1.7) | Small |
| **P3** | Rate limiting (4.3) | Medium |
| **P3** | Proper PCM resampling (3.5) | Medium |
