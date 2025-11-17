#!/bin/bash
#
# SSM Session Wrapper Script - Command Logging and Recording
# This script logs all commands executed during an SSM session
# Place this at: /usr/local/bin/ssm-session-wrapper.sh on target instances
#
# Installation on EC2 instances:
# 1. sudo mkdir -p /usr/local/bin
# 2. sudo cp ssm-session-wrapper.sh /usr/local/bin/
# 3. sudo chmod +x /usr/local/bin/ssm-session-wrapper.sh
#

# Get session information
SESSION_ID="${SESSION_ID:-unknown}"
SESSION_OWNER="${SESSION_OWNER:-unknown}"
INSTANCE_ID=$(ec2-metadata --instance-id 2>/dev/null | cut -d " " -f 2 || echo "unknown")
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

# Log directory
LOG_DIR="/var/log/ssm-sessions"
sudo mkdir -p "$LOG_DIR"

# Session log file
SESSION_LOG="$LOG_DIR/session-${SESSION_OWNER}-${TIMESTAMP}.log"

# Log session start
{
    echo "=============================================="
    echo "SSM Session Started"
    echo "=============================================="
    echo "Session ID: $SESSION_ID"
    echo "User: $SESSION_OWNER"
    echo "Instance: $INSTANCE_ID"
    echo "Start Time: $(date '+%Y-%m-%d %H:%M:%S %Z')"
    echo "=============================================="
    echo ""
} | sudo tee -a "$SESSION_LOG"

# Function to log commands
log_command() {
    local cmd="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $SESSION_OWNER: $cmd" | sudo tee -a "$SESSION_LOG"
}

# Export the logging function so it's available in the shell
export -f log_command
export SESSION_LOG
export SESSION_OWNER

# Set up bash prompt to log commands
if [ -n "$BASH_VERSION" ]; then
    # Create a custom PROMPT_COMMAND to log each command
    export PROMPT_COMMAND='LAST_CMD=$(history 1 | sed "s/^[ ]*[0-9]*[ ]*//"); if [ -n "$LAST_CMD" ] && [ "$LAST_CMD" != "$PREV_CMD" ]; then echo "[$(date +"%Y-%m-%d %H:%M:%S")] $SESSION_OWNER: $LAST_CMD" | sudo tee -a "$SESSION_LOG" >/dev/null; export PREV_CMD="$LAST_CMD"; fi'

    # Enhanced prompt
    export PS1="\[\033[1;32m\][\u@\h \W]\\$\[\033[0m\] "

    # Enable command history
    export HISTFILE="$LOG_DIR/.bash_history_${SESSION_OWNER}_${TIMESTAMP}"
    export HISTSIZE=10000
    export HISTFILESIZE=10000
    export HISTTIMEFORMAT="%Y-%m-%d %H:%M:%S  "
fi

# Trap exit to log session end
trap 'echo "" | sudo tee -a "$SESSION_LOG"; echo "=============================================="; echo "SSM Session Ended"; echo "End Time: $(date +"%Y-%m-%d %H:%M:%S %Z")"; echo "==============================================" | sudo tee -a "$SESSION_LOG"' EXIT

# Start bash shell (interactive, non-login to avoid profile issues)
exec /bin/bash
