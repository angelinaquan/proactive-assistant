"""
Real-time speech-to-text transcription engine.

Self-contained streaming transcription using OpenAI Whisper. Implements
tumbling-window segmentation for continuous audio streams — audio chunks
are accumulated and transcribed, with segments closed on silence/repetition.
"""

from __future__ import annotations

import asyncio
import logging
import os
import time
from queue import Queue
from typing import Callable

import numpy as np
import torch
import whisper
from whisper import Whisper

from config import config

logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Model loading
# ---------------------------------------------------------------------------

_models: dict[str, Whisper] = {}


def get_model(file_name: str = "tiny.en.pt") -> Whisper:
    """Load a Whisper model from the local models/ directory (cached)."""
    if file_name not in _models:
        path = os.path.join(os.path.dirname(__file__), "models", file_name)
        if not os.path.exists(path):
            # Fall back to whisper's built-in download
            model_name = file_name.replace(".pt", "").replace(".en", ".en")
            logger.info("Model file not found at %s, loading by name: %s", path, model_name)
            _models[file_name] = whisper.load_model(model_name).to(
                "cuda" if torch.cuda.is_available() else "cpu"
            )
        else:
            _models[file_name] = whisper.load_model(path).to(
                "cuda" if torch.cuda.is_available() else "cpu"
            )
    return _models[file_name]


# ---------------------------------------------------------------------------
# PCM transcription
# ---------------------------------------------------------------------------


def transcribe_pcm_chunks(
    model: Whisper,
    chunks: list[bytes],
    lang: str = "en",
    temperature: float = 0.1,
    log_prob: float = -0.5,
) -> dict:
    """Transcribe a list of PCM audio chunks (16kHz mono int16)."""
    arr = (
        np.frombuffer(b"".join(chunks), np.int16)
        .flatten()
        .astype(np.float32)
        / 32768.0
    )
    return model.transcribe(
        arr,
        fp16=False,
        language=lang,
        logprob_threshold=log_prob,
        temperature=temperature,
    )


async def transcribe_pcm_chunks_async(
    model: Whisper,
    chunks: list[bytes],
    lang: str = "en",
    temperature: float = 0.1,
    log_prob: float = -0.5,
) -> dict:
    """Async wrapper for PCM transcription (runs in thread pool)."""
    return await asyncio.get_running_loop().run_in_executor(
        None, transcribe_pcm_chunks, model, chunks, lang, temperature, log_prob
    )


# ---------------------------------------------------------------------------
# Streaming transcription loop
# ---------------------------------------------------------------------------


def _get_all(queue: Queue) -> list:
    """Drain all items from a queue."""
    items = []
    while queue and not queue.empty():
        items.append(queue.get())
    return items


def _should_close_segment(
    result: dict, prev_result: dict, cycles: int, max_cycles: int = 1
) -> bool:
    """Determine if the current segment should be finalized."""
    return cycles >= max_cycles and result["data"]["text"] == prev_result.get(
        "data", {}
    ).get("text", "")


async def _streaming_transcribe_loop(
    should_stop: list[bool],
    queue: Queue,
    transcriber: Callable,
    segment_closed: Callable,
) -> None:
    """
    Tumbling-window transcription loop.

    Accumulates audio chunks, runs transcription, and emits partial/final
    segments. A segment is closed when the transcription stabilizes
    (same text repeated).
    """
    window: list = []
    prev_result: dict = {}
    cycles = 0

    while not should_stop[0]:
        start = time.time()
        await asyncio.sleep(0.01)
        window.extend(_get_all(queue))

        if not window:
            continue

        result = {
            "is_partial": True,
            "data": await transcriber(window),
            "time": (time.time() - start) * 1000,
        }

        if _should_close_segment(result, prev_result, cycles):
            window, prev_result, cycles = [], {}, 0
            result["is_partial"] = False
        elif result["data"]["text"] == prev_result.get("data", {}).get("text", ""):
            cycles += 1
        else:
            cycles = 0
            prev_result = result

        if result["data"]["text"]:
            await segment_closed(result)


# ---------------------------------------------------------------------------
# AmbientTranscriber (high-level API)
# ---------------------------------------------------------------------------


class AmbientTranscriber:
    """
    Manages a real-time transcription session for ambient listening.

    Audio chunks (PCM 16kHz mono int16) are fed in via `add_audio_chunk()`,
    and transcript segments are emitted via the `on_transcript` callback.
    """

    def __init__(
        self,
        on_transcript: Callable[[str, bool, float], None] | None = None,
    ):
        self._on_transcript = on_transcript
        self._queue: Queue = Queue()
        self._should_stop: list[bool] = [False]
        self._task: asyncio.Task | None = None
        self._model: Whisper | None = None

    async def start(self) -> None:
        """Start the transcription loop."""
        if self._task is not None:
            return

        logger.info("Loading Whisper model: %s", config.WHISPER_MODEL)
        self._model = get_model(config.WHISPER_MODEL)
        self._should_stop[0] = False

        model = self._model

        async def transcribe_async(chunks: list) -> dict:
            return await transcribe_pcm_chunks_async(
                model, chunks, lang=config.WHISPER_LANGUAGE
            )

        async def on_segment(result: dict) -> None:
            text = result.get("data", {}).get("text", "").strip()
            is_partial = result.get("is_partial", True)
            latency_ms = result.get("time", 0.0)
            if text and self._on_transcript:
                self._on_transcript(text, is_partial, latency_ms)

        self._task = asyncio.create_task(
            _streaming_transcribe_loop(
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


# ---------------------------------------------------------------------------
# TranscriptBuffer
# ---------------------------------------------------------------------------


class TranscriptBuffer:
    """
    Accumulates transcript segments over a time window for batch extraction.

    Collects finalized (non-partial) transcript segments and yields them
    for LLM extraction once the buffer reaches the configured duration.
    """

    def __init__(self, buffer_seconds: int | None = None):
        self._buffer_seconds = buffer_seconds or config.TRANSCRIPT_BUFFER_SECONDS
        self._segments: list[tuple[float, str]] = []
        self._last_flush: float = time.time()

    def add_segment(self, text: str, is_partial: bool) -> str | None:
        if is_partial:
            return None

        now = time.time()
        self._segments.append((now, text))

        elapsed = now - self._last_flush
        if elapsed >= self._buffer_seconds and self._segments:
            return self.flush()

        return None

    def flush(self) -> str | None:
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
