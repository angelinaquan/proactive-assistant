"""Tests for TranscriptBuffer."""

import sys
import time
import unittest.mock
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

# Mock heavy imports that TranscriptBuffer doesn't need
sys.modules.setdefault("torch", unittest.mock.MagicMock())
sys.modules.setdefault("whisper", unittest.mock.MagicMock())
sys.modules.setdefault("numpy", unittest.mock.MagicMock())

from transcription import TranscriptBuffer


def test_buffer_ignores_partial():
    """Partial segments should not be accumulated."""
    buf = TranscriptBuffer(buffer_seconds=30)
    result = buf.add_segment("partial text", is_partial=True)
    assert result is None
    assert buf.segment_count == 0


def test_buffer_accumulates_final():
    """Final segments should be accumulated."""
    buf = TranscriptBuffer(buffer_seconds=60)
    result = buf.add_segment("final text", is_partial=False)
    # Not enough time has passed, so no flush yet
    assert result is None
    assert buf.segment_count == 1


def test_buffer_flush():
    """Manual flush should return accumulated text."""
    buf = TranscriptBuffer(buffer_seconds=60)
    buf.add_segment("segment one", is_partial=False)
    buf.add_segment("segment two", is_partial=False)

    result = buf.flush()
    assert result is not None
    assert "segment one" in result
    assert "segment two" in result
    assert buf.segment_count == 0


def test_buffer_flush_empty():
    """Flush on empty buffer returns None."""
    buf = TranscriptBuffer(buffer_seconds=60)
    result = buf.flush()
    assert result is None


def test_buffer_auto_flush_on_window():
    """Buffer should auto-flush when time window elapses."""
    buf = TranscriptBuffer(buffer_seconds=60)  # Long window
    buf.add_segment("first", is_partial=False)
    buf.add_segment("second", is_partial=False)
    assert buf.segment_count == 2

    # Force the last_flush time to be in the past so next add triggers flush
    buf._last_flush = time.time() - 120

    result = buf.add_segment("third", is_partial=False)
    assert result is not None
    assert "first" in result
    assert "second" in result
    assert "third" in result
    assert buf.segment_count == 0


def test_buffer_has_content():
    buf = TranscriptBuffer(buffer_seconds=60)
    assert buf.has_content is False

    buf.add_segment("text", is_partial=False)
    assert buf.has_content is True

    buf.flush()
    assert buf.has_content is False


def test_buffer_strips_whitespace():
    """Flushed text should be stripped."""
    buf = TranscriptBuffer(buffer_seconds=60)
    buf.add_segment("  text with spaces  ", is_partial=False)
    result = buf.flush()
    assert result == "text with spaces"


def test_buffer_empty_segments_not_returned():
    """If only whitespace segments, flush returns None."""
    buf = TranscriptBuffer(buffer_seconds=60)
    buf.add_segment("   ", is_partial=False)
    result = buf.flush()
    assert result is None
