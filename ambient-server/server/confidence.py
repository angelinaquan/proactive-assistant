"""
Confidence scoring and auto-execute threshold logic.

Determines whether an extracted action should be auto-executed (high confidence),
presented as a suggestion (medium confidence), or discarded (low confidence).
"""

from __future__ import annotations

from models import (
    ActionType,
    ConfidenceLevel,
    ExtractedItem,
)
from config import config


def classify_confidence(score: float) -> ConfidenceLevel:
    """Classify a confidence score into a level."""
    if score >= config.AUTO_EXECUTE_THRESHOLD:
        return ConfidenceLevel.HIGH
    if score >= config.SUGGESTION_THRESHOLD:
        return ConfidenceLevel.MEDIUM
    return ConfidenceLevel.LOW


def should_auto_execute(score: float) -> bool:
    """Whether an action with this confidence score should be auto-executed."""
    return score >= config.AUTO_EXECUTE_THRESHOLD


def adjust_confidence(item: ExtractedItem) -> float:
    """
    Apply heuristic adjustments to the LLM's raw confidence score.

    Boosts confidence when there are strong signals (specific deadlines,
    named people, action verbs). Reduces confidence for vague or
    ambiguous extractions.
    """
    score = item.confidence

    # Boost: specific deadline mentioned
    if item.deadline and item.deadline.strip():
        score = min(1.0, score + 0.05)

    # Boost: specific people mentioned
    if len(item.people) > 0:
        score = min(1.0, score + 0.03)

    # Boost: reminders and calendar events are typically more concrete
    if item.type in (ActionType.REMINDER, ActionType.CALENDAR_EVENT):
        score = min(1.0, score + 0.02)

    # Reduce: very short titles are often vague
    if len(item.title.strip()) < 10:
        score = max(0.0, score - 0.05)

    # Reduce: notes and draft messages are less actionable
    if item.type in (ActionType.NOTE, ActionType.DRAFT_MESSAGE):
        score = max(0.0, score - 0.05)

    # Reduce: no description and no deadline = vague
    if not item.description and not item.deadline:
        score = max(0.0, score - 0.03)

    return round(score, 3)


def score_extraction(item: ExtractedItem) -> tuple[float, ConfidenceLevel, bool]:
    """
    Score an extracted item and determine its disposition.

    Returns:
        (adjusted_confidence, confidence_level, auto_execute)
    """
    adjusted = adjust_confidence(item)
    level = classify_confidence(adjusted)
    auto_exec = should_auto_execute(adjusted)
    return adjusted, level, auto_exec
