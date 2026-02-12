"""Tests for ActionPlan JSON serialization — verifies server output matches iOS decode expectations.

The iOS client uses JSONDecoder with .convertFromSnakeCase, so Pydantic's snake_case
output (action_plan → actionPlan) must be consistent.
"""

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from models import ActionPlan, ActionType, ConfidenceLevel, ExecutionStatus


def test_action_plan_json_has_required_keys():
    """JSON output must have all keys the iOS AmbientActionItem expects."""
    plan = ActionPlan(
        type=ActionType.REMINDER,
        confidence=0.9,
        confidence_level=ConfidenceLevel.HIGH,
        auto_execute=True,
        source_transcript="I need to call Sarah",
        context_window="meeting context",
        action_description='Create reminder: "Call Sarah"',
        action_params={"title": "Call Sarah", "due_iso": "2026-02-13T09:00:00"},
        people=["Sarah"],
        deadline="tomorrow 9am",
        undo_window_seconds=1800,
    )
    data = plan.model_dump(mode="json")

    # These are the keys iOS expects (snake_case, converted to camelCase by iOS decoder)
    required_keys = [
        "id", "type", "confidence", "confidence_level", "auto_execute",
        "source_transcript", "context_window", "action_description",
        "action_params", "execution_status", "detected_at",
        "people", "deadline", "undo_window_seconds",
    ]
    for key in required_keys:
        assert key in data, f"Missing key: {key}"


def test_action_plan_json_types():
    """JSON values must have correct types for iOS decode."""
    plan = ActionPlan(
        type=ActionType.CALENDAR_EVENT,
        confidence=0.85,
        auto_execute=True,
        action_params={"title": "Meeting", "start_iso": "2026-02-12T15:00:00"},
        people=["Team"],
    )
    data = plan.model_dump(mode="json")

    assert isinstance(data["id"], str)
    assert isinstance(data["type"], str)
    assert isinstance(data["confidence"], (int, float))
    assert isinstance(data["auto_execute"], bool)
    assert isinstance(data["action_params"], dict)
    assert isinstance(data["people"], list)
    assert isinstance(data["undo_window_seconds"], int)
    assert isinstance(data["execution_status"], str)


def test_action_plan_json_roundtrip():
    """JSON should be parseable back into ActionPlan."""
    original = ActionPlan(
        type=ActionType.REMINDER,
        confidence=0.9,
        confidence_level=ConfidenceLevel.HIGH,
        auto_execute=True,
        source_transcript="test",
        action_description="Create reminder",
        action_params={"title": "Test"},
        people=["Alice"],
        deadline="tomorrow",
    )
    json_str = original.model_dump_json()
    restored = ActionPlan.model_validate_json(json_str)

    assert restored.id == original.id
    assert restored.type == original.type
    assert restored.confidence == original.confidence
    assert restored.auto_execute == original.auto_execute
    assert restored.people == original.people


def test_action_plan_enum_values_are_strings():
    """Enums should serialize as their string values, not Python repr."""
    plan = ActionPlan(
        type=ActionType.REMINDER,
        confidence_level=ConfidenceLevel.HIGH,
        execution_status=ExecutionStatus.PENDING,
    )
    data = plan.model_dump(mode="json")

    assert data["type"] == "reminder"
    assert data["confidence_level"] == "high"
    assert data["execution_status"] == "pending"


def test_action_plan_optional_fields_null():
    """Optional fields should be null (not missing) in JSON."""
    plan = ActionPlan(type=ActionType.NOTE)
    data = plan.model_dump(mode="json")

    # These should be present as null
    assert "executed_at" in data
    assert data["executed_at"] is None
    assert "confirmed_at" in data
    assert data["confirmed_at"] is None
    assert "deadline" in data
    assert data["deadline"] is None


def test_snake_case_keys():
    """All keys should be snake_case (iOS uses .convertFromSnakeCase)."""
    plan = ActionPlan(
        type=ActionType.REMINDER,
        confidence=0.9,
        confidence_level=ConfidenceLevel.HIGH,
        auto_execute=True,
        source_transcript="test",
    )
    data = plan.model_dump(mode="json")

    for key in data:
        # Verify no camelCase keys
        assert key == key.lower() or "_" in key, f"Key not snake_case: {key}"
        # Verify no spaces or weird chars
        assert key.replace("_", "").isalnum(), f"Invalid key format: {key}"
