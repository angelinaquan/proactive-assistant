# IMPLEMENTATION_PLAN.md

Prioritized list of remaining work items. Completed items are removed.
Last updated after full specs-vs-code comparison.

---

## P2 — Should Do

- **Edit UI for action plans (spec: Keep/Edit/Undo)**: Server supports `FeedbackAction.EDIT` with `edited_params` but iOS has no Edit button or editing sheet. `AmbientItemRow` and `AmbientItemDetailView` need an Edit flow: tap Edit → sheet with editable title/deadline/notes → confirm → update item + send feedback. _Files: `ios/.../AmbientItemRow.swift`, `ios/.../AmbientItemDetailView.swift`_

- **Mocked test for `extract_actions` full function**: `test_extraction.py` only tests `_parse_extraction_response` (the JSON parser). The `extract_actions` async function (which calls OpenAI, injects date/time, handles errors) has zero test coverage. Need to mock `AsyncOpenAI` and test: success path, empty transcript, API error, timeout. _File: `server/tests/test_extraction.py`_

- **RollbackStore cleanup of old entries**: Entries accumulate indefinitely. Old confirmed/undone entries are never pruned. Should add `cleanupOldEntries(olderThan:)` and call it periodically (e.g., remove entries older than 7 days). _File: `ios/.../RollbackStore.swift`_

- **Make `wsClient` private in AmbientListeningManager**: `let wsClient = AmbientWebSocketClient()` is not private — external code could bypass the manager's state machine by calling connect/disconnect directly. Change to `private let`. _File: `ios/.../AmbientListeningManager.swift`_

- **`test_e2e.py` collected by pytest, fails without running server**: Running `pytest` from `ambient-server/` root collects `test_e2e.py` which requires a live server. This will fail in CI. Either move it to a separate directory, mark it with `@pytest.mark.skip`/`@pytest.mark.e2e`, or add a `conftest.py` to exclude it. _File: `test_e2e.py`_

- **Auth rejection test claim stale in plan**: 2.2 said "untested" but `test_server_integration.py::test_websocket_auth_rejection` exists and covers this. Already resolved — just stale tracking.

- **Consecutive buffer flush test**: `TranscriptBuffer` has no test for the sequence: add segments → flush → add more → flush again (verifying state resets correctly between flushes). _File: `server/tests/test_transcription.py`_

---

## P3 — Nice to Have

- **Lock Screen widget / Control Center pause toggle**: Spec requires "Pause Listening" in Lock Screen widget and Control Center. Would need iOS WidgetKit / LiveActivity integration. Large effort, iOS-only. _Files: new widget extension target_

- **Transcript history view**: Spec says "visible log of what was captured." `AmbientListeningManager.lastTranscript` only holds the most recent segment. Server stores `transcript_history` per session but doesn't expose it via REST. Need: server `GET /transcripts?session_id=` endpoint + iOS transcript log view in PrivacyView. _Files: `server/main.py`, `ios/.../PrivacyView.swift`_

- **Data export**: Spec mentions "Export data option" in privacy section. No export/share functionality exists. Add share sheet for action items JSON export. _File: `ios/.../PrivacyView.swift`_

- **Rate limiting on endpoints**: No rate limiting on WebSocket audio data or REST endpoints. A malicious client could flood the server. Consider `slowapi` or manual token bucket. _File: `server/main.py`_

- **Proper PCM resampling**: `processAudio` uses nearest-neighbor downsampling (pick closest sample). This introduces aliasing that degrades Whisper accuracy. Should use at minimum linear interpolation, ideally `vDSP.downsample` from Accelerate framework. _File: `ios/.../AmbientListeningManager.swift`_

- **Graceful server shutdown**: No `@app.on_event("shutdown")` or `lifespan` handler. Active transcription sessions won't be cleaned up on SIGTERM. _File: `server/main.py`_

- **Startup health check for missing API key**: When `OPENAI_API_KEY` is empty, the server starts but all extraction/chat calls fail silently with logged errors. Should warn on startup and optionally in `/health` response. _File: `server/main.py`, `server/config.py`_

- **Transcript auto-deletion timer**: Spec says "Transcripts processed and deleted within 60 seconds." `PrivacyView` claims this, but server stores `transcript_history` indefinitely (capped at 100). No actual 60-second deletion timer exists on either server or client. Need to implement timed cleanup or clarify the spec. _Files: `server/main.py`, spec_

---

## Architectural Notes (not blocking, for awareness)

- **Dual state tracking**: Server and client both track `execution_status` independently. Client (AmbientStore) is the de facto source of truth. Server state is ephemeral (lost on disconnect). The `/items` endpoint only shows active sessions — acceptable but should be documented in API docs.

- **Force-unwrapped `proactiveExecutor`**: `AppModel` uses `ProactiveExecutor!` — required because `self` isn't available during property init with `@Observable`. Acceptable given init always sets it before any access.

- **Config read-once**: `AmbientConfig` reads env vars at import time. Fine for production; won't pick up runtime changes. Acceptable.
