# Product Specification: Ambient Listening AI

## Vision

An always-listening iOS application that acts as a silent, proactive assistant. Unlike traditional voice assistants, this system never interrupts or speaks unless explicitly engaged. It passively captures conversational context and identifies actionable items such as commitments, follow-ups, reminders, and notes.

The core experience is **quiet intelligence**: no notifications by default, no public interjections, and no social friction. The app functions as an invisible chief of staff — organizing, drafting, and tracking tasks without disrupting daily life.

## Core Philosophy: Act First, Confirm Later

The system is **proactive** — it executes actions immediately, then presents completed work to the user for confirmation or undo. This is NOT a traditional "propose and wait" assistant.

Flow:
1. **Hear**: "I need to send that report to Sarah by tomorrow morning"
2. **Act**: Immediately creates a reminder → "Send report to Sarah" due tomorrow 9:00 AM
3. **Present**: User opens app → sees "✅ Created reminder: Send report to Sarah — tomorrow 9am"
4. **Confirm**: User can **Keep** ✓ | **Edit** ✏️ | **Undo** ↩️

Only high-confidence items (≥80%) are auto-executed. Lower-confidence items are held as suggestions.

## Core Components

### 1. Audio Capture Layer (iOS)
- Continuous background audio capture using AVAudioEngine
- On-device Voice Activity Detection (VAD) using RMS levels
- Only speech segments streamed to backend (filters silence)
- PCM 16kHz mono int16 format
- Rolling buffer: raw audio never stored, only transcripts
- User-controlled pause that immediately halts recording

### 2. Backend Intelligence Server (Python)
- Real-time speech-to-text using OpenAI Whisper (inlined, self-contained)
- Tumbling-window transcription with segment detection
- LLM-based extraction of actionable items (OpenAI API)
- Action planner with confidence scoring and deduplication
- WebSocket for audio streaming + REST for chat
- Configurable thresholds: auto-execute ≥0.8, suggestion ≥0.5, discard <0.5

### 3. Proactive Execution Engine (iOS)
- `ProactiveExecutor`: Creates reminders/calendar events via EventKit
- `RollbackStore`: Tracks system identifiers for undo (30-min window)
- `AmbientStore`: Persistent JSON storage with debounced writes
- Respects user's auto-execute toggle in Settings
- Sends local notification after each auto-executed action

### 4. Review & Control Interface (iOS)
- **Timeline view**: Done (auto-executed) / Suggestions / Confirmed sections
- **Audit trail**: Heard → Interpreted → Action Taken
- **One-tap actions**: Keep, Undo, Execute, Discard
- **Privacy controls**: Delete today, delete all, privacy info
- **Pause button**: Pulsing indicator, one-tap pause/resume

### 5. AI Video Chat (iOS + Server)
- Full-screen view with animated AI avatar
- On-device speech recognition (SFSpeechRecognizer)
- Silence detection triggers server call (POST /chat)
- Server returns AI response text
- AVSpeechSynthesizer plays response (system TTS)
- Avatar animates during speech (glow rings synced to audio)
- Conversation history maintained per session
- Mic mute toggle + end call button

## Privacy & User Control

- Raw audio is NEVER stored — only transcripts
- Transcripts processed and deleted within 60 seconds
- All data stored locally on device
- One-tap pause stops all capture immediately
- Delete today's items or entire history
- Clear listening indicator when active
- API key authentication on WebSocket

## Technical Stack

- **Server**: Python 3.12, FastAPI, OpenAI Whisper, OpenAI API, Pydantic
- **iOS**: Swift 6, iOS 18+, SwiftUI, AVAudioEngine, SFSpeechRecognizer, EventKit, AVSpeechSynthesizer
- **Protocol**: WebSocket (audio streaming), REST (chat, health, items)
- **Persistence**: JSON files on iOS, ephemeral sessions on server

## Action Types

| Type | Auto-executable | iOS Service |
|------|----------------|-------------|
| Reminder | ✅ | EventKit (EKReminder) |
| Calendar Event | ✅ | EventKit (EKEvent) |
| Follow-up | ✅ | EventKit (as reminder) |
| Commitment | ✅ | EventKit (as reminder) |
| Note | ❌ (local only) | AmbientStore |
| Draft Message | ❌ (suggestion) | AmbientStore |

## Confidence Thresholds

| Score | Classification | Behavior |
|-------|---------------|----------|
| ≥ 0.8 | High | Auto-execute immediately |
| 0.5–0.8 | Medium | Show as suggestion |
| < 0.5 | Low | Discard silently |

Heuristic adjustments: +0.05 for deadline, +0.03 for named people, +0.02 for reminder/calendar type, -0.05 for short titles, -0.05 for notes/drafts, -0.03 for no description+no deadline.
