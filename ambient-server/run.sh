#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

case "${1:--help}" in
  -local)
    echo "=== Setting up local environment ==="
    cd "$SCRIPT_DIR"
    python3 -m venv .venv
    source .venv/bin/activate
    pip install -r requirements.txt
    echo "=== Running tests ==="
    cd "$SCRIPT_DIR/server"
    python3 -m pytest tests/ -v
    echo "=== Setup complete ==="
    ;;
  -test)
    echo "=== Running tests ==="
    cd "$SCRIPT_DIR/server"
    python3 -m pytest tests/ -v
    ;;
  -run)
    echo "=== Starting Ambient Intelligence Server ==="
    cd "$SCRIPT_DIR/server"
    python3 main.py
    ;;
  -help|*)
    echo "Ambient Intelligence System"
    echo ""
    echo "Usage: ./run.sh [command]"
    echo ""
    echo "Commands:"
    echo "  -local    Setup venv, install deps, run tests"
    echo "  -test     Run server tests"
    echo "  -run      Start the ambient server"
    echo "  -help     Show this help"
    echo ""
    echo "iOS app: open ios/project.yml with XcodeGen"
    ;;
esac
