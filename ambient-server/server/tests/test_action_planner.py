"""Tests for action planner module."""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from action_planner import ActionPlanner
from models import ActionType, ConfidenceLevel, ExecutionStatus, ExtractedItem, ExtractionResult


def _make_extraction(items: list[ExtractedItem], transcript: str = "test") -> ExtractionResult:
    return ExtractionResult(items=items, transcript_segment=transcript)


def test_plan_high_confidence_reminder():
    """High-confidence reminder should be auto-executed."""
    planner = ActionPlanner()
    extraction = _make_extraction(
        [
            ExtractedItem(
                type=ActionType.REMINDER,
                title="Send report to Sarah",
                deadline="tomorrow 9am",
                people=["Sarah"],
                confidence=0.90,
            )
        ],
        transcript="I need to send that report to Sarah by tomorrow morning",
    )
    plans = planner.plan_actions(extraction)
    assert len(plans) == 1
    plan = plans[0]
    assert plan.type == ActionType.REMINDER
    assert plan.auto_execute is True
    assert plan.confidence_level == ConfidenceLevel.HIGH
    assert plan.execution_status == ExecutionStatus.PENDING
    assert "title" in plan.action_params
    assert plan.action_params["title"] == "Send report to Sarah"


def test_plan_medium_confidence_is_suggestion():
    """Medium-confidence items should NOT be auto-executed."""
    planner = ActionPlanner()
    extraction = _make_extraction(
        [
            ExtractedItem(
                type=ActionType.REMINDER,
                title="Maybe review the quarterly numbers soon",
                description="Review quarterly data",
                confidence=0.65,
            )
        ]
    )
    plans = planner.plan_actions(extraction)
    assert len(plans) == 1
    plan = plans[0]
    assert plan.auto_execute is False
    assert plan.confidence_level == ConfidenceLevel.MEDIUM


def test_plan_low_confidence_discarded():
    """Low-confidence items should be filtered out."""
    planner = ActionPlanner()
    extraction = _make_extraction(
        [
            ExtractedItem(
                type=ActionType.NOTE,
                title="Hmm",
                confidence=0.2,
            )
        ]
    )
    plans = planner.plan_actions(extraction)
    assert len(plans) == 0


def test_plan_calendar_event():
    """Calendar events should include start/end ISO params."""
    planner = ActionPlanner()
    extraction = _make_extraction(
        [
            ExtractedItem(
                type=ActionType.CALENDAR_EVENT,
                title="Team meeting",
                deadline="2026-02-12T15:00:00",
                people=["Team"],
                location="Conference Room A",
                confidence=0.88,
            )
        ]
    )
    plans = planner.plan_actions(extraction)
    assert len(plans) == 1
    plan = plans[0]
    assert plan.type == ActionType.CALENDAR_EVENT
    assert plan.auto_execute is True
    assert "start_iso" in plan.action_params
    assert "end_iso" in plan.action_params
    assert plan.action_params.get("location") == "Conference Room A"


def test_plan_commitment_creates_reminder():
    """Commitments and follow-ups are created as reminders."""
    planner = ActionPlanner()
    extraction = _make_extraction(
        [
            ExtractedItem(
                type=ActionType.COMMITMENT,
                title="Call the dentist this week",
                confidence=0.82,
                description="Commitment to schedule dental appointment",
            )
        ]
    )
    plans = planner.plan_actions(extraction)
    assert len(plans) == 1
    plan = plans[0]
    assert plan.type == ActionType.COMMITMENT
    assert "title" in plan.action_params
    # Notes should mention it's a detected commitment
    notes = plan.action_params.get("notes", "")
    assert "commitment" in notes.lower() or "Commitment" in notes


def test_deduplication():
    """Same item extracted twice within dedup window should be deduplicated."""
    planner = ActionPlanner()

    extraction1 = _make_extraction(
        [
            ExtractedItem(
                type=ActionType.REMINDER,
                title="Send report to Sarah",
                deadline="tomorrow",
                confidence=0.85,
            )
        ]
    )
    plans1 = planner.plan_actions(extraction1)
    assert len(plans1) == 1

    # Same item again — should be deduplicated
    extraction2 = _make_extraction(
        [
            ExtractedItem(
                type=ActionType.REMINDER,
                title="Send report to Sarah",
                deadline="tomorrow",
                confidence=0.85,
            )
        ]
    )
    plans2 = planner.plan_actions(extraction2)
    assert len(plans2) == 0  # Deduped!


def test_different_items_not_deduplicated():
    """Different items should not be deduplicated."""
    planner = ActionPlanner()

    extraction = _make_extraction(
        [
            ExtractedItem(
                type=ActionType.REMINDER,
                title="Send report to Sarah",
                confidence=0.85,
            ),
            ExtractedItem(
                type=ActionType.REMINDER,
                title="Call the dentist",
                confidence=0.82,
            ),
        ]
    )
    plans = planner.plan_actions(extraction)
    assert len(plans) == 2


def test_multiple_items_mixed_confidence():
    """Extract multiple items: some auto-execute, some suggestions, some discarded."""
    planner = ActionPlanner()
    extraction = _make_extraction(
        [
            ExtractedItem(
                type=ActionType.REMINDER,
                title="Send report to Sarah by tomorrow",
                deadline="tomorrow",
                people=["Sarah"],
                confidence=0.90,
            ),
            ExtractedItem(
                type=ActionType.REMINDER,
                title="Maybe review the vendor contracts sometime",
                description="Vendor review",
                confidence=0.65,
            ),
            ExtractedItem(
                type=ActionType.NOTE,
                title="um",
                confidence=0.15,
            ),
        ]
    )
    plans = planner.plan_actions(extraction)

    auto_execute = [p for p in plans if p.auto_execute]
    suggestions = [p for p in plans if not p.auto_execute]

    assert len(auto_execute) == 1
    assert auto_execute[0].action_params["title"] == "Send report to Sarah by tomorrow"
    assert len(suggestions) == 1
    assert suggestions[0].action_params["title"] == "Maybe review the vendor contracts sometime"
    # The "um" item with 0.15 confidence should be discarded (not in plans)
    assert len(plans) == 2


def test_action_description_format():
    """Action descriptions should be human-readable."""
    planner = ActionPlanner()
    extraction = _make_extraction(
        [
            ExtractedItem(
                type=ActionType.REMINDER,
                title="Send report",
                deadline="tomorrow",
                confidence=0.90,
            )
        ]
    )
    plans = planner.plan_actions(extraction)
    assert len(plans) == 1
    desc = plans[0].action_description
    assert "Send report" in desc
    assert "tomorrow" in desc


def test_context_window_stored():
    """Plans should store the context window for audit trail."""
    planner = ActionPlanner()
    extraction = _make_extraction(
        [
            ExtractedItem(
                type=ActionType.REMINDER,
                title="Call dentist",
                confidence=0.85,
            )
        ],
        transcript="Don't forget to call the dentist",
    )
    plans = planner.plan_actions(extraction, context_window="earlier conversation context")
    assert len(plans) == 1
    assert plans[0].context_window == "earlier conversation context"
    assert plans[0].source_transcript == "Don't forget to call the dentist"
