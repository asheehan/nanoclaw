#!/bin/bash
# Setup script for NanoClaw systemd service
# Run this on your VPS host (not inside the container)

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}NanoClaw Systemd Service Setup${NC}"
echo "========================================"
echo ""

# Get the actual project directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "Project root: $PROJECT_ROOT"
echo "Current user: $(whoami)"
echo ""

# Check if running as root
if [ "$EUID" -eq 0 ]; then
   echo -e "${YELLOW}Note: Running as root. Service will be installed system-wide.${NC}"
else
   echo -e "${YELLOW}Note: Not running as root. Will use sudo for installation.${NC}"
   SUDO="sudo"
fi

# Get actual paths
NODE_PATH=$(which node)
USER_NAME=$(whoami)

echo "Node path: $NODE_PATH"
echo "User: $USER_NAME"
echo ""

# Create a temporary service file with actual paths
TEMP_SERVICE="/tmp/nanoclaw.service"
cat > "$TEMP_SERVICE" <<EOF
[Unit]
Description=NanoClaw WhatsApp Assistant
After=network.target

[Service]
Type=simple
User=$USER_NAME
WorkingDirectory=$PROJECT_ROOT
ExecStart=$NODE_PATH $PROJECT_ROOT/dist/index.js
Restart=always
RestartSec=10
StandardOutput=append:$PROJECT_ROOT/logs/nanoclaw.log
StandardError=append:$PROJECT_ROOT/logs/nanoclaw.error.log

# Environment variables
Environment="NODE_ENV=production"
Environment="ASSISTANT_NAME=Claude"

[Install]
WantedBy=multi-user.target
EOF

echo "Generated service file at $TEMP_SERVICE"
echo ""
echo -e "${YELLOW}Service file contents:${NC}"
cat "$TEMP_SERVICE"
echo ""

# Ask for confirmation
read -p "Install this service? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${RED}Installation cancelled.${NC}"
    rm "$TEMP_SERVICE"
    exit 1
fi

# Install the service
echo ""
echo "Installing service..."
$SUDO cp "$TEMP_SERVICE" /etc/systemd/system/nanoclaw.service
$SUDO systemctl daemon-reload

echo -e "${GREEN}✓ Service installed${NC}"
rm "$TEMP_SERVICE"

# Enable the service
echo ""
read -p "Enable service to start on boot? (Y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Nn]$ ]]; then
    $SUDO systemctl enable nanoclaw
    echo -e "${GREEN}✓ Service enabled${NC}"
fi

# Setup sudo permissions for restart
echo ""
echo "Setting up sudo permissions for restart..."
SUDOERS_FILE="/etc/sudoers.d/nanoclaw-restart"
echo "$USER_NAME ALL=(ALL) NOPASSWD: /usr/bin/systemctl restart nanoclaw" | $SUDO tee "$SUDOERS_FILE" > /dev/null
echo "$USER_NAME ALL=(ALL) NOPASSWD: /usr/bin/systemctl status nanoclaw" | $SUDO tee -a "$SUDOERS_FILE" > /dev/null
$SUDO chmod 0440 "$SUDOERS_FILE"
echo -e "${GREEN}✓ Sudo permissions configured${NC}"

# Check if nanoclaw is currently running
echo ""
if pgrep -f "node.*dist/index.js" > /dev/null; then
    echo -e "${YELLOW}NanoClaw appears to be running already.${NC}"
    read -p "Stop existing process and start via systemd? (y/N) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "Stopping existing process..."
        pkill -f "node.*dist/index.js" || true
        sleep 2
        echo "Starting service..."
        $SUDO systemctl start nanoclaw
    fi
else
    read -p "Start the service now? (Y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        $SUDO systemctl start nanoclaw
        echo -e "${GREEN}✓ Service started${NC}"
    fi
fi

# Show status
echo ""
echo "========================================"
echo -e "${GREEN}Setup Complete!${NC}"
echo "========================================"
echo ""
echo "Useful commands:"
echo "  sudo systemctl status nanoclaw   # Check status"
echo "  sudo systemctl restart nanoclaw  # Restart service"
echo "  sudo systemctl stop nanoclaw     # Stop service"
echo "  sudo systemctl start nanoclaw    # Start service"
echo "  journalctl -u nanoclaw -f        # Follow service logs"
echo ""
echo "Service logs are also at:"
echo "  $PROJECT_ROOT/logs/nanoclaw.log"
echo "  $PROJECT_ROOT/logs/nanoclaw.error.log"
echo ""

# Show current status
$SUDO systemctl status nanoclaw --no-pager || true
