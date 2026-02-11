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

app = FastAPI(
    title="Ambient Listening Intelligence Server",
    version="1.0.0",
    description="Real-time ambient audio → transcription → action extraction",
)

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
        self.transcript_history: list[str] = []
        self.is_paused = False
        self.created_at = datetime.now(timezone.utc)
        self._extraction_lock = asyncio.Lock()
        self._context_window: list[str] = []  # Last N segments for context

    async def start_transcription(self) -> None:
        """Start the transcription engine."""
        self.transcriber = AmbientTranscriber(
            on_transcript=self._on_transcript_sync,
        )
        await self.transcriber.start()

    async def stop_transcription(self) -> None:
        """Stop the transcription engine."""
        if self.transcriber:
            await self.transcriber.stop()
            self.transcriber = None

    def _on_transcript_sync(
        self, text: str, is_partial: bool, latency_ms: float
    ) -> None:
        """Sync callback from transcriber — schedules async work."""
        asyncio.get_event_loop().call_soon_threadsafe(
            asyncio.ensure_future,
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

                # Store transcript
                self.transcript_history.append(transcript)

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
    """
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
    return {
        "status": "ok",
        "service": "ambient-intelligence",
        "version": "1.0.0",
        "active_sessions": len(sessions),
    }


@app.get("/items")
def list_items(session_id: str | None = None):
    """List all action plans across sessions (or for a specific session)."""
    all_plans = []
    target_sessions = (
        [sessions[session_id]] if session_id and session_id in sessions else sessions.values()
    )
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
