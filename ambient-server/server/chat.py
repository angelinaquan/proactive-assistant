"""
Conversational AI chat for the video chat feature.

Accepts user messages, maintains conversation history per session,
and returns AI responses using the configured LLM.
"""

from __future__ import annotations

import logging
from datetime import datetime, timezone

from openai import AsyncOpenAI
from pydantic import BaseModel, Field

from config import config

logger = logging.getLogger(__name__)

CHAT_SYSTEM_PROMPT = """\
You are a helpful, friendly AI assistant in a voice conversation. \
Keep your responses concise and natural — you are being spoken aloud \
via text-to-speech, so:

- Use short sentences.
- Avoid bullet points, markdown, or formatting.
- Be conversational, warm, and direct.
- If asked about tasks or reminders, note that the ambient listening \
system can handle those automatically.
- Keep responses under 3 sentences unless the user asks for detail.
"""


class ChatMessage(BaseModel):
    role: str  # "user" or "assistant"
    content: str
    timestamp: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))


class ChatRequest(BaseModel):
    message: str
    session_id: str = "default"


class ChatResponse(BaseModel):
    reply: str
    session_id: str
    message_count: int


# Per-session conversation history
_histories: dict[str, list[ChatMessage]] = {}

MAX_HISTORY_MESSAGES = 20  # Keep last N messages per session


def _get_client() -> AsyncOpenAI:
    return AsyncOpenAI(
        api_key=config.OPENAI_API_KEY or "sk-not-configured",
        base_url=config.OPENAI_BASE_URL,
    )


async def chat(request: ChatRequest) -> ChatResponse:
    """
    Send a user message and get an AI response.
    Maintains conversation history per session_id.
    """
    session_id = request.session_id
    user_text = request.message.strip()

    if not user_text:
        return ChatResponse(
            reply="I didn't catch that. Could you say it again?",
            session_id=session_id,
            message_count=len(_histories.get(session_id, [])),
        )

    # Get or create history
    if session_id not in _histories:
        _histories[session_id] = []
    history = _histories[session_id]

    # Add user message
    history.append(ChatMessage(role="user", content=user_text))

    # Trim history to prevent token overflow
    if len(history) > MAX_HISTORY_MESSAGES:
        history[:] = history[-MAX_HISTORY_MESSAGES:]

    # Build messages for LLM
    messages = [{"role": "system", "content": CHAT_SYSTEM_PROMPT}]
    for msg in history:
        messages.append({"role": msg.role, "content": msg.content})

    client = _get_client()

    try:
        response = await client.chat.completions.create(
            model=config.OPENAI_MODEL,
            messages=messages,
            temperature=0.7,
            max_tokens=300,
        )

        reply = (response.choices[0].message.content or "").strip()
        if not reply:
            reply = "Hmm, I'm not sure what to say to that."

    except Exception as e:
        logger.error("Chat LLM call failed: %s", e)
        reply = "Sorry, I'm having trouble thinking right now. Try again in a moment."

    # Add assistant response to history
    history.append(ChatMessage(role="assistant", content=reply))

    logger.info(
        "Chat session=%s user=%d chars reply=%d chars history=%d",
        session_id,
        len(user_text),
        len(reply),
        len(history),
    )

    return ChatResponse(
        reply=reply,
        session_id=session_id,
        message_count=len(history),
    )


def clear_chat_history(session_id: str) -> None:
    """Clear conversation history for a session."""
    _histories.pop(session_id, None)


def get_chat_history(session_id: str) -> list[ChatMessage]:
    """Get conversation history for a session."""
    return list(_histories.get(session_id, []))
