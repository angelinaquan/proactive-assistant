#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

case "${1:--help}" in
  -local)
    echo "=== Setting up local environment ==="
    python3 -m venv .venv
    source .venv/bin/activate
    pip install -r requirements.txt
    echo "=== Running tests ==="
    python3 -m pytest tests/ -v
    echo "=== Setup complete. Activate with: source .venv/bin/activate ==="
    ;;
  -test)
    echo "=== Running tests ==="
    python3 -m pytest tests/ -v
    ;;
  -run)
    echo "=== Starting Ambient Intelligence Server ==="
    python3 main.py
    ;;
  -help|*)
    echo "Ambient Intelligence Server"
    echo ""
    echo "Usage: ./run.sh [command]"
    echo ""
    echo "Commands:"
    echo "  -local    Setup environment, install deps, run tests"
    echo "  -test     Run tests only"
    echo "  -run      Start the server"
    echo "  -help     Show this help"
    ;;
esac
