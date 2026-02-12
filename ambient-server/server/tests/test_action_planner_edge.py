"""Edge case tests for action planner — note, draft, follow-up types + descriptions."""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from action_planner import ActionPlanner
from models import ActionType, ExtractedItem, ExtractionResult


def _make_extraction(items, transcript="test"):
    return ExtractionResult(items=items, transcript_segment=transcript)


def test_plan_note_type():
    """Notes should have title and body in params."""
    planner = ActionPlanner()
    extraction = _make_extraction([
        ExtractedItem(
            type=ActionType.NOTE,
            title="Important observation about Q3 results",
            description="Revenue was up 15% but margins declined",
            confidence=0.7,
        )
    ])
    plans = planner.plan_actions(extraction)
    assert len(plans) == 1
    p = plans[0]
    assert p.type == ActionType.NOTE
    assert p.action_params["title"] == "Important observation about Q3 results"
    assert "Revenue" in p.action_params.get("body", "")


def test_plan_draft_message_type():
    """Draft messages should have recipient, subject, body."""
    planner = ActionPlanner()
    extraction = _make_extraction([
        ExtractedItem(
            type=ActionType.DRAFT_MESSAGE,
            title="Quarterly update for the team",
            description="Summary of Q3 achievements",
            people=["Team"],
            confidence=0.7,
        )
    ])
    plans = planner.plan_actions(extraction)
    assert len(plans) == 1
    p = plans[0]
    assert p.type == ActionType.DRAFT_MESSAGE
    assert p.action_params["recipient"] == "Team"
    assert p.action_params["subject"] == "Quarterly update for the team"


def test_plan_draft_message_no_people():
    """Draft message with no people should use 'Unknown' recipient."""
    planner = ActionPlanner()
    extraction = _make_extraction([
        ExtractedItem(
            type=ActionType.DRAFT_MESSAGE,
            title="Send update about the project status",
            confidence=0.7,
            description="Project update email",
        )
    ])
    plans = planner.plan_actions(extraction)
    assert len(plans) == 1
    assert plans[0].action_params["recipient"] == "Unknown"


def test_plan_follow_up_type():
    """Follow-ups should be created as reminders with follow-up note."""
    planner = ActionPlanner()
    extraction = _make_extraction([
        ExtractedItem(
            type=ActionType.FOLLOW_UP,
            title="Check in with Mike about the design review",
            people=["Mike"],
            deadline="next week",
            confidence=0.85,
        )
    ])
    plans = planner.plan_actions(extraction)
    assert len(plans) == 1
    p = plans[0]
    assert p.type == ActionType.FOLLOW_UP
    assert "title" in p.action_params
    notes = p.action_params.get("notes", "")
    assert "Follow-up" in notes or "follow-up" in notes.lower()
    assert "Mike" in notes


def test_description_for_each_type():
    """Each action type should produce a meaningful description."""
    planner = ActionPlanner()

    types_and_titles = [
        (ActionType.REMINDER, "Buy groceries"),
        (ActionType.CALENDAR_EVENT, "Team standup"),
        (ActionType.FOLLOW_UP, "Check with vendor"),
        (ActionType.COMMITMENT, "Submit report"),
        (ActionType.NOTE, "Interesting insight about the market trends today"),
        (ActionType.DRAFT_MESSAGE, "Write email to client about the new feature"),
    ]

    for action_type, title in types_and_titles:
        p = ActionPlanner()  # Fresh planner to avoid dedup
        extraction = _make_extraction([
            ExtractedItem(
                type=action_type,
                title=title,
                confidence=0.85,
                people=["Someone"] if action_type == ActionType.DRAFT_MESSAGE else [],
                deadline="2026-03-01T09:00:00" if action_type == ActionType.CALENDAR_EVENT else None,
                description="test desc" if action_type in (ActionType.NOTE, ActionType.DRAFT_MESSAGE) else None,
            )
        ])
        plans = p.plan_actions(extraction)
        assert len(plans) >= 1, f"No plans for {action_type}"
        desc = plans[0].action_description
        assert title in desc, f"Title not in description for {action_type}: {desc}"


def test_calendar_event_with_non_iso_deadline():
    """Calendar event with non-ISO deadline should fall back to default time."""
    planner = ActionPlanner()
    extraction = _make_extraction([
        ExtractedItem(
            type=ActionType.CALENDAR_EVENT,
            title="Meeting with team",
            deadline="next Thursday at 3pm",  # Natural language, not ISO
            confidence=0.85,
        )
    ])
    plans = planner.plan_actions(extraction)
    assert len(plans) == 1
    p = plans[0]
    # Should have start_iso and end_iso even though deadline wasn't ISO
    assert "start_iso" in p.action_params
    assert "end_iso" in p.action_params


def test_dedup_cache_cleanup():
    """Dedup cache should clean up expired entries."""
    import time
    planner = ActionPlanner()

    # Add an item
    extraction = _make_extraction([
        ExtractedItem(type=ActionType.REMINDER, title="Test item for dedup cleanup", confidence=0.85)
    ])
    planner.plan_actions(extraction)

    # Verify it's in the cache
    assert len(planner._recent_hashes) == 1

    # Expire it
    for key in planner._recent_hashes:
        planner._recent_hashes[key] = time.time() - 99999

    # Cleanup should remove it
    planner._cleanup_dedup_cache()
    assert len(planner._recent_hashes) == 0


def test_undo_window_from_config():
    """Action plans should use the configured undo window."""
    planner = ActionPlanner()
    extraction = _make_extraction([
        ExtractedItem(type=ActionType.REMINDER, title="Test undo window config value", confidence=0.85)
    ])
    plans = planner.plan_actions(extraction)
    assert len(plans) == 1
    from config import config
    assert plans[0].undo_window_seconds == config.UNDO_WINDOW_SECONDS
