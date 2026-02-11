# Ambient Listening Intelligence Server

Real-time ambient audio → transcription → action extraction → proactive execution.

## Quick Start

```bash
# 1. Copy environment config
cp .env.example .env
# Edit .env and set your OPENAI_API_KEY

# 2. Install dependencies
pip install -r requirements.txt

# 3. Start the server
python main.py
```

The server will start on `http://localhost:8200`.

## Architecture

```
iOS App (audio capture)
    │
    │ PCM 16kHz mono int16 via WebSocket
    ▼
┌──────────────────────────────────────┐
│  Ambient Server                      │
│  ┌──────────┐  ┌──────────────────┐ │
│  │WhisperFlow│→ │ LLM Extraction  │ │
│  │   STT    │  │ (OpenAI API)    │ │
│  └──────────┘  └────────┬─────────┘ │
│                         │            │
│                ┌────────▼─────────┐  │
│                │ Action Planner   │  │
│                │ + Confidence     │  │
│                │ + Deduplication  │  │
│                └────────┬─────────┘  │
│                         │            │
│                    ActionPlan        │
│                   (sent to client)   │
└──────────────────────────────────────┘
    │
    ▼
iOS App (ProactiveExecutor)
    → Creates reminder / calendar event
    → User sees "Done: ..." with Undo button
```

## Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/ws/ambient` | WebSocket | Real-time audio streaming + action plans |
| `/health` | GET | Server health check |
| `/items` | GET | List all detected action plans |
| `/items/{id}/feedback` | POST | Submit keep/undo/discard feedback |

## WebSocket Protocol

### Client → Server

**Binary messages**: PCM audio chunks (16kHz, mono, int16)

**JSON messages**:
```json
{"type": "pause"}
{"type": "resume"}
{"type": "feedback", "payload": {"action_plan_id": "...", "action": "keep|undo|discard|execute"}}
```

### Server → Client

```json
{"type": "transcript", "payload": {"text": "...", "is_partial": true, "latency_ms": 123.4}}
{"type": "action_plan", "payload": { /* ActionPlan object */ }}
{"type": "error", "payload": {"message": "..."}}
```

## Configuration

See `.env.example` for all configuration options.

Key settings:
- `AUTO_EXECUTE_THRESHOLD=0.8` — Actions above this confidence are auto-executed
- `SUGGESTION_THRESHOLD=0.5` — Actions above this are shown as suggestions
- `TRANSCRIPT_BUFFER_SECONDS=45` — How much transcript to accumulate before extraction
- `UNDO_WINDOW_SECONDS=1800` — How long users can undo (30 min default)

## Dependencies

- **WhisperFlow** (included in repo at `whisper-flow-main/`) — Streaming speech-to-text
- **OpenAI API** — LLM extraction of actionable items from conversation
- **FastAPI + uvicorn** — WebSocket server
