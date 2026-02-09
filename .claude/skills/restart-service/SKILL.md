---
name: restart-service
description: Add ability to restart the NanoClaw service from within the agent. Useful for applying code changes, clearing state, or recovering from errors without manual SSH access.
---

# Restart NanoClaw Service

This skill adds the ability to restart the NanoClaw WhatsApp service from within an agent conversation. This is useful when:
- Applying code changes (after `npm run build`)
- Clearing connection state
- Recovering from errors
- Testing new configurations

**Safety Note**: This skill allows the agent to restart its own parent process. Use with appropriate permissions and consider the security implications for your deployment.

---

## Implementation Options

Choose the approach that matches your deployment:

### Option A: Systemd Service (Recommended for Linux VPS)

If NanoClaw is running as a systemd service, this is the cleanest approach.

#### Step 1: Create Systemd Service File

Create `/etc/systemd/system/nanoclaw.service` (requires root):

```ini
[Unit]
Description=NanoClaw WhatsApp Assistant
After=network.target

[Service]
Type=simple
User=nanoclaw
WorkingDirectory=/home/nanoclaw/nanoclaw
ExecStart=/usr/bin/node /home/nanoclaw/nanoclaw/dist/index.js
Restart=always
RestartSec=10
StandardOutput=append:/home/nanoclaw/nanoclaw/logs/nanoclaw.log
StandardError=append:/home/nanoclaw/nanoclaw/logs/nanoclaw.error.log

# Environment variables
Environment="NODE_ENV=production"
Environment="ASSISTANT_NAME=Andy"

[Install]
WantedBy=multi-user.target
```

**Adjust paths**:
- Replace `/home/nanoclaw/nanoclaw` with your actual project path
- Replace `nanoclaw` user with your actual user
- Update `ASSISTANT_NAME` if different

#### Step 2: Enable and Start Service

```bash
sudo systemctl daemon-reload
sudo systemctl enable nanoclaw
sudo systemctl start nanoclaw
```

#### Step 3: Allow User to Restart Without Password

Add sudo permission for the restart command. Edit `/etc/sudoers` (use `visudo`):

```
nanoclaw ALL=(ALL) NOPASSWD: /usr/bin/systemctl restart nanoclaw
nanoclaw ALL=(ALL) NOPASSWD: /usr/bin/systemctl status nanoclaw
```

Replace `nanoclaw` with your actual username.

#### Step 4: Test Restart

The agent can now restart the service:

```bash
sudo systemctl restart nanoclaw
```

And check status:

```bash
sudo systemctl status nanoclaw
```

---

### Option B: PM2 Process Manager

If you're using PM2 to manage the process:

#### Step 1: Install PM2

```bash
npm install -g pm2
```

#### Step 2: Create PM2 Ecosystem File

Create `ecosystem.config.js` in your project root:

```javascript
module.exports = {
  apps: [{
    name: 'nanoclaw',
    script: './dist/index.js',
    cwd: '/home/nanoclaw/nanoclaw',
    instances: 1,
    autorestart: true,
    watch: false,
    max_memory_restart: '500M',
    env: {
      NODE_ENV: 'production',
      ASSISTANT_NAME: 'Andy'
    },
    error_file: './logs/nanoclaw.error.log',
    out_file: './logs/nanoclaw.log',
    log_date_format: 'YYYY-MM-DD HH:mm:ss Z'
  }]
};
```

#### Step 3: Start with PM2

```bash
pm2 start ecosystem.config.js
pm2 save  # Save the process list
pm2 startup  # Generate startup script (follow the instructions)
```

#### Step 4: Restart Commands

The agent can restart using:

```bash
pm2 restart nanoclaw
```

Check status:

```bash
pm2 status nanoclaw
pm2 logs nanoclaw --lines 50
```

---

### Option C: Signal-Based Restart (Simple)

This approach uses process signals without external process managers.

#### Step 1: Create Restart Script

Create `scripts/restart.sh` in your project root:

```bash
#!/bin/bash
set -e

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

echo "Finding NanoClaw process..."
PID=$(pgrep -f "node.*dist/index.js" | head -1)

if [ -z "$PID" ]; then
  echo "NanoClaw is not running. Starting..."
  nohup node dist/index.js > logs/nanoclaw.log 2> logs/nanoclaw.error.log &
  echo "Started with PID: $!"
  exit 0
fi

echo "Stopping NanoClaw (PID: $PID)..."
kill $PID

# Wait for process to stop
for i in {1..10}; do
  if ! kill -0 $PID 2>/dev/null; then
    break
  fi
  sleep 1
done

# Force kill if still running
if kill -0 $PID 2>/dev/null; then
  echo "Force stopping..."
  kill -9 $PID
fi

echo "Starting NanoClaw..."
nohup node dist/index.js > logs/nanoclaw.log 2> logs/nanoclaw.error.log &
NEW_PID=$!
echo "Started with PID: $NEW_PID"

# Wait a moment and verify it started
sleep 2
if kill -0 $NEW_PID 2>/dev/null; then
  echo "✓ NanoClaw restarted successfully"
else
  echo "✗ Failed to start NanoClaw"
  exit 1
fi
```

Make it executable:

```bash
chmod +x scripts/restart.sh
```

#### Step 2: Usage

The agent can restart using:

```bash
./scripts/restart.sh
```

---

### Option D: Docker Container Restart

If running in Docker:

```bash
# Restart the container
docker restart nanoclaw-container

# Or if using docker-compose
docker-compose restart
```

---

## Usage in Conversation

Once set up, the agent can restart the service when needed:

**Example conversations:**

> User: "I just updated the code, please restart the service"
>
> Agent: *Runs appropriate restart command*
>
> Agent: "Service restarted. The new code should be active now."

**Automatic restarts after builds:**

When the agent runs `npm run build` and commits changes, they can automatically restart to apply them.

---

## Safety Considerations

### Permissions

- **Systemd**: Requires sudo permission for restart (configured in sudoers)
- **PM2**: User must have permission to run PM2 commands
- **Script**: User must have permission to kill processes they own
- **Docker**: User must be in the docker group

### Race Conditions

When the service restarts, the current agent container will be orphaned (its parent dies). The container will complete its current task but won't be able to send messages back. Consider:

1. Send a message "Restarting service..." BEFORE the restart
2. Keep restart commands at the END of the agent's work
3. Don't expect responses after restart

### Alternative: Delayed Restart

For a cleaner experience, create a delayed restart script:

```bash
#!/bin/bash
# Delayed restart - gives the agent time to respond first
sleep 5 && /path/to/restart.sh &
```

The agent can use this to respond "Restarting in 5 seconds..." and exit gracefully.

---

## Testing

### Test Manual Restart

```bash
# Systemd
sudo systemctl restart nanoclaw

# PM2
pm2 restart nanoclaw

# Script
./scripts/restart.sh
```

### Test from Agent

Send a message like "@Andy restart the service" and verify:
1. Agent attempts the restart
2. Service goes down briefly
3. Service comes back up
4. New messages work after restart

### Verify Logs

Check that logs show the restart:

```bash
tail -f logs/nanoclaw.log
# Should show: connection closed, new connection opened
```

---

## Troubleshooting

### Permission Denied

**Issue**: `sudo: no tty present and no askpass program specified`

**Solution**: Configure passwordless sudo in `/etc/sudoers` (see Step 3 in Option A)

### Service Won't Start

**Issue**: Service stops but doesn't restart

**Solution**:
- Check logs: `tail -f logs/nanoclaw.error.log`
- Verify working directory is correct
- Ensure dist/index.js exists and is executable

### Agent Loses Connection

**Issue**: Agent stops responding after restart

**Expected**: This is normal - the parent process died. The agent container completes but can't send further messages. Send a new message to start a fresh agent with the new service.

---

## Notes for Upstream

**Use Case**: This skill is particularly useful for development/testing where you're frequently updating code. For production, consider:
- Automated deployments with proper CI/CD
- Blue-green deployments for zero-downtime updates
- Health checks and automatic rollback

**Security**: Carefully consider who has access to trigger restarts. In a shared group, you may want to restrict this to the main/admin channel only.

**Alternative**: Instead of restarting, consider implementing hot-reload where the service watches for code changes and reloads automatically. This is more complex but provides a better user experience.
