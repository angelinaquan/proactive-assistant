"""
Ambient Listening Intelligence Server.

FastAPI application that accepts real-time audio via WebSocket,
transcribes it using Whisper, extracts actionable items using LLM,
and returns action plans to the iOS client for proactive execution.
"""

from __future__ import annotations

import asyncio
import json
import logging
import uuid
from datetime import datetime, timezone

from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.responses import JSONResponse

from action_planner import ActionPlanner
from chat import ChatRequest, ChatResponse, chat as chat_handler, clear_chat_history
from config import config
from extraction import extract_actions
from models import (
    ActionFeedback,
    ActionPlan,
    ExecutionStatus,
    FeedbackAction,
    TranscriptSegment,
    WSMessage,
    WSMessageType,
)
from transcription import AmbientTranscriber, TranscriptBuffer

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
)
logger = logging.getLogger(__name__)

import time as _time_module
from collections import defaultdict
from contextlib import asynccontextmanager

from fastapi import Request
from fastapi.middleware.cors import CORSMiddleware
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.responses import JSONResponse as StarletteJSONResponse


@asynccontextmanager
async def lifespan(application: FastAPI):
    """Server lifecycle: startup and shutdown."""
    # Startup
    if not config.OPENAI_API_KEY or config.OPENAI_API_KEY == "sk-not-configured":
        logger.warning("⚠️  OPENAI_API_KEY not set — extraction and chat will return fallback responses")
    logger.info("Ambient server started")
    yield
    # Shutdown: clean up all active sessions
    logger.info("Shutting down: cleaning up %d active sessions", len(sessions))
    for session in list(sessions.values()):
        await session.stop_transcription()
    sessions.clear()
    logger.info("Shutdown complete")


app = FastAPI(
    title="Ambient Listening Intelligence Server",
    version="1.0.0",
    description="Real-time ambient audio → transcription → action extraction",
    lifespan=lifespan,
)


# Simple rate limiter: max 60 requests/minute per IP for REST endpoints
_rate_limit_store: dict[str, list[float]] = defaultdict(list)
RATE_LIMIT_MAX = 60
RATE_LIMIT_WINDOW = 60.0


class RateLimitMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next):
        # Only rate-limit REST, not WebSocket
        if request.scope.get("type") == "websocket":
            return await call_next(request)
        client_ip = request.client.host if request.client else "unknown"
        now = _time_module.time()
        # Clean old entries
        _rate_limit_store[client_ip] = [
            t for t in _rate_limit_store[client_ip] if t > now - RATE_LIMIT_WINDOW
        ]
        if len(_rate_limit_store[client_ip]) >= RATE_LIMIT_MAX:
            return StarletteJSONResponse(
                status_code=429,
                content={"error": "Rate limit exceeded. Max 60 requests/minute."},
            )
        _rate_limit_store[client_ip].append(now)
        return await call_next(request)


app.add_middleware(RateLimitMiddleware)

# Global state: action plans indexed by session then by plan ID
sessions: dict[str, "AmbientSession"] = {}


class AmbientSession:
    """Represents an active ambient listening session for one client."""

    def __init__(self, session_id: str, websocket: WebSocket):
        self.session_id = session_id
        self.websocket = websocket
        self.transcriber: AmbientTranscriber | None = None
        self.buffer = TranscriptBuffer()
        self.planner = ActionPlanner()
        self.action_plans: dict[str, ActionPlan] = {}
        self.transcript_history: list[tuple[float, str]] = []  # (timestamp, text)
        self._max_action_plans = 200
        self._max_transcript_history = 100
        self.is_paused = False
        self.created_at = datetime.now(timezone.utc)
        self._loop: asyncio.AbstractEventLoop | None = None
        self._extraction_lock = asyncio.Lock()
        self._context_window: list[str] = []  # Last N segments for context

    async def start_transcription(self) -> None:
        """Start the transcription engine."""
        # Capture the running event loop so the sync callback from the
        # transcriber thread can safely schedule async work.
        self._loop = asyncio.get_running_loop()
        self.transcriber = AmbientTranscriber(
            on_transcript=self._on_transcript_sync,
        )
        await self.transcriber.start()

    async def stop_transcription(self) -> None:
        """Stop the transcription engine."""
        if self.transcriber:
            await self.transcriber.stop()
            self.transcriber = None
        self._loop = None

    def _on_transcript_sync(
        self, text: str, is_partial: bool, latency_ms: float
    ) -> None:
        """Sync callback from transcriber thread — schedules async work on the event loop."""
        loop = self._loop
        if loop is not None and loop.is_running():
            loop.call_soon_threadsafe(
                loop.create_task,
                self._handle_transcript(text, is_partial, latency_ms),
            )

    async def _handle_transcript(
        self, text: str, is_partial: bool, latency_ms: float
    ) -> None:
        """Process a transcript segment."""
        if self.is_paused:
            return

        # Send transcript to client for display
        segment = TranscriptSegment(
            text=text,
            is_partial=is_partial,
            latency_ms=latency_ms,
        )
        await self._send(
            WSMessageType.TRANSCRIPT,
            segment.model_dump(mode="json"),
        )

        # Buffer finalized segments for extraction
        accumulated = self.buffer.add_segment(text, is_partial)
        if accumulated:
            await self._run_extraction(accumulated)

    async def _run_extraction(self, transcript: str) -> None:
        """Run LLM extraction on accumulated transcript."""
        # Skip short/gibberish transcripts to avoid wasting LLM API calls.
        # Whisper often produces very short fragments from background noise.
        MIN_TRANSCRIPT_WORDS = 5
        word_count = len(transcript.split())
        if word_count < MIN_TRANSCRIPT_WORDS:
            logger.debug(
                "Skipping extraction: transcript too short (%d words): %s",
                word_count,
                transcript[:80],
            )
            return

        async with self._extraction_lock:
            try:
                # Build context from recent segments
                context = " ".join(self._context_window[-3:]) if self._context_window else None

                # Extract actionable items
                result = await extract_actions(transcript, context=context)

                # Update context window
                self._context_window.append(transcript)
                if len(self._context_window) > 5:
                    self._context_window.pop(0)

                # Store transcript with timestamp
                import time as _time
                self.transcript_history.append((_time.time(), transcript))

                if not result.items:
                    return

                # Plan actions
                context_window = " ".join(self._context_window)
                plans = self.planner.plan_actions(result, context_window)

                # Send plans to client
                for plan in plans:
                    self.action_plans[plan.id] = plan
                    await self._send(
                        WSMessageType.ACTION_PLAN,
                        plan.model_dump(mode="json"),
                    )
                    logger.info(
                        "Sent action plan: %s (auto_execute=%s)",
                        plan.action_description,
                        plan.auto_execute,
                    )

                # Periodic cleanup to prevent memory growth
                self._cleanup_old_data()

            except Exception as e:
                logger.error("Extraction failed: %s", e)
                await self._send(
                    WSMessageType.ERROR,
                    {"message": f"Extraction error: {str(e)}"},
                )

    async def handle_feedback(self, feedback: ActionFeedback) -> None:
        """Handle user feedback on an action plan."""
        plan = self.action_plans.get(feedback.action_plan_id)
        if not plan:
            logger.warning(
                "Feedback for unknown plan: %s", feedback.action_plan_id
            )
            return

        if feedback.action == FeedbackAction.KEEP:
            plan.execution_status = ExecutionStatus.CONFIRMED
            plan.confirmed_at = datetime.now(timezone.utc)
        elif feedback.action == FeedbackAction.UNDO:
            plan.execution_status = ExecutionStatus.UNDONE
            plan.undone_at = datetime.now(timezone.utc)
        elif feedback.action == FeedbackAction.EDIT:
            if feedback.edited_params:
                plan.action_params.update(feedback.edited_params)
            plan.execution_status = ExecutionStatus.CONFIRMED
            plan.confirmed_at = datetime.now(timezone.utc)
        elif feedback.action == FeedbackAction.DISCARD:
            plan.execution_status = ExecutionStatus.UNDONE
            plan.undone_at = datetime.now(timezone.utc)
        elif feedback.action == FeedbackAction.EXECUTE:
            plan.auto_execute = True
            plan.execution_status = ExecutionStatus.PENDING

        logger.info(
            "Feedback on %s: %s → %s",
            plan.action_description,
            feedback.action.value,
            plan.execution_status.value,
        )

    def _cleanup_old_data(self) -> None:
        """Remove old action plans and transcript entries to prevent memory growth."""
        # Trim action plans: keep most recent N
        if len(self.action_plans) > self._max_action_plans:
            sorted_plans = sorted(
                self.action_plans.items(),
                key=lambda kv: kv[1].detected_at,
            )
            excess = len(sorted_plans) - self._max_action_plans
            for plan_id, _ in sorted_plans[:excess]:
                del self.action_plans[plan_id]
            logger.info("Cleaned up %d old action plans", excess)

        # Auto-delete transcripts older than 60 seconds (per spec)
        import time as _time
        cutoff = _time.time() - 60
        self.transcript_history = [
            (ts, text) for ts, text in self.transcript_history if ts > cutoff
        ]
        # Also cap at max
        if len(self.transcript_history) > self._max_transcript_history:
            self.transcript_history = self.transcript_history[-self._max_transcript_history:]

    async def flush_and_extract(self) -> None:
        """Force flush the transcript buffer and run extraction."""
        accumulated = self.buffer.flush()
        if accumulated:
            await self._run_extraction(accumulated)

    async def _send(self, msg_type: WSMessageType, payload: dict) -> None:
        """Send a WebSocket message to the client."""
        try:
            msg = WSMessage(type=msg_type, payload=payload)
            await self.websocket.send_json(msg.model_dump(mode="json"))
        except Exception as e:
            logger.error("Failed to send WS message: %s", e)


# ---------------------------------------------------------------------------
# WebSocket endpoint
# ---------------------------------------------------------------------------


@app.websocket("/ws/ambient")
async def ambient_websocket(websocket: WebSocket):
    """
    WebSocket endpoint for ambient listening sessions.

    Client sends PCM audio chunks (binary) or JSON control messages.
    Server sends transcript segments and action plans.

    Authentication: If AMBIENT_API_KEY is set, client must pass it as
    a query parameter: ws://host:port/ws/ambient?key=YOUR_KEY
    """
    # Check API key if configured
    if config.API_KEY:
        client_key = websocket.query_params.get("key", "")
        if client_key != config.API_KEY:
            await websocket.close(code=4001, reason="Invalid API key")
            logger.warning("Rejected WebSocket connection: invalid API key")
            return

    await websocket.accept()
    session_id = uuid.uuid4().hex
    session = AmbientSession(session_id, websocket)
    sessions[session_id] = session

    logger.info("Ambient session started: %s", session_id)

    try:
        await session.start_transcription()

        while True:
            message = await websocket.receive()

            if "bytes" in message and message["bytes"]:
                # Binary data = PCM audio chunk
                if not session.is_paused:
                    session.transcriber.add_audio_chunk(message["bytes"])

            elif "text" in message and message["text"]:
                # JSON control message
                try:
                    data = json.loads(message["text"])
                    msg_type = data.get("type", "")

                    if msg_type == "pause":
                        session.is_paused = True
                        # Flush any remaining buffer
                        await session.flush_and_extract()
                        logger.info("Session %s paused", session_id)

                    elif msg_type == "resume":
                        session.is_paused = False
                        logger.info("Session %s resumed", session_id)

                    elif msg_type == "feedback":
                        feedback = ActionFeedback(**data.get("payload", {}))
                        await session.handle_feedback(feedback)

                except json.JSONDecodeError:
                    logger.warning("Invalid JSON from client")
                except Exception as e:
                    logger.error("Error handling control message: %s", e)

    except WebSocketDisconnect:
        logger.info("Ambient session disconnected: %s", session_id)
    except Exception as e:
        logger.error("Ambient session error: %s — %s", session_id, e)
    finally:
        await session.stop_transcription()
        # Flush any remaining content
        try:
            await session.flush_and_extract()
        except Exception:
            pass
        sessions.pop(session_id, None)
        logger.info("Ambient session cleaned up: %s", session_id)


# ---------------------------------------------------------------------------
# REST endpoints
# ---------------------------------------------------------------------------


@app.get("/health")
def health():
    """Health check endpoint."""
    api_key_set = bool(config.OPENAI_API_KEY and config.OPENAI_API_KEY != "sk-not-configured")
    return {
        "status": "ok",
        "service": "ambient-intelligence",
        "version": "1.0.0",
        "active_sessions": len(sessions),
        "openai_configured": api_key_set,
    }


@app.get("/items")
def list_items(session_id: str | None = None):
    """List all action plans across sessions (or for a specific session)."""
    all_plans = []
    if session_id:
        session = sessions.get(session_id)
        target_sessions = [session] if session else []
    else:
        target_sessions = list(sessions.values())
    for session in target_sessions:
        all_plans.extend(
            plan.model_dump(mode="json") for plan in session.action_plans.values()
        )
    return {"items": all_plans, "count": len(all_plans)}


@app.post("/items/{item_id}/feedback")
async def item_feedback(item_id: str, feedback: ActionFeedback):
    """Submit feedback for an action plan."""
    for session in sessions.values():
        if item_id in session.action_plans:
            feedback.action_plan_id = item_id
            await session.handle_feedback(feedback)
            plan = session.action_plans[item_id]
            return {"ok": True, "plan": plan.model_dump(mode="json")}

    return JSONResponse(
        status_code=404,
        content={"ok": False, "error": f"Action plan {item_id} not found"},
    )


# ---------------------------------------------------------------------------
# Transcript history endpoint
# ---------------------------------------------------------------------------


@app.get("/transcripts")
def get_transcripts(session_id: str | None = None, limit: int = 50):
    """Get transcript history for a session (or all sessions)."""
    all_transcripts: list[str] = []
    if session_id:
        session = sessions.get(session_id)
        target_sessions = [session] if session else []
    else:
        target_sessions = list(sessions.values())
    for session in target_sessions:
        all_transcripts.extend(text for _, text in session.transcript_history[-limit:])
    return {"transcripts": all_transcripts[-limit:], "count": len(all_transcripts)}


# ---------------------------------------------------------------------------
# Chat endpoints (for video chat AI responses)
# ---------------------------------------------------------------------------


@app.post("/chat", response_model=ChatResponse)
async def chat_endpoint(request: ChatRequest):
    """
    Send a message and get an AI response. Used by the video chat feature.
    Maintains conversation history per session_id.
    """
    return await chat_handler(request)


@app.post("/chat/clear")
async def chat_clear(session_id: str = "default"):
    """Clear conversation history for a session."""
    clear_chat_history(session_id)
    return {"ok": True, "session_id": session_id}


# ---------------------------------------------------------------------------
# Startup
# ---------------------------------------------------------------------------


def main():
    """Run the ambient server."""
    import uvicorn

    logger.info(
        "Starting Ambient Intelligence Server on %s:%d",
        config.HOST,
        config.PORT,
    )
    uvicorn.run(
        app,
        host=config.HOST,
        port=config.PORT,
        log_level="info",
    )


if __name__ == "__main__":
    main()
