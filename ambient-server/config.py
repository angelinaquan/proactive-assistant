"""Configuration for the ambient listening server."""

import os
from dotenv import load_dotenv

load_dotenv()


class AmbientConfig:
    """Central configuration for the ambient intelligence server."""

    # Server
    HOST: str = os.getenv("AMBIENT_HOST", "0.0.0.0")
    PORT: int = int(os.getenv("AMBIENT_PORT", "8200"))

    # WhisperFlow
    WHISPER_MODEL: str = os.getenv("WHISPER_MODEL", "tiny.en.pt")
    WHISPER_LANGUAGE: str = os.getenv("WHISPER_LANGUAGE", "en")

    # LLM Extraction
    OPENAI_API_KEY: str = os.getenv("OPENAI_API_KEY", "")
    OPENAI_MODEL: str = os.getenv("OPENAI_MODEL", "gpt-4o-mini")
    OPENAI_BASE_URL: str = os.getenv("OPENAI_BASE_URL", "https://api.openai.com/v1")

    # Confidence thresholds
    AUTO_EXECUTE_THRESHOLD: float = float(
        os.getenv("AUTO_EXECUTE_THRESHOLD", "0.8")
    )
    SUGGESTION_THRESHOLD: float = float(
        os.getenv("SUGGESTION_THRESHOLD", "0.5")
    )

    # Transcript buffering
    TRANSCRIPT_BUFFER_SECONDS: int = int(
        os.getenv("TRANSCRIPT_BUFFER_SECONDS", "45")
    )
    DEDUP_WINDOW_SECONDS: int = int(os.getenv("DEDUP_WINDOW_SECONDS", "300"))

    # Undo window (sent to clients as recommendation)
    UNDO_WINDOW_SECONDS: int = int(os.getenv("UNDO_WINDOW_SECONDS", "1800"))

    # Audio
    SAMPLE_RATE: int = 16000
    CHANNELS: int = 1
    SAMPLE_WIDTH: int = 2  # 16-bit = 2 bytes


config = AmbientConfig()
