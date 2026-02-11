# Ambient Listening Intelligence System

A proactive ambient intelligence system. Always-listening iOS app + backend server that captures conversation, extracts actionable items, **immediately executes them** (creates reminders, calendar events), then presents completed actions for user confirmation or undo.

## Architecture

```
┌──────────────────────────────────────┐
│  iOS App (ambient-server/ios/)       │
│  ┌────────────┐  ┌───────────────┐  │
│  │ Audio      │  │ Proactive     │  │
│  │ Capture    │→ │ Executor      │  │
│  │ + VAD      │  │ (act first)   │  │
│  └─────┬──────┘  └───────┬───────┘  │
│        │ PCM audio        │ Creates  │
│        │ via WebSocket    │ reminders│
│        ▼                  ▼          │
│  ┌────────────────────────────────┐  │
│  │ Review Timeline + Undo UI     │  │
│  └────────────────────────────────┘  │
└────────┼─────────────────────────────┘
         │
         ▼
┌──────────────────────────────────────┐
│  Server (ambient-server/server/)     │
│  ┌──────────┐  ┌──────────────────┐ │
│  │ Whisper   │→ │ LLM Extraction  │ │
│  │ STT      │  │ + Action Planner│ │
│  └──────────┘  └──────────────────┘ │
└──────────────────────────────────────┘
```

## Quick Start

### Server

```bash
# Setup and test
cp .env.example .env       # Set OPENAI_API_KEY
./run.sh -local            # Create venv, install deps, run tests

# Or manually:
cd server
pip install -r ../requirements.txt
python3 -m pytest tests/ -v
python3 main.py            # Starts on port 8200
```

### iOS App

```bash
# Generate Xcode project (requires XcodeGen)
cd ios
xcodegen generate

# Open in Xcode
open AmbientApp.xcodeproj
```

In the app:
1. Settings → enter server host (e.g. `192.168.1.100`) and port (`8200`)
2. Enable "Ambient Listening"
3. Speak naturally — detected actions appear in the timeline
4. Auto-executed items show Keep/Undo buttons (30-minute undo window)

## Structure

```
ambient-server/
├── server/                     # Python backend (self-contained)
│   ├── main.py                 # FastAPI WebSocket server
│   ├── transcription.py        # Whisper STT (inlined, no external deps)
│   ├── extraction.py           # LLM action extraction
│   ├── action_planner.py       # Confidence scoring + action planning
│   ├── confidence.py           # Auto-execute threshold logic
│   ├── models.py               # Pydantic data models
│   ├── config.py               # Configuration
│   ├── models/tiny.en.pt       # Whisper model file
│   └── tests/                  # 52 unit tests
├── ios/                        # Standalone iOS app
│   ├── project.yml             # XcodeGen project config
│   └── AmbientApp/
│       ├── App.swift           # Entry point
│       ├── AppModel.swift      # Central app model
│       ├── ContentView.swift   # Main UI + settings
│       ├── Models/             # AmbientActionItem
│       ├── Services/           # RemindersService, CalendarService
│       ├── Ambient/            # Core: Manager, WebSocket, Store, Executor
│       └── Views/              # Timeline, Detail, Avatar, VideoChat
├── requirements.txt
├── run.sh
├── .env.example
└── README.md
```

## How It Works

1. **Hear**: iOS app captures audio, applies VAD, streams speech to server
2. **Transcribe**: Server runs Whisper STT in real-time
3. **Extract**: LLM identifies tasks, reminders, commitments, deadlines
4. **Act**: High-confidence items (≥80%) auto-create reminders/calendar events
5. **Review**: User sees "✅ Created reminder: X" with Keep/Undo buttons
6. **Undo**: One tap to reverse within 30-minute window

## Configuration

See `.env.example` for all server settings:
- `AUTO_EXECUTE_THRESHOLD=0.8` — Minimum confidence for auto-execution
- `SUGGESTION_THRESHOLD=0.5` — Minimum confidence to show as suggestion
- `UNDO_WINDOW_SECONDS=1800` — Undo window (30 min default)
- `TRANSCRIPT_BUFFER_SECONDS=45` — Transcript accumulation before extraction
