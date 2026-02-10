#!/bin/bash
# Build and restart NanoClaw service
# This allows the agent to apply code changes

set -e

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

echo "Building NanoClaw..."
npm run build

if [ $? -eq 0 ]; then
    echo "Build successful!"
    echo "Restarting service..."
    sudo systemctl restart nanoclaw
    echo "Service restarted!"

    # Wait a moment and check status
    sleep 2
    sudo systemctl status nanoclaw --no-pager
else
    echo "Build failed! Not restarting service."
    exit 1
fi
