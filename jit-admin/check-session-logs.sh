#!/usr/bin/env bash
set -euo pipefail
#
# Check SSM Session Logs
# Usage: ./check-session-logs.sh USERNAME [REGION]
#

USERNAME="${1:-}"
REGION="${2:-ap-southeast-1}"

if [ -z "$USERNAME" ]; then
  echo "Usage: $0 USERNAME [REGION]"
  echo ""
  echo "Example:"
  echo "  $0 vinson-devops ap-southeast-1"
  exit 1
fi

echo "🔍 Checking SSM Session Logs for: $USERNAME"
echo "Region: $REGION"
echo "=============================================="
echo ""

# 1. Check S3 logs
echo "📦 S3 Logs (ssm-onetime-logs-vortech-dev/sessions/)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

S3_LOGS=$(aws s3 ls s3://ssm-onetime-logs-vortech-dev/sessions/ --region "$REGION" 2>/dev/null | grep "$USERNAME" || echo "")

if [ -n "$S3_LOGS" ]; then
  echo "✅ Found logs in S3:"
  echo "$S3_LOGS"
  echo ""

  # Get latest log
  LATEST_LOG=$(echo "$S3_LOGS" | tail -1 | awk '{print $4}')

  echo "📄 Latest log: $LATEST_LOG"
  echo ""
  read -p "Download and view this log? [y/N] " -n 1 -r
  echo ""

  if [[ $REPLY =~ ^[Yy]$ ]]; then
    aws s3 cp "s3://ssm-onetime-logs-vortech-dev/sessions/$LATEST_LOG" \
      "./session-log-$LATEST_LOG" \
      --region "$REGION"

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Log Content:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    cat "./session-log-$LATEST_LOG"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "✅ Log saved to: ./session-log-$LATEST_LOG"
  fi
else
  echo "⚠️  No S3 logs found yet for $USERNAME"
  echo ""
  echo "💡 S3 logs take 5-15 minutes to upload after session ends"
  echo "   Try checking CloudWatch logs below for real-time data"
fi

echo ""
echo "📊 CloudWatch Logs (/aws/ssm/onetime-sessions-dev)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Get timestamp from 1 hour ago
START_TIME=$(($(date +%s) - 3600))000

CW_LOGS=$(aws logs filter-log-events \
  --log-group-name /aws/ssm/onetime-sessions-dev \
  --filter-pattern "$USERNAME" \
  --start-time "$START_TIME" \
  --region "$REGION" \
  --max-items 20 \
  --query 'events[*].[timestamp,message]' \
  --output text 2>&1 || echo "")

if echo "$CW_LOGS" | grep -q "$USERNAME"; then
  echo "✅ Found CloudWatch logs:"
  echo ""
  echo "$CW_LOGS" | while read -r timestamp message; do
    if [ -n "$timestamp" ]; then
      # Convert timestamp to readable date
      date_readable=$(date -r "$((timestamp / 1000))" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "$timestamp")
      echo "[$date_readable] $message"
    fi
  done
else
  echo "⚠️  No CloudWatch logs found yet for $USERNAME"
fi

echo ""
echo "📋 Session History"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

SESSIONS=$(aws ssm describe-sessions \
  --state History \
  --region "$REGION" \
  --max-results 20 \
  --query "Sessions[?contains(Owner, '$USERNAME')].[SessionId,Status,StartDate,EndDate]" \
  --output table 2>/dev/null || echo "")

if [ -n "$SESSIONS" ]; then
  echo "$SESSIONS"
else
  echo "⚠️  No session history found for $USERNAME"
fi

echo ""
echo "=============================================="
echo "✅ Log check complete!"
echo ""
echo "💡 Tips:"
echo "   - S3 logs appear 5-15 min after session ends"
echo "   - CloudWatch has real-time streaming"
echo "   - Session history shows all past sessions"
echo ""
