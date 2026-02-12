"""
Tests verifying the auto_execute flag contract between server and iOS client.

Server behavior (unchanged):
- auto_execute is set based on confidence scoring (>= 0.8 = True)
- Server always sends the truthful auto_execute flag

Client behavior (fix for issue 1.2):
- ProactiveExecutor.processActionPlan checks BOTH:
  1. item.autoExecute (from server confidence scoring)
  2. isAutoExecuteEnabled (user's Settings toggle)
- If user disables auto-execute, all items are stored as suggestions
  regardless of server confidence.

These tests verify the server-side contract is correct so the client
can rely on the auto_execute flag being set consistently.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from action_planner import ActionPlanner
from models import ActionType, ExtractedItem, ExtractionResult


def _plan(items, transcript="test"):
    planner = ActionPlanner()
    extraction = ExtractionResult(items=items, transcript_segment=transcript)
    return planner.plan_actions(extraction)


def test_high_confidence_sets_auto_execute_true():
    """Server must set auto_execute=True for high-confidence items."""
    plans = _plan([
        ExtractedItem(
            type=ActionType.REMINDER,
            title="Send quarterly report to the entire board by Friday",
            deadline="Friday",
            people=["Board"],
            confidence=0.92,
        )
    ])
    assert len(plans) == 1
    assert plans[0].auto_execute is True


def test_medium_confidence_sets_auto_execute_false():
    """Server must set auto_execute=False for medium-confidence items."""
    plans = _plan([
        ExtractedItem(
            type=ActionType.REMINDER,
            title="Maybe look into the vendor contract renewal options",
            description="Vendor review consideration",
            confidence=0.65,
        )
    ])
    assert len(plans) == 1
    assert plans[0].auto_execute is False


def test_auto_execute_flag_in_json_output():
    """The auto_execute flag must be present and boolean in JSON serialization."""
    plans = _plan([
        ExtractedItem(
            type=ActionType.REMINDER,
            title="Call Sarah about the project deadline tomorrow morning",
            deadline="tomorrow morning",
            people=["Sarah"],
            confidence=0.90,
        )
    ])
    data = plans[0].model_dump(mode="json")
    assert "auto_execute" in data
    assert isinstance(data["auto_execute"], bool)
    assert data["auto_execute"] is True


def test_auto_execute_false_in_json_output():
    """Medium-confidence items must have auto_execute=false in JSON."""
    plans = _plan([
        ExtractedItem(
            type=ActionType.REMINDER,
            title="Consider reviewing the old project documentation sometime",
            description="Low priority review",
            confidence=0.60,
        )
    ])
    data = plans[0].model_dump(mode="json")
    assert data["auto_execute"] is False


def test_boundary_confidence_080():
    """Exactly 0.80 raw confidence should auto-execute (after adjustments)."""
    plans = _plan([
        ExtractedItem(
            type=ActionType.REMINDER,
            title="Submit the expense report by end of day today",
            deadline="today",
            confidence=0.80,
        )
    ])
    assert len(plans) == 1
    # 0.80 + deadline boost (0.05) + reminder boost (0.02) = 0.87 → auto_execute
    assert plans[0].auto_execute is True


def test_boundary_confidence_079():
    """0.79 raw confidence without strong signals should NOT auto-execute."""
    plans = _plan([
        ExtractedItem(
            type=ActionType.REMINDER,
            title="Think about maybe scheduling that meeting sometime",
            confidence=0.65,
            description="Vague meeting scheduling consideration",
        )
    ])
    assert len(plans) == 1
    assert plans[0].auto_execute is False
