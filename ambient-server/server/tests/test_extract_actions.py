"""Tests for the full extract_actions function (mocked OpenAI)."""

import json
import sys
from pathlib import Path
from unittest.mock import AsyncMock, MagicMock, patch

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from extraction import extract_actions
from models import ActionType


@pytest.mark.asyncio
async def test_extract_actions_success():
    """Successful extraction returns parsed items."""
    mock_content = json.dumps({"items": [
        {"type": "reminder", "title": "Call dentist", "confidence": 0.85, "deadline": "this week"},
    ]})
    mock_response = MagicMock()
    mock_response.choices = [MagicMock()]
    mock_response.choices[0].message.content = mock_content

    with patch("extraction._get_client") as mock_fn:
        client = AsyncMock()
        client.chat.completions.create = AsyncMock(return_value=mock_response)
        mock_fn.return_value = client

        result = await extract_actions("I need to call the dentist this week")

    assert len(result.items) == 1
    assert result.items[0].title == "Call dentist"
    assert result.items[0].type == ActionType.REMINDER
    assert result.transcript_segment == "I need to call the dentist this week"


@pytest.mark.asyncio
async def test_extract_actions_empty_transcript():
    """Empty transcript should return empty result without calling LLM."""
    result = await extract_actions("")
    assert len(result.items) == 0

    result2 = await extract_actions("   ")
    assert len(result2.items) == 0


@pytest.mark.asyncio
async def test_extract_actions_api_error():
    """API error should return empty result, not raise."""
    with patch("extraction._get_client") as mock_fn:
        client = AsyncMock()
        client.chat.completions.create = AsyncMock(side_effect=Exception("API timeout"))
        mock_fn.return_value = client

        result = await extract_actions("I need to send the report")

    assert len(result.items) == 0
    assert result.transcript_segment == "I need to send the report"


@pytest.mark.asyncio
async def test_extract_actions_empty_response():
    """LLM returning empty content should return empty items."""
    mock_response = MagicMock()
    mock_response.choices = [MagicMock()]
    mock_response.choices[0].message.content = ""

    with patch("extraction._get_client") as mock_fn:
        client = AsyncMock()
        client.chat.completions.create = AsyncMock(return_value=mock_response)
        mock_fn.return_value = client

        result = await extract_actions("some transcript")

    assert len(result.items) == 0


@pytest.mark.asyncio
async def test_extract_actions_with_context():
    """Context should be included in the prompt."""
    mock_response = MagicMock()
    mock_response.choices = [MagicMock()]
    mock_response.choices[0].message.content = '{"items": []}'

    with patch("extraction._get_client") as mock_fn:
        client = AsyncMock()
        client.chat.completions.create = AsyncMock(return_value=mock_response)
        mock_fn.return_value = client

        result = await extract_actions("follow up on that", context="we discussed the vendor contract")

    # Verify create was called with messages containing context
    call_args = client.chat.completions.create.call_args
    messages = call_args.kwargs.get("messages", call_args[1].get("messages", []))
    user_msg = [m for m in messages if m["role"] == "user"][0]["content"]
    assert "vendor contract" in user_msg
    assert "follow up on that" in user_msg


@pytest.mark.asyncio
async def test_extract_actions_injects_datetime():
    """The prompt should include current date/time."""
    mock_response = MagicMock()
    mock_response.choices = [MagicMock()]
    mock_response.choices[0].message.content = '{"items": []}'

    with patch("extraction._get_client") as mock_fn:
        client = AsyncMock()
        client.chat.completions.create = AsyncMock(return_value=mock_response)
        mock_fn.return_value = client

        await extract_actions("test")

    call_args = client.chat.completions.create.call_args
    messages = call_args.kwargs.get("messages", call_args[1].get("messages", []))
    user_msg = [m for m in messages if m["role"] == "user"][0]["content"]
    assert "Current date/time:" in user_msg


@pytest.mark.asyncio
async def test_extract_actions_multiple_items():
    """Multiple items should all be parsed."""
    mock_content = json.dumps({"items": [
        {"type": "reminder", "title": "Call Sarah", "confidence": 0.9},
        {"type": "calendar_event", "title": "Team standup", "confidence": 0.85},
        {"type": "note", "title": "Review numbers", "confidence": 0.6},
    ]})
    mock_response = MagicMock()
    mock_response.choices = [MagicMock()]
    mock_response.choices[0].message.content = mock_content

    with patch("extraction._get_client") as mock_fn:
        client = AsyncMock()
        client.chat.completions.create = AsyncMock(return_value=mock_response)
        mock_fn.return_value = client

        result = await extract_actions("Call Sarah, team standup tomorrow, review numbers")

    assert len(result.items) == 3
