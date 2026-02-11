"""
Action planner: converts extracted items into executable action plans.

Takes the raw LLM extractions and transforms them into concrete ActionPlan
objects with the correct parameters for each action type (reminder params,
calendar event params, etc.). Applies confidence scoring and deduplication.
"""

from __future__ import annotations

import hashlib
import logging
import time
from datetime import datetime, timedelta

from config import config
from confidence import score_extraction
from models import (
    ActionPlan,
    ActionType,
    CalendarEventParams,
    ConfidenceLevel,
    DraftMessageParams,
    ExecutionStatus,
    ExtractedItem,
    ExtractionResult,
    NoteParams,
    ReminderParams,
)

logger = logging.getLogger(__name__)


class ActionPlanner:
    """
    Converts extracted items into executable action plans.

    Handles confidence scoring, parameter construction, and deduplication
    to prevent the same action from being created multiple times.
    """

    def __init__(self):
        # Dedup: hash → timestamp of last seen
        self._recent_hashes: dict[str, float] = {}

    def plan_actions(
        self,
        extraction: ExtractionResult,
        context_window: str = "",
    ) -> list[ActionPlan]:
        """
        Convert extraction results into action plans.

        Args:
            extraction: The LLM extraction result.
            context_window: Surrounding transcript for audit trail.

        Returns:
            List of ActionPlan objects ready for client execution.
        """
        self._cleanup_dedup_cache()
        plans = []

        for item in extraction.items:
            # Score and classify
            adjusted_confidence, level, auto_execute = score_extraction(item)

            # Skip low-confidence items
            if level == ConfidenceLevel.LOW:
                logger.debug(
                    "Skipping low-confidence item: %s (%.2f)",
                    item.title,
                    adjusted_confidence,
                )
                continue

            # Dedup check
            item_hash = self._hash_item(item)
            if self._is_duplicate(item_hash):
                logger.debug("Skipping duplicate item: %s", item.title)
                continue
            self._recent_hashes[item_hash] = time.time()

            # Build action params based on type
            action_params = self._build_action_params(item)
            action_description = self._build_description(item, auto_execute)

            plan = ActionPlan(
                type=item.type,
                confidence=adjusted_confidence,
                confidence_level=level,
                auto_execute=auto_execute,
                source_transcript=extraction.transcript_segment,
                context_window=context_window,
                action_description=action_description,
                action_params=action_params,
                execution_status=ExecutionStatus.PENDING,
                detected_at=datetime.utcnow(),
                people=item.people,
                deadline=item.deadline,
                undo_window_seconds=config.UNDO_WINDOW_SECONDS,
            )

            plans.append(plan)
            logger.info(
                "Planned action: %s [confidence=%.2f, auto_execute=%s]",
                action_description,
                adjusted_confidence,
                auto_execute,
            )

        return plans

    def _build_action_params(self, item: ExtractedItem) -> dict:
        """Build type-specific action parameters."""

        if item.type in (
            ActionType.REMINDER,
            ActionType.FOLLOW_UP,
            ActionType.COMMITMENT,
        ):
            params = ReminderParams(
                title=item.title,
                due_iso=item.deadline,
                notes=self._build_reminder_notes(item),
            )
            return params.model_dump(exclude_none=True)

        elif item.type == ActionType.CALENDAR_EVENT:
            start_iso = item.deadline or datetime.utcnow().isoformat()
            # Default 1-hour event
            try:
                start_dt = datetime.fromisoformat(start_iso)
            except (ValueError, TypeError):
                start_dt = datetime.utcnow() + timedelta(hours=1)
            end_dt = start_dt + timedelta(hours=1)

            params = CalendarEventParams(
                title=item.title,
                start_iso=start_dt.isoformat(),
                end_iso=end_dt.isoformat(),
                location=item.location,
                notes=item.description,
            )
            return params.model_dump(exclude_none=True)

        elif item.type == ActionType.NOTE:
            params = NoteParams(
                title=item.title,
                body=item.description or "",
            )
            return params.model_dump(exclude_none=True)

        elif item.type == ActionType.DRAFT_MESSAGE:
            recipient = item.people[0] if item.people else "Unknown"
            params = DraftMessageParams(
                recipient=recipient,
                subject=item.title,
                body=item.description or "",
            )
            return params.model_dump(exclude_none=True)

        return {"title": item.title}

    def _build_reminder_notes(self, item: ExtractedItem) -> str | None:
        """Build notes for a reminder, including context."""
        parts = []
        if item.description:
            parts.append(item.description)
        if item.type == ActionType.COMMITMENT:
            parts.append("(Detected commitment from conversation)")
        elif item.type == ActionType.FOLLOW_UP:
            parts.append("(Follow-up detected from conversation)")
        if item.people:
            parts.append(f"People: {', '.join(item.people)}")
        return "\n".join(parts) if parts else None

    def _build_description(self, item: ExtractedItem, auto_execute: bool) -> str:
        """Build a human-readable action description."""
        prefix = "Create" if auto_execute else "Suggest"

        if item.type == ActionType.REMINDER:
            desc = f'{prefix} reminder: "{item.title}"'
        elif item.type == ActionType.CALENDAR_EVENT:
            desc = f'{prefix} calendar event: "{item.title}"'
        elif item.type == ActionType.FOLLOW_UP:
            desc = f'{prefix} follow-up: "{item.title}"'
        elif item.type == ActionType.COMMITMENT:
            desc = f'{prefix} commitment reminder: "{item.title}"'
        elif item.type == ActionType.NOTE:
            desc = f'{prefix} note: "{item.title}"'
        elif item.type == ActionType.DRAFT_MESSAGE:
            recipient = item.people[0] if item.people else "someone"
            desc = f'{prefix} draft message to {recipient}: "{item.title}"'
        else:
            desc = f'{prefix}: "{item.title}"'

        if item.deadline:
            desc += f" — {item.deadline}"

        return desc

    def _hash_item(self, item: ExtractedItem) -> str:
        """Create a hash for deduplication."""
        key = f"{item.type.value}|{item.title.lower().strip()}|{item.deadline or ''}"
        return hashlib.sha256(key.encode()).hexdigest()[:16]

    def _is_duplicate(self, item_hash: str) -> bool:
        """Check if this item was recently seen."""
        last_seen = self._recent_hashes.get(item_hash)
        if last_seen is None:
            return False
        return (time.time() - last_seen) < config.DEDUP_WINDOW_SECONDS

    def _cleanup_dedup_cache(self) -> None:
        """Remove expired entries from the dedup cache."""
        now = time.time()
        expired = [
            h
            for h, ts in self._recent_hashes.items()
            if (now - ts) > config.DEDUP_WINDOW_SECONDS
        ]
        for h in expired:
            del self._recent_hashes[h]
