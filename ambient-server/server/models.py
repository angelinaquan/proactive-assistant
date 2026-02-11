"""Data models for the ambient listening system."""

from __future__ import annotations

import uuid
from datetime import datetime, timezone
from enum import Enum
from typing import Any

from pydantic import BaseModel, Field


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


class ActionType(str, Enum):
    """Types of actions the system can detect and execute."""

    REMINDER = "reminder"
    CALENDAR_EVENT = "calendar_event"
    FOLLOW_UP = "follow_up"
    COMMITMENT = "commitment"
    NOTE = "note"
    DRAFT_MESSAGE = "draft_message"


class ExecutionStatus(str, Enum):
    """Lifecycle status of an action plan."""

    PENDING = "pending"
    EXECUTED = "executed"
    CONFIRMED = "confirmed"
    UNDONE = "undone"
    FAILED = "failed"


class ConfidenceLevel(str, Enum):
    """Categorized confidence level."""

    HIGH = "high"  # >= 0.8 → auto-execute
    MEDIUM = "medium"  # 0.5–0.8 → suggestion
    LOW = "low"  # < 0.5 → discard


# ---------------------------------------------------------------------------
# Extraction models (output from LLM)
# ---------------------------------------------------------------------------


class ExtractedItem(BaseModel):
    """A single actionable item extracted from conversation by the LLM."""

    type: ActionType
    title: str
    description: str | None = None
    deadline: str | None = None  # ISO 8601 or natural language
    people: list[str] = Field(default_factory=list)
    location: str | None = None
    confidence: float = Field(ge=0.0, le=1.0)
    reasoning: str | None = None  # LLM's reasoning for extraction


class ExtractionResult(BaseModel):
    """Result of LLM extraction from a transcript segment."""

    items: list[ExtractedItem] = Field(default_factory=list)
    transcript_segment: str = ""
    processed_at: datetime = Field(default_factory=_utcnow)


# ---------------------------------------------------------------------------
# Action plan models (ready for execution)
# ---------------------------------------------------------------------------


class ReminderParams(BaseModel):
    """Parameters for creating a reminder."""

    title: str
    due_iso: str | None = None
    notes: str | None = None
    list_name: str | None = None


class CalendarEventParams(BaseModel):
    """Parameters for creating a calendar event."""

    title: str
    start_iso: str
    end_iso: str
    is_all_day: bool = False
    location: str | None = None
    notes: str | None = None


class NoteParams(BaseModel):
    """Parameters for creating a local note."""

    title: str
    body: str = ""


class DraftMessageParams(BaseModel):
    """Parameters for a draft message suggestion."""

    recipient: str
    subject: str | None = None
    body: str = ""


class ActionPlan(BaseModel):
    """
    A fully planned action ready for execution by the iOS client.

    This is the core data structure sent to clients. High-confidence plans
    have auto_execute=True, meaning the client should immediately create the
    reminder/event and present it for confirmation. Lower-confidence plans
    are presented as suggestions.
    """

    id: str = Field(default_factory=lambda: uuid.uuid4().hex)
    type: ActionType
    confidence: float = Field(default=0.0, ge=0.0, le=1.0)
    confidence_level: ConfidenceLevel = ConfidenceLevel.LOW
    auto_execute: bool = False

    # What was heard
    source_transcript: str = ""
    context_window: str = ""  # surrounding transcript for audit trail

    # What the system decided to do
    action_description: str = ""
    action_params: dict[str, Any] = Field(default_factory=dict)

    # Execution state (tracked by client, echoed back via feedback)
    execution_status: ExecutionStatus = ExecutionStatus.PENDING
    executed_at: datetime | None = None
    execution_result: dict[str, Any] | None = None  # { identifier: ... }

    # Timestamps
    detected_at: datetime = Field(default_factory=_utcnow)
    confirmed_at: datetime | None = None
    undone_at: datetime | None = None

    # Entities
    people: list[str] = Field(default_factory=list)
    deadline: str | None = None

    # Undo window recommendation (seconds)
    undo_window_seconds: int = 1800


# ---------------------------------------------------------------------------
# Transcript models
# ---------------------------------------------------------------------------


class TranscriptSegment(BaseModel):
    """A segment of transcribed audio."""

    text: str
    is_partial: bool = True
    timestamp: datetime = Field(default_factory=_utcnow)
    latency_ms: float | None = None


# ---------------------------------------------------------------------------
# WebSocket message models
# ---------------------------------------------------------------------------


class WSMessageType(str, Enum):
    """Types of WebSocket messages between server and client."""

    # Server → Client
    TRANSCRIPT = "transcript"
    ACTION_PLAN = "action_plan"
    HEALTH = "health"
    ERROR = "error"

    # Client → Server
    AUDIO_CHUNK = "audio_chunk"
    FEEDBACK = "feedback"
    PAUSE = "pause"
    RESUME = "resume"


class WSMessage(BaseModel):
    """WebSocket message envelope."""

    type: WSMessageType
    payload: dict[str, Any] = Field(default_factory=dict)
    timestamp: datetime = Field(default_factory=_utcnow)


# ---------------------------------------------------------------------------
# Feedback models (client → server)
# ---------------------------------------------------------------------------


class FeedbackAction(str, Enum):
    """User feedback on an action plan."""

    KEEP = "keep"
    EDIT = "edit"
    UNDO = "undo"
    DISCARD = "discard"
    EXECUTE = "execute"  # For suggestions the user wants to execute


class ActionFeedback(BaseModel):
    """Feedback from user on an action plan."""

    action_plan_id: str
    action: FeedbackAction
    edited_params: dict[str, Any] | None = None  # If action == EDIT
