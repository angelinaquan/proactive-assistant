# Architecture

## Directory Structure

```
ambient-server/                  # Self-contained (no external deps)
├── server/                      # Python backend
│   ├── main.py                  # FastAPI server + WebSocket endpoint
│   ├── config.py                # Environment-based configuration
│   ├── models.py                # Pydantic models (ActionPlan, etc.)
│   ├── transcription.py         # Whisper STT + streaming loop + TranscriptBuffer
│   ├── extraction.py            # LLM extraction of actionable items
│   ├── action_planner.py        # Confidence scoring + action plan creation
│   ├── confidence.py            # Score adjustment heuristics
│   ├── chat.py                  # Conversational AI for video chat
│   ├── models/tiny.en.pt        # Bundled Whisper model
│   └── tests/                   # 108 pytest tests
├── ios/                         # Standalone iOS app
│   ├── project.yml              # XcodeGen config
│   └── AmbientApp/
│       ├── App.swift            # @main entry point
│       ├── AppModel.swift       # Central @Observable model
│       ├── ContentView.swift    # Main UI + inline SettingsView
│       ├── Models/              # AmbientActionItem, AnyCodableValue
│       ├── Services/            # RemindersService, CalendarService, ChatClient
│       ├── Ambient/             # Core: ListeningManager, WebSocketClient,
│       │                        #   ProactiveExecutor, AmbientStore, RollbackStore
│       └── Views/               # Timeline, Detail, Avatar, VideoChat, Pause, Privacy
├── test_e2e.py                  # Manual end-to-end test (requires running server)
├── requirements.txt
├── run.sh
└── .env.example
```

## Data Flow

```
  iOS Mic → AVAudioEngine → VAD filter → WebSocket
                                            │
                                            ▼
  Server: Whisper STT → TranscriptBuffer → LLM Extraction → ActionPlanner
                                                                │
                                            ┌───────────────────┤
                                            ▼                   ▼
                                      auto_execute=true   auto_execute=false
                                            │                   │
                                            ▼                   ▼
  iOS: ProactiveExecutor.execute()    Store as suggestion
         │
         ├─ RemindersService.add()
         ├─ CalendarService.add()
         └─ RollbackStore.record()
              │
              ▼
         Local notification
         "✅ Action Created"
              │
              ▼
         User reviews in timeline
         Keep / Edit / Undo
```

## Server Endpoints

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/ws/ambient` | WebSocket | Audio streaming + action plans |
| `/chat` | POST | Video chat AI responses |
| `/chat/clear` | POST | Clear chat history |
| `/health` | GET | Server health check |
| `/items` | GET | List action plans (active sessions only) |
| `/items/{id}/feedback` | POST | Submit keep/undo/discard |

## Key Design Decisions

1. **Act first, confirm later** — high-confidence items auto-executed
2. **30-minute undo window** — reversible via EventKit delete
3. **System TTS** — AVSpeechSynthesizer (no external TTS dependency)
4. **Ephemeral server state** — client is source of truth
5. **Self-contained** — no dependency on openclaw-main or whisper-flow-main
