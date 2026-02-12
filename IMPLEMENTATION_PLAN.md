# IMPLEMENTATION_PLAN.md

All prioritized items have been implemented. Only one deferred item remains.

---

## Deferred

- **Lock Screen widget / Control Center pause toggle**: Requires iOS WidgetKit/ActivityKit target extension which cannot be created or verified without Xcode. Documented as future work when building on a Mac with Xcode 16+. _Would need: new widget extension target in project.yml, WidgetBundle, AppIntent for toggle._

---

## Architectural Notes (for awareness, not blocking)

- **Dual state tracking**: Server and client both track `execution_status` independently. Client (AmbientStore) is the source of truth. Server state is ephemeral. Acceptable for current architecture.

- **Force-unwrapped `proactiveExecutor`**: `AppModel` uses `ProactiveExecutor!` — required by `@Observable` init constraints. Always set before access. Acceptable.

- **Config read-once**: `AmbientConfig` reads env vars at import. Fine for production.

---

## Completed (for reference)

All P0, P1, P2, P3 items implemented across 25+ commits. 116 server tests passing.

Key completions:
- ✅ Video chat AI response loop (speech → /chat → TTS → avatar)
- ✅ Auto-execute toggle wired to ProactiveExecutor
- ✅ Local notifications on auto-execute
- ✅ Edit UI for action plans
- ✅ Mocked extract_actions tests
- ✅ RollbackStore cleanup of old entries
- ✅ WebSocket integration tests
- ✅ Min transcript length gate
- ✅ Server memory cleanup
- ✅ Transcript history endpoint + auto-deletion (60s)
- ✅ Data export (JSON share sheet)
- ✅ Rate limiting (60 req/min)
- ✅ Graceful shutdown
- ✅ API key health check
- ✅ Linear interpolation PCM resampling
- ✅ test_e2e.py excluded from pytest
- ✅ wsClient made private
- ✅ Consecutive buffer flush test
