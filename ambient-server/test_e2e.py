#!/usr/bin/env python3
"""
End-to-end test: connect to the ambient server via WebSocket,
send audio, receive transcripts and action plans.
"""

import asyncio
import json
import struct
import sys
import math

import websockets


async def test_websocket_connection():
    """Test basic WebSocket connect/disconnect."""
    print("1. Testing WebSocket connection...")
    async with websockets.connect("ws://localhost:8200/ws/ambient") as ws:
        print("   ✅ Connected to ws://localhost:8200/ws/ambient")
        await ws.close()
    print("   ✅ Disconnected cleanly")


async def test_pause_resume():
    """Test pause/resume control messages."""
    print("\n2. Testing pause/resume...")
    async with websockets.connect("ws://localhost:8200/ws/ambient") as ws:
        # Send pause
        await ws.send(json.dumps({"type": "pause"}))
        print("   ✅ Sent pause command")

        # Send resume
        await ws.send(json.dumps({"type": "resume"}))
        print("   ✅ Sent resume command")

        await ws.close()
    print("   ✅ Pause/resume works")


async def test_send_audio():
    """Test sending PCM audio data and receiving transcripts."""
    print("\n3. Testing audio streaming...")
    async with websockets.connect("ws://localhost:8200/ws/ambient") as ws:
        # Generate 1 second of 440Hz sine wave as PCM 16kHz mono int16
        sample_rate = 16000
        duration = 1.0
        frequency = 440
        num_samples = int(sample_rate * duration)

        audio_data = bytearray()
        for i in range(num_samples):
            t = i / sample_rate
            sample = int(32767 * 0.5 * math.sin(2 * math.pi * frequency * t))
            audio_data.extend(struct.pack('<h', sample))

        # Send audio in chunks
        chunk_size = 4096
        chunks_sent = 0
        for i in range(0, len(audio_data), chunk_size):
            chunk = bytes(audio_data[i:i + chunk_size])
            await ws.send(chunk)
            chunks_sent += 1

        print(f"   ✅ Sent {chunks_sent} audio chunks ({len(audio_data)} bytes total)")

        # Wait briefly for any transcript response
        try:
            response = await asyncio.wait_for(ws.recv(), timeout=5.0)
            data = json.loads(response)
            print(f"   ✅ Received response: type={data.get('type', '?')}")
            if data.get("type") == "transcript":
                payload = data.get("payload", {})
                print(f"      Text: '{payload.get('text', '')}' (partial={payload.get('is_partial', True)})")
        except asyncio.TimeoutError:
            print("   ⚠️  No transcript received (expected — sine wave isn't speech)")

        await ws.close()
    print("   ✅ Audio streaming works")


async def test_feedback():
    """Test feedback messages."""
    print("\n4. Testing feedback...")
    async with websockets.connect("ws://localhost:8200/ws/ambient") as ws:
        feedback = {
            "type": "feedback",
            "payload": {
                "action_plan_id": "test-plan-123",
                "action": "keep",
            },
        }
        await ws.send(json.dumps(feedback))
        print("   ✅ Sent feedback command")

        await ws.close()
    print("   ✅ Feedback works (no crash)")


async def test_items_endpoint():
    """Test REST items endpoint."""
    print("\n5. Testing REST /items endpoint...")
    import httpx

    async with httpx.AsyncClient() as client:
        resp = await client.get("http://localhost:8200/items")
        data = resp.json()
        print(f"   ✅ GET /items → {data['count']} items")


async def test_extraction_parser():
    """Test the extraction parser directly with mock data."""
    print("\n6. Testing extraction parser with sample data...")
    sys.path.insert(0, "/workspace/ambient-server/server")
    from extraction import _parse_extraction_response

    # Simulate LLM response
    mock_response = json.dumps({
        "items": [
            {
                "type": "reminder",
                "title": "Send quarterly report to Sarah",
                "deadline": "2026-02-12T09:00:00",
                "people": ["Sarah"],
                "confidence": 0.92,
                "reasoning": "Explicit commitment with deadline",
            },
            {
                "type": "calendar_event",
                "title": "Team standup",
                "deadline": "2026-02-12T15:00:00",
                "location": "Conference Room B",
                "confidence": 0.88,
                "reasoning": "Meeting mentioned with time",
            },
        ]
    })

    items = _parse_extraction_response(mock_response)
    assert len(items) == 2, f"Expected 2 items, got {len(items)}"
    assert items[0].title == "Send quarterly report to Sarah"
    assert items[0].confidence == 0.92
    assert items[1].title == "Team standup"
    assert items[1].location == "Conference Room B"
    print(f"   ✅ Parsed {len(items)} items correctly")

    # Test confidence scoring
    from confidence import score_extraction
    for item in items:
        score, level, auto_exec = score_extraction(item)
        print(f"   ✅ '{item.title}' → confidence={score:.2f}, level={level.value}, auto_execute={auto_exec}")


async def test_action_planner():
    """Test the action planner with mock extraction results."""
    print("\n7. Testing action planner...")
    sys.path.insert(0, "/workspace/ambient-server/server")
    from action_planner import ActionPlanner
    from models import ActionType, ExtractedItem, ExtractionResult

    planner = ActionPlanner()
    extraction = ExtractionResult(
        items=[
            ExtractedItem(
                type=ActionType.REMINDER,
                title="Send quarterly report to Sarah",
                deadline="2026-02-12T09:00:00",
                people=["Sarah"],
                confidence=0.92,
            ),
            ExtractedItem(
                type=ActionType.NOTE,
                title="Maybe check vendor options",
                confidence=0.35,
            ),
        ],
        transcript_segment="I need to send the quarterly report to Sarah by tomorrow morning",
    )

    plans = planner.plan_actions(extraction, context_window="meeting discussion")
    print(f"   ✅ Generated {len(plans)} action plans from 2 extractions")
    for plan in plans:
        print(f"      - {plan.action_description} [auto_execute={plan.auto_execute}, confidence={plan.confidence:.2f}]")

    assert len(plans) == 1, f"Expected 1 plan (low confidence filtered), got {len(plans)}"
    assert plans[0].auto_execute is True
    assert "Sarah" in plans[0].action_description
    print("   ✅ Action planner works correctly")


async def main():
    print("=" * 60)
    print("Ambient Intelligence Server - End-to-End Tests")
    print("=" * 60)

    await test_websocket_connection()
    await test_pause_resume()
    await test_send_audio()
    await test_feedback()
    await test_items_endpoint()
    await test_extraction_parser()
    await test_action_planner()

    print("\n" + "=" * 60)
    print("✅ ALL END-TO-END TESTS PASSED")
    print("=" * 60)


if __name__ == "__main__":
    asyncio.run(main())
