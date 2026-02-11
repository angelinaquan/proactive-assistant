"""Tests for confidence scoring module."""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from confidence import (
    adjust_confidence,
    classify_confidence,
    score_extraction,
    should_auto_execute,
)
from models import ActionType, ConfidenceLevel, ExtractedItem


def test_classify_high():
    assert classify_confidence(0.85) == ConfidenceLevel.HIGH
    assert classify_confidence(0.80) == ConfidenceLevel.HIGH
    assert classify_confidence(1.0) == ConfidenceLevel.HIGH


def test_classify_medium():
    assert classify_confidence(0.5) == ConfidenceLevel.MEDIUM
    assert classify_confidence(0.65) == ConfidenceLevel.MEDIUM
    assert classify_confidence(0.79) == ConfidenceLevel.MEDIUM


def test_classify_low():
    assert classify_confidence(0.0) == ConfidenceLevel.LOW
    assert classify_confidence(0.3) == ConfidenceLevel.LOW
    assert classify_confidence(0.49) == ConfidenceLevel.LOW


def test_should_auto_execute():
    assert should_auto_execute(0.80) is True
    assert should_auto_execute(0.90) is True
    assert should_auto_execute(0.79) is False
    assert should_auto_execute(0.50) is False


def test_adjust_confidence_deadline_boost():
    """Items with specific deadlines get a confidence boost."""
    item = ExtractedItem(
        type=ActionType.REMINDER,
        title="Send report to Sarah",
        deadline="tomorrow 9am",
        confidence=0.75,
    )
    adjusted = adjust_confidence(item)
    assert adjusted > 0.75  # Boosted for deadline


def test_adjust_confidence_people_boost():
    """Items mentioning specific people get a boost."""
    item = ExtractedItem(
        type=ActionType.FOLLOW_UP,
        title="Follow up with Mike about the project",
        people=["Mike"],
        deadline="next week",
        confidence=0.75,
    )
    adjusted = adjust_confidence(item)
    assert adjusted > 0.75


def test_adjust_confidence_short_title_penalty():
    """Very short titles get a confidence reduction."""
    item = ExtractedItem(
        type=ActionType.NOTE,
        title="Do thing",
        confidence=0.7,
    )
    adjusted = adjust_confidence(item)
    assert adjusted < 0.7  # Penalized for short title + note type


def test_adjust_confidence_note_penalty():
    """Notes are less actionable, get a small penalty."""
    item = ExtractedItem(
        type=ActionType.NOTE,
        title="Review the quarterly numbers sometime",
        confidence=0.7,
    )
    adjusted = adjust_confidence(item)
    assert adjusted < 0.7


def test_adjust_confidence_caps_at_1():
    """Confidence should never exceed 1.0 even with boosts."""
    item = ExtractedItem(
        type=ActionType.REMINDER,
        title="Send the detailed report to Sarah by Friday morning",
        deadline="Friday 9am",
        people=["Sarah"],
        confidence=0.98,
    )
    adjusted = adjust_confidence(item)
    assert adjusted <= 1.0


def test_adjust_confidence_floor_at_0():
    """Confidence should never go below 0.0."""
    item = ExtractedItem(
        type=ActionType.DRAFT_MESSAGE,
        title="Hi",
        confidence=0.02,
    )
    adjusted = adjust_confidence(item)
    assert adjusted >= 0.0


def test_score_extraction_full():
    """Full scoring pipeline: adjust → classify → auto_execute."""
    item = ExtractedItem(
        type=ActionType.REMINDER,
        title="Send report to Sarah by tomorrow morning",
        deadline="tomorrow 9am",
        people=["Sarah"],
        confidence=0.85,
    )
    adjusted, level, auto_exec = score_extraction(item)
    assert adjusted >= 0.85
    assert level == ConfidenceLevel.HIGH
    assert auto_exec is True


def test_score_extraction_suggestion():
    """Medium-confidence items are suggestions, not auto-executed."""
    item = ExtractedItem(
        type=ActionType.REMINDER,
        title="Maybe look into the new vendor options",
        description="Potential vendor review",
        confidence=0.65,
    )
    adjusted, level, auto_exec = score_extraction(item)
    assert level == ConfidenceLevel.MEDIUM
    assert auto_exec is False


def test_score_extraction_discard():
    """Low-confidence items should be discarded."""
    item = ExtractedItem(
        type=ActionType.NOTE,
        title="Hmm",
        confidence=0.2,
    )
    adjusted, level, auto_exec = score_extraction(item)
    assert level == ConfidenceLevel.LOW
    assert auto_exec is False
