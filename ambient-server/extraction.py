"""
LLM-based extraction of actionable items from conversation transcripts.

Uses OpenAI-compatible API to identify commitments, tasks, deadlines,
follow-ups, and other actionable items from natural conversation text.
"""

from __future__ import annotations

import json
import logging
from datetime import datetime, timezone

from openai import AsyncOpenAI

from config import config
from models import ActionType, ExtractedItem, ExtractionResult

logger = logging.getLogger(__name__)

EXTRACTION_SYSTEM_PROMPT = """\
You are an ambient intelligence assistant that analyzes conversation transcripts \
to identify actionable items. You listen to natural conversation and extract \
commitments, tasks, reminders, follow-ups, calendar events, and notes.

IMPORTANT RULES:
1. Only extract items that are CLEARLY actionable — someone committed to doing \
something, or there's a clear task/reminder.
2. Do NOT extract casual mentions, opinions, or hypotheticals.
3. Each item needs a clear title that describes the action.
4. Assign a confidence score (0.0–1.0) based on how clearly the item was stated:
   - 0.9–1.0: Explicit commitment with specific details ("I'll send the report \
to Sarah by tomorrow 9am")
   - 0.7–0.89: Clear intent but missing some specifics ("I need to call the \
dentist this week")
   - 0.5–0.69: Probable intent but ambiguous ("We should probably look into that")
   - Below 0.5: Too vague to be actionable
5. For deadlines, extract any time references (tomorrow, next week, Thursday, etc.)
6. Extract names of people mentioned in connection with the action.
7. Categorize each item as one of: reminder, calendar_event, follow_up, \
commitment, note, draft_message

OUTPUT FORMAT: Return a JSON array of extracted items. Each item has:
{
  "type": "reminder|calendar_event|follow_up|commitment|note|draft_message",
  "title": "Short action description",
  "description": "Additional context if available",
  "deadline": "Time reference if mentioned (natural language or ISO 8601)",
  "people": ["Names mentioned"],
  "location": "Location if mentioned",
  "confidence": 0.0-1.0,
  "reasoning": "Brief explanation of why this was extracted"
}

Return ONLY the JSON array. No other text. If nothing actionable is found, \
return an empty array: []
"""


def _get_client() -> AsyncOpenAI:
    """Create an OpenAI client."""
    return AsyncOpenAI(
        api_key=config.OPENAI_API_KEY or "sk-placeholder",
        base_url=config.OPENAI_BASE_URL,
    )


async def extract_actions(
    transcript: str,
    context: str | None = None,
) -> ExtractionResult:
    """
    Extract actionable items from a transcript segment using LLM.

    Args:
        transcript: The transcript text to analyze.
        context: Optional surrounding context for better understanding.

    Returns:
        ExtractionResult with list of extracted items.
    """
    if not transcript.strip():
        return ExtractionResult(items=[], transcript_segment=transcript)

    user_prompt = f"Analyze this conversation transcript for actionable items:\n\n"
    if context:
        user_prompt += f"[Previous context]: {context}\n\n"
    user_prompt += f"[Current segment]: {transcript}"

    client = _get_client()

    try:
        response = await client.chat.completions.create(
            model=config.OPENAI_MODEL,
            messages=[
                {"role": "system", "content": EXTRACTION_SYSTEM_PROMPT},
                {"role": "user", "content": user_prompt},
            ],
            temperature=0.2,
            max_tokens=2000,
            response_format={"type": "json_object"},
        )

        content = response.choices[0].message.content or "[]"
        items = _parse_extraction_response(content)

        logger.info(
            "Extracted %d items from %d-char transcript",
            len(items),
            len(transcript),
        )

        return ExtractionResult(
            items=items,
            transcript_segment=transcript,
            processed_at=datetime.now(timezone.utc),
        )

    except Exception as e:
        logger.error("LLM extraction failed: %s", e)
        return ExtractionResult(items=[], transcript_segment=transcript)


def _parse_extraction_response(content: str) -> list[ExtractedItem]:
    """Parse the LLM's JSON response into ExtractedItem objects."""
    try:
        data = json.loads(content)

        # Handle both { "items": [...] } and plain [...] formats
        if isinstance(data, dict):
            items_raw = data.get("items", data.get("actions", []))
        elif isinstance(data, list):
            items_raw = data
        else:
            logger.warning("Unexpected extraction response format: %s", type(data))
            return []

        items = []
        for raw in items_raw:
            try:
                item_type = raw.get("type", "note")
                # Normalize type string
                type_map = {
                    "reminder": ActionType.REMINDER,
                    "calendar_event": ActionType.CALENDAR_EVENT,
                    "calendar": ActionType.CALENDAR_EVENT,
                    "event": ActionType.CALENDAR_EVENT,
                    "follow_up": ActionType.FOLLOW_UP,
                    "followup": ActionType.FOLLOW_UP,
                    "follow-up": ActionType.FOLLOW_UP,
                    "commitment": ActionType.COMMITMENT,
                    "note": ActionType.NOTE,
                    "draft_message": ActionType.DRAFT_MESSAGE,
                    "draft": ActionType.DRAFT_MESSAGE,
                    "message": ActionType.DRAFT_MESSAGE,
                }
                action_type = type_map.get(item_type.lower(), ActionType.NOTE)

                confidence = float(raw.get("confidence", 0.5))
                confidence = max(0.0, min(1.0, confidence))

                item = ExtractedItem(
                    type=action_type,
                    title=raw.get("title", "").strip(),
                    description=raw.get("description"),
                    deadline=raw.get("deadline"),
                    people=raw.get("people", []),
                    location=raw.get("location"),
                    confidence=confidence,
                    reasoning=raw.get("reasoning"),
                )

                # Skip items with empty titles
                if item.title:
                    items.append(item)

            except Exception as e:
                logger.warning("Failed to parse extracted item: %s — %s", raw, e)
                continue

        return items

    except json.JSONDecodeError as e:
        logger.error("Failed to parse LLM extraction JSON: %s", e)
        return []
