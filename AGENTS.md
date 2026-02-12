## Build & Run

- **Primary code**: `ambient-server/` (self-contained — server + iOS app)
- **Server (Python)**: `ambient-server/server/`
- **iOS app (Swift)**: `ambient-server/ios/AmbientApp/`
- **Reference codebases** (read-only, not used at runtime): `openclaw-main/`, `whisper-flow-main/`

### Server Setup

```bash
cd ambient-server
cp .env.example .env          # Set OPENAI_API_KEY
pip install -r requirements.txt
```

### Run Server

```bash
cd ambient-server/server
python3 main.py               # Starts on port 8200
# OR
cd ambient-server && ./run.sh -run
```

### iOS App

```bash
cd ambient-server/ios
xcodegen generate              # Requires: brew install xcodegen
open AmbientApp.xcodeproj
```

iOS 18+, Swift 6, Xcode 16. No external Swift package dependencies.

## Validation

Run these after implementing to get immediate feedback:

- Tests: `cd ambient-server/server && python3 -m pytest tests/ -v`
- Quick tests: `cd ambient-server/server && python3 -m pytest tests/ -q`
- Single file: `cd ambient-server/server && python3 -m pytest tests/test_chat.py -v`
- E2E (requires running server): `cd ambient-server && python3 test_e2e.py`
- Typecheck: N/A (Python — use mypy if desired: `mypy ambient-server/server/`)
- Lint: N/A (no linter configured — use `ruff check ambient-server/server/` if desired)
- Swift syntax check: No Xcode on this VM. Verify brace balance with: `python3 -c "..."`

## Operational Notes

- Server requires `OPENAI_API_KEY` in `.env` for LLM extraction and chat. Without it, extraction returns empty results and chat returns a fallback message.
- Whisper model `tiny.en.pt` is bundled in `server/models/`. Falls back to download if missing.
- Tests mock heavy imports (torch, whisper) where TranscriptBuffer is tested standalone.
- FastAPI TestClient requires `httpx<0.28` (compatibility with starlette 0.32).
- WebSocket auth: set `AMBIENT_API_KEY` in `.env`; clients pass `?key=` query param.

### Codebase Patterns

- **Server modules**: config → models → confidence → extraction → action_planner → chat → transcription → main
- **iOS architecture**: AppModel (central) → AmbientListeningManager (audio+WS) → ProactiveExecutor (act first) → RollbackStore (undo)
- **iOS views**: ContentView → AmbientTimelineView → AmbientItemRow/DetailView; VideoChatView (standalone)
- **Testing**: pytest with `sys.path.insert` for imports. Async tests use `pytest-asyncio`. Integration tests use `FastAPI TestClient`.
- **Persistence**: iOS stores JSON files in documents dir (AmbientStore, RollbackStore). Server state is ephemeral (in-memory per session).
