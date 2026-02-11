"""
WhisperFlow integration for real-time transcription.

Wraps WhisperFlow's TranscribeSession to provide streaming speech-to-text
for the ambient listening pipeline.
"""

from __future__ import annotations

import asyncio
import logging
import sys
import time
from pathlib import Path
from queue import Queue
from typing import Callable

# Add WhisperFlow to the Python path
WHISPERFLOW_PATH = Path(__file__).resolve().parent.parent / "whisper-flow-main"
if str(WHISPERFLOW_PATH) not in sys.path:
    sys.path.insert(0, str(WHISPERFLOW_PATH))

from config import config

logger = logging.getLogger(__name__)


def _load_whisper_model():
    """Load the Whisper model (lazy, cached)."""
    import whisperflow.transcriber as ts

    return ts.get_model(config.WHISPER_MODEL)


class AmbientTranscriber:
    """
    Manages a real-time transcription session for ambient listening.

    Uses WhisperFlow's streaming transcription engine with tumbling windows.
    Audio chunks (PCM 16kHz mono int16) are fed in, and transcript segments
    are emitted via callback.
    """

    def __init__(
        self,
        on_transcript: Callable[[str, bool, float], None] | None = None,
    ):
        """
        Args:
            on_transcript: Callback(text, is_partial, latency_ms) for each
                           transcript segment.
        """
        self._on_transcript = on_transcript
        self._queue: Queue = Queue()
        self._should_stop: list[bool] = [False]
        self._task: asyncio.Task | None = None
        self._model = None

    async def start(self) -> None:
        """Start the transcription loop."""
        if self._task is not None:
            return

        logger.info("Loading Whisper model: %s", config.WHISPER_MODEL)
        self._model = _load_whisper_model()
        self._should_stop[0] = False

        import whisperflow.transcriber as ts

        async def transcribe_async(chunks: list):
            return await ts.transcribe_pcm_chunks_async(
                self._model, chunks, lang=config.WHISPER_LANGUAGE
            )

        async def on_segment(result: dict):
            text = result.get("data", {}).get("text", "").strip()
            is_partial = result.get("is_partial", True)
            latency_ms = result.get("time", 0.0)
            if text and self._on_transcript:
                self._on_transcript(text, is_partial, latency_ms)

        # Use WhisperFlow's streaming transcription loop
        import whisperflow.streaming as st

        self._task = asyncio.create_task(
            st.transcribe(
                self._should_stop,
                self._queue,
                transcribe_async,
                on_segment,
            )
        )
        logger.info("Transcription session started")

    async def stop(self) -> None:
        """Stop the transcription loop."""
        self._should_stop[0] = True
        if self._task is not None:
            try:
                await self._task
            except Exception:
                pass
            self._task = None
        logger.info("Transcription session stopped")

    def add_audio_chunk(self, chunk: bytes) -> None:
        """Add a PCM audio chunk for transcription."""
        if not self._should_stop[0]:
            self._queue.put_nowait(chunk)

    @property
    def is_running(self) -> bool:
        return self._task is not None and not self._should_stop[0]


class TranscriptBuffer:
    """
    Accumulates transcript segments over a time window for batch extraction.

    Collects finalized (non-partial) transcript segments and yields them
    for LLM extraction once the buffer reaches the configured duration.
    """

    def __init__(self, buffer_seconds: int | None = None):
        self._buffer_seconds = buffer_seconds or config.TRANSCRIPT_BUFFER_SECONDS
        self._segments: list[tuple[float, str]] = []  # (timestamp, text)
        self._last_flush: float = time.time()

    def add_segment(self, text: str, is_partial: bool) -> str | None:
        """
        Add a transcript segment. Returns accumulated text if the buffer
        window has elapsed, otherwise None.

        Only finalized (non-partial) segments are accumulated. Partial
        results are ignored to avoid duplication.
        """
        if is_partial:
            return None

        now = time.time()
        self._segments.append((now, text))

        elapsed = now - self._last_flush
        if elapsed >= self._buffer_seconds and self._segments:
            return self.flush()

        return None

    def flush(self) -> str | None:
        """Force-flush the buffer and return accumulated text."""
        if not self._segments:
            return None

        combined = " ".join(text for _, text in self._segments)
        self._segments.clear()
        self._last_flush = time.time()
        return combined.strip() if combined.strip() else None

    @property
    def segment_count(self) -> int:
        return len(self._segments)

    @property
    def has_content(self) -> bool:
        return len(self._segments) > 0
