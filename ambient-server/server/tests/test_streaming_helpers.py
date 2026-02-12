"""Tests for streaming transcription helper functions."""

import sys
import unittest.mock
from pathlib import Path
from queue import Queue

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

# Mock heavy imports
sys.modules.setdefault("torch", unittest.mock.MagicMock())
sys.modules.setdefault("whisper", unittest.mock.MagicMock())
sys.modules.setdefault("numpy", unittest.mock.MagicMock())

from transcription import _get_all, _should_close_segment


def test_get_all_empty_queue():
    q = Queue()
    assert _get_all(q) == []


def test_get_all_drains_queue():
    q = Queue()
    q.put("a")
    q.put("b")
    q.put("c")
    result = _get_all(q)
    assert result == ["a", "b", "c"]
    assert q.empty()


def test_get_all_mixed_types():
    q = Queue()
    q.put(b"audio1")
    q.put(b"audio2")
    result = _get_all(q)
    assert len(result) == 2
    assert result[0] == b"audio1"


def test_should_close_segment_same_text_enough_cycles():
    result = {"data": {"text": "hello"}}
    prev = {"data": {"text": "hello"}}
    assert _should_close_segment(result, prev, cycles=1, max_cycles=1) is True
    assert _should_close_segment(result, prev, cycles=2, max_cycles=1) is True


def test_should_close_segment_different_text():
    result = {"data": {"text": "hello world"}}
    prev = {"data": {"text": "hello"}}
    assert _should_close_segment(result, prev, cycles=5, max_cycles=1) is False


def test_should_close_segment_not_enough_cycles():
    result = {"data": {"text": "hello"}}
    prev = {"data": {"text": "hello"}}
    assert _should_close_segment(result, prev, cycles=0, max_cycles=1) is False


def test_should_close_segment_empty_prev():
    result = {"data": {"text": "hello"}}
    prev = {}
    assert _should_close_segment(result, prev, cycles=5, max_cycles=1) is False


def test_should_close_segment_custom_max_cycles():
    result = {"data": {"text": "hello"}}
    prev = {"data": {"text": "hello"}}
    assert _should_close_segment(result, prev, cycles=2, max_cycles=3) is False
    assert _should_close_segment(result, prev, cycles=3, max_cycles=3) is True
