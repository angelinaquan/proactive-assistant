"""Tests for data models."""

import sys
from pathlib import Path

# Add parent to path
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from models import (
    ActionPlan,
    ActionType,
    ConfidenceLevel,
    ExecutionStatus,
    ExtractedItem,
    ExtractionResult,
    TranscriptSegment,
    WSMessage,
    WSMessageType,
    ActionFeedback,
    FeedbackAction,
)


def test_action_plan_defaults():
    plan = ActionPlan(type=ActionType.REMINDER)
    assert plan.type == ActionType.REMINDER
    assert plan.confidence == 0.0
    assert plan.confidence_level == ConfidenceLevel.LOW
    assert plan.auto_execute is False
    assert plan.execution_status == ExecutionStatus.PENDING
    assert plan.id  # non-empty UUID hex


def test_action_plan_full():
    plan = ActionPlan(
        type=ActionType.CALENDAR_EVENT,
        confidence=0.92,
        confidence_level=ConfidenceLevel.HIGH,
        auto_execute=True,
        source_transcript="Let's meet Thursday at 3",
        action_description='Create calendar event: "Team meeting"',
        action_params={"title": "Team meeting", "start_iso": "2026-02-12T15:00:00"},
        people=["Sarah", "Mike"],
        deadline="Thursday 3pm",
    )
    assert plan.auto_execute is True
    assert plan.confidence == 0.92
    assert plan.people == ["Sarah", "Mike"]
    assert plan.action_params["title"] == "Team meeting"


def test_extracted_item_validation():
    item = ExtractedItem(
        type=ActionType.REMINDER,
        title="Call dentist",
        confidence=0.85,
        people=["Dr. Smith"],
        deadline="this week",
    )
    assert item.confidence == 0.85
    assert item.type == ActionType.REMINDER
    assert len(item.people) == 1


def test_extracted_item_confidence_bounds():
    item = ExtractedItem(
        type=ActionType.NOTE,
        title="Test",
        confidence=0.0,
    )
    assert item.confidence == 0.0

    item2 = ExtractedItem(
        type=ActionType.NOTE,
        title="Test",
        confidence=1.0,
    )
    assert item2.confidence == 1.0


def test_extraction_result_empty():
    result = ExtractionResult()
    assert result.items == []
    assert result.transcript_segment == ""


def test_transcript_segment():
    seg = TranscriptSegment(text="hello world", is_partial=False, latency_ms=123.4)
    assert seg.text == "hello world"
    assert seg.is_partial is False
    assert seg.latency_ms == 123.4


def test_ws_message():
    msg = WSMessage(
        type=WSMessageType.ACTION_PLAN,
        payload={"id": "abc", "type": "reminder"},
    )
    assert msg.type == WSMessageType.ACTION_PLAN
    assert msg.payload["id"] == "abc"


def test_feedback():
    fb = ActionFeedback(action_plan_id="plan-123", action=FeedbackAction.UNDO)
    assert fb.action_plan_id == "plan-123"
    assert fb.action == FeedbackAction.UNDO
    assert fb.edited_params is None


def test_feedback_with_edit():
    fb = ActionFeedback(
        action_plan_id="plan-456",
        action=FeedbackAction.EDIT,
        edited_params={"title": "Updated title"},
    )
    assert fb.action == FeedbackAction.EDIT
    assert fb.edited_params["title"] == "Updated title"
