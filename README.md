# Ambient Listening AI

A proactive ambient intelligence system. An always-listening iOS app + Python backend that captures conversation, extracts actionable items, **immediately creates reminders and calendar events**, then lets users confirm or undo with one tap. Includes AI video chat with an animated avatar.

## How It Works

```
You say: "I need to send that report to Sarah by tomorrow morning"
  ↓
System hears → transcribes → extracts → creates reminder immediately
  ↓
You open the app → "✅ Created: Send report to Sarah — tomorrow 9am"
  ↓
You tap: [Keep ✓] or [Undo ↩️]
```

**Act first, confirm later.** High-confidence items (≥80%) are executed immediately. Lower-confidence items appear as suggestions for you to approve.

## Quick Start

### 1. Start the Server

```bash
cd ambient-server

# Configure
cp .env.example .env
# Edit .env → set OPENAI_API_KEY (required for LLM extraction)
# Optionally set AMBIENT_API_KEY for authentication

# Install dependencies
pip install -r requirements.txt

# Run tests (52 unit tests)
cd server && python3 -m pytest tests/ -v && cd ..

# Start the server
./run.sh -run
# Server runs on http://localhost:8200
```

Verify it's running:
```bash
curl http://localhost:8200/health
# → {"status":"ok","service":"ambient-intelligence","version":"1.0.0"}
```

### 2. Build the iOS App

```bash
cd ambient-server/ios

# Generate Xcode project (requires XcodeGen: brew install xcodegen)
xcodegen generate

# Open in Xcode
open AmbientApp.xcodeproj
```

Build and run on your iPhone (iOS 18+). Then:

1. Open **Settings** (gear icon)
2. Enter your server's IP address (e.g., `192.168.1.100`) and port (`8200`)
3. If you set `AMBIENT_API_KEY`, enter it in the API Key field
4. Toggle **Ambient Listening** on
5. Speak naturally — actions appear in the timeline

### 3. Run End-to-End Test

```bash
# With the server running:
cd ambient-server
python3 test_e2e.py
```

This tests WebSocket connectivity, audio streaming, transcription, extraction, and action planning.

## Architecture

```
┌──────────────────────────────────────┐
│  iOS App (ambient-server/ios/)       │
│  ┌────────────┐  ┌───────────────┐  │
│  │ Audio      │→ │ Proactive     │  │
│  │ Capture    │  │ Executor      │  │
│  │ + VAD      │  │ (act first)   │  │
│  └─────┬──────┘  └───────┬───────┘  │
│        │ WebSocket        │ Creates  │
│        │                  │ reminders│
│        ▼                  ▼          │
│  ┌────────────────────────────────┐  │
│  │ Review Timeline + Undo        │  │
│  └────────────────────────────────┘  │
└────────┼─────────────────────────────┘
         ▼
┌──────────────────────────────────────┐
│  Server (ambient-server/server/)     │
│  ┌──────────┐  ┌──────────────────┐ │
│  │ Whisper   │→ │ LLM Extraction  │ │
│  │ STT      │  │ + Action Planner│ │
│  └──────────┘  └──────────────────┘ │
└──────────────────────────────────────┘
```

## Project Structure

```
ambient-server/                  # ← Everything is here (self-contained)
├── server/                      # Python backend
│   ├── main.py                  # FastAPI WebSocket server
│   ├── transcription.py         # Whisper speech-to-text (inlined)
│   ├── extraction.py            # LLM action extraction
│   ├── action_planner.py        # Confidence scoring + planning
│   ├── models/tiny.en.pt        # Bundled Whisper model
│   └── tests/                   # 52 unit tests
├── ios/                         # Standalone iOS app
│   ├── project.yml              # XcodeGen config
│   └── AmbientApp/
│       ├── App.swift            # Entry point
│       ├── AppModel.swift       # Central model
│       ├── ContentView.swift    # Main UI + Settings
│       ├── Services/            # RemindersService, CalendarService
│       ├── Ambient/             # Core engine
│       └── Views/               # Timeline, Avatar, VideoChat
├── test_e2e.py                  # End-to-end integration test
├── requirements.txt
├── run.sh
└── .env.example
```

The `openclaw-main/` and `whisper-flow-main/` directories are reference codebases. The ambient system in `ambient-server/` is fully self-contained and does not depend on them.

## Features

### Proactive Execution
- Detects commitments, tasks, deadlines, follow-ups from natural conversation
- **Immediately creates** iOS reminders and calendar events for high-confidence items
- 30-minute undo window — one tap to reverse any action
- Lower-confidence items shown as suggestions for manual approval

### Review Timeline
- **Done** section: auto-executed items with Keep/Undo buttons
- **Suggestions** section: items awaiting your decision
- **Confirmed** section: actions you've kept
- Full audit trail: Heard → Interpreted → Action Taken

### AI Video Chat
- Animated AI avatar with glow rings synced to audio levels
- On-device speech recognition (SFSpeechRecognizer)
- Live transcript overlay
- Mic mute toggle + end call button

### Privacy
- Raw audio is never stored — only transcripts
- Transcripts processed and deleted within 60 seconds
- All data stored locally on device
- One-tap pause stops all capture immediately
- Delete today's items or entire history

## Configuration

Key settings in `.env`:

| Variable | Default | Description |
|----------|---------|-------------|
| `OPENAI_API_KEY` | (required) | API key for LLM extraction |
| `OPENAI_MODEL` | `gpt-4o-mini` | Model for action extraction |
| `AMBIENT_API_KEY` | (empty) | Authentication key for clients |
| `AUTO_EXECUTE_THRESHOLD` | `0.8` | Min confidence for auto-execution |
| `SUGGESTION_THRESHOLD` | `0.5` | Min confidence to show as suggestion |
| `UNDO_WINDOW_SECONDS` | `1800` | Undo window (30 min) |
| `TRANSCRIPT_BUFFER_SECONDS` | `45` | Seconds of transcript before extraction |
