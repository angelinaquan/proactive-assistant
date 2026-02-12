"""Tests for the chat module (video chat AI responses)."""

import sys
from pathlib import Path
from unittest.mock import AsyncMock, MagicMock, patch

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from chat import (
    ChatMessage,
    ChatRequest,
    ChatResponse,
    chat,
    clear_chat_history,
    get_chat_history,
    _histories,
)


@pytest.fixture(autouse=True)
def clear_histories():
    """Clear chat histories before each test."""
    _histories.clear()
    yield
    _histories.clear()


def test_chat_request_model():
    req = ChatRequest(message="Hello", session_id="test-1")
    assert req.message == "Hello"
    assert req.session_id == "test-1"


def test_chat_request_default_session():
    req = ChatRequest(message="Hi")
    assert req.session_id == "default"


def test_chat_response_model():
    resp = ChatResponse(reply="Hi there!", session_id="s1", message_count=2)
    assert resp.reply == "Hi there!"
    assert resp.message_count == 2


def test_chat_message_model():
    msg = ChatMessage(role="user", content="test")
    assert msg.role == "user"
    assert msg.content == "test"
    assert msg.timestamp is not None


@pytest.mark.asyncio
async def test_chat_empty_message():
    """Empty message should return a fallback response."""
    resp = await chat(ChatRequest(message="", session_id="empty-test"))
    assert "didn't catch" in resp.reply.lower()


@pytest.mark.asyncio
async def test_chat_whitespace_message():
    """Whitespace-only message should return a fallback response."""
    resp = await chat(ChatRequest(message="   ", session_id="ws-test"))
    assert "didn't catch" in resp.reply.lower()


@pytest.mark.asyncio
async def test_chat_stores_history():
    """Chat should maintain conversation history per session."""
    mock_response = MagicMock()
    mock_response.choices = [MagicMock()]
    mock_response.choices[0].message.content = "I'm doing well, thanks!"

    with patch("chat._get_client") as mock_client_fn:
        client = AsyncMock()
        client.chat.completions.create = AsyncMock(return_value=mock_response)
        mock_client_fn.return_value = client

        resp = await chat(ChatRequest(message="How are you?", session_id="hist-test"))

    assert resp.reply == "I'm doing well, thanks!"
    assert resp.session_id == "hist-test"
    assert resp.message_count == 2  # user + assistant

    history = get_chat_history("hist-test")
    assert len(history) == 2
    assert history[0].role == "user"
    assert history[0].content == "How are you?"
    assert history[1].role == "assistant"
    assert history[1].content == "I'm doing well, thanks!"


@pytest.mark.asyncio
async def test_chat_multi_turn():
    """Multiple turns should accumulate in history."""
    mock_response = MagicMock()
    mock_response.choices = [MagicMock()]
    mock_response.choices[0].message.content = "Response"

    with patch("chat._get_client") as mock_client_fn:
        client = AsyncMock()
        client.chat.completions.create = AsyncMock(return_value=mock_response)
        mock_client_fn.return_value = client

        await chat(ChatRequest(message="Turn 1", session_id="multi"))
        await chat(ChatRequest(message="Turn 2", session_id="multi"))
        resp = await chat(ChatRequest(message="Turn 3", session_id="multi"))

    assert resp.message_count == 6  # 3 user + 3 assistant
    history = get_chat_history("multi")
    assert len(history) == 6


@pytest.mark.asyncio
async def test_chat_separate_sessions():
    """Different session_ids should have independent histories."""
    mock_response = MagicMock()
    mock_response.choices = [MagicMock()]
    mock_response.choices[0].message.content = "Reply"

    with patch("chat._get_client") as mock_client_fn:
        client = AsyncMock()
        client.chat.completions.create = AsyncMock(return_value=mock_response)
        mock_client_fn.return_value = client

        await chat(ChatRequest(message="Hello", session_id="session-a"))
        await chat(ChatRequest(message="Hi", session_id="session-b"))

    assert len(get_chat_history("session-a")) == 2
    assert len(get_chat_history("session-b")) == 2


@pytest.mark.asyncio
async def test_chat_llm_failure_returns_fallback():
    """If LLM call fails, should return a friendly error message."""
    with patch("chat._get_client") as mock_client_fn:
        client = AsyncMock()
        client.chat.completions.create = AsyncMock(side_effect=Exception("API timeout"))
        mock_client_fn.return_value = client

        resp = await chat(ChatRequest(message="Hello", session_id="fail-test"))

    assert "sorry" in resp.reply.lower() or "trouble" in resp.reply.lower()
    # Should still store the user message + fallback in history
    assert resp.message_count == 2


def test_clear_chat_history():
    """Clearing history should remove all messages for that session."""
    _histories["clear-test"] = [
        ChatMessage(role="user", content="msg1"),
        ChatMessage(role="assistant", content="msg2"),
    ]
    clear_chat_history("clear-test")
    assert get_chat_history("clear-test") == []


def test_clear_nonexistent_session():
    """Clearing a nonexistent session should not crash."""
    clear_chat_history("does-not-exist")  # Should not raise


def test_get_history_empty():
    """Getting history for unknown session should return empty list."""
    assert get_chat_history("unknown") == []
