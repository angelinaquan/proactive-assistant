"""Tests for the extraction module's JSON parser."""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from extraction import _parse_extraction_response
from models import ActionType


def test_parse_array_format():
    """Parser should handle plain JSON array."""
    content = '''[
        {
            "type": "reminder",
            "title": "Send report to Sarah",
            "confidence": 0.85,
            "deadline": "tomorrow 9am",
            "people": ["Sarah"],
            "reasoning": "Clear commitment"
        }
    ]'''
    items = _parse_extraction_response(content)
    assert len(items) == 1
    assert items[0].title == "Send report to Sarah"
    assert items[0].type == ActionType.REMINDER
    assert items[0].confidence == 0.85
    assert items[0].people == ["Sarah"]


def test_parse_object_with_items_key():
    """Parser should handle { items: [...] } format."""
    content = '''{
        "items": [
            {"type": "calendar_event", "title": "Team meeting", "confidence": 0.9}
        ]
    }'''
    items = _parse_extraction_response(content)
    assert len(items) == 1
    assert items[0].type == ActionType.CALENDAR_EVENT


def test_parse_object_with_actions_key():
    """Parser should handle { actions: [...] } format."""
    content = '''{
        "actions": [
            {"type": "follow_up", "title": "Check with Mike", "confidence": 0.7}
        ]
    }'''
    items = _parse_extraction_response(content)
    assert len(items) == 1
    assert items[0].type == ActionType.FOLLOW_UP


def test_parse_empty_array():
    content = "[]"
    items = _parse_extraction_response(content)
    assert len(items) == 0


def test_parse_empty_object():
    content = '{"items": []}'
    items = _parse_extraction_response(content)
    assert len(items) == 0


def test_parse_type_normalization():
    """Various type strings should be normalized correctly."""
    content = '''[
        {"type": "calendar", "title": "Meeting", "confidence": 0.8},
        {"type": "event", "title": "Party", "confidence": 0.7},
        {"type": "followup", "title": "Follow up", "confidence": 0.6},
        {"type": "follow-up", "title": "Check in", "confidence": 0.65},
        {"type": "draft", "title": "Email", "confidence": 0.5},
        {"type": "message", "title": "Text", "confidence": 0.5}
    ]'''
    items = _parse_extraction_response(content)
    assert len(items) == 6
    assert items[0].type == ActionType.CALENDAR_EVENT
    assert items[1].type == ActionType.CALENDAR_EVENT
    assert items[2].type == ActionType.FOLLOW_UP
    assert items[3].type == ActionType.FOLLOW_UP
    assert items[4].type == ActionType.DRAFT_MESSAGE
    assert items[5].type == ActionType.DRAFT_MESSAGE


def test_parse_confidence_clamping():
    """Confidence should be clamped to 0.0-1.0."""
    content = '''[
        {"type": "note", "title": "High", "confidence": 1.5},
        {"type": "note", "title": "Low", "confidence": -0.3}
    ]'''
    items = _parse_extraction_response(content)
    assert len(items) == 2
    assert items[0].confidence == 1.0
    assert items[1].confidence == 0.0


def test_parse_skips_empty_titles():
    """Items with empty titles should be skipped."""
    content = '''[
        {"type": "reminder", "title": "", "confidence": 0.8},
        {"type": "reminder", "title": "Valid", "confidence": 0.8}
    ]'''
    items = _parse_extraction_response(content)
    assert len(items) == 1
    assert items[0].title == "Valid"


def test_parse_invalid_json():
    """Invalid JSON should return empty list."""
    items = _parse_extraction_response("not json at all")
    assert len(items) == 0


def test_parse_malformed_item():
    """Malformed items in array should be skipped gracefully."""
    content = '''[
        {"type": "reminder", "title": "Good item", "confidence": 0.8},
        "this is not an object",
        {"type": "reminder", "title": "Also good", "confidence": 0.7}
    ]'''
    items = _parse_extraction_response(content)
    # Should get the 2 valid items, skip the string
    assert len(items) == 2


def test_parse_optional_fields():
    """Optional fields should default gracefully."""
    content = '''[
        {"type": "reminder", "title": "Minimal item", "confidence": 0.8}
    ]'''
    items = _parse_extraction_response(content)
    assert len(items) == 1
    assert items[0].description is None
    assert items[0].deadline is None
    assert items[0].people == []
    assert items[0].location is None
    assert items[0].reasoning is None


def test_parse_all_fields():
    """All optional fields should be captured when present."""
    content = '''[{
        "type": "commitment",
        "title": "Send quarterly report",
        "description": "Quarterly financial report for Q1",
        "deadline": "2026-03-01",
        "people": ["CFO", "Board"],
        "location": "Main office",
        "confidence": 0.95,
        "reasoning": "Explicit deadline commitment in conversation"
    }]'''
    items = _parse_extraction_response(content)
    assert len(items) == 1
    item = items[0]
    assert item.type == ActionType.COMMITMENT
    assert item.description == "Quarterly financial report for Q1"
    assert item.deadline == "2026-03-01"
    assert item.people == ["CFO", "Board"]
    assert item.location == "Main office"
    assert item.reasoning == "Explicit deadline commitment in conversation"
