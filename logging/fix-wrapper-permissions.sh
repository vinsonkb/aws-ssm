#!/bin/bash
set -euo pipefail

echo "🔧 Fixing SSM Session Wrapper Permissions"
echo "=========================================="

# Get configuration
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
BUCKET_NAME="ssm-session-logs-${ACCOUNT_ID}"
INSTANCE_ID="i-0ee0bc84a481f7852"

echo "Configuration:"
echo "  S3 Bucket: $BUCKET_NAME"
echo "  Instance: $INSTANCE_ID"
echo ""

# Create fixed wrapper script
echo "📝 Creating fixed wrapper script..."
cat > /tmp/ssm-session-wrapper-fixed.sh << 'WRAPPER_EOF'
#!/bin/bash
set -euo pipefail

# Session metadata
SESSION_ID="${AWS_SSM_SESSION_ID:-unknown-$(date +%s)}"
INSTANCE_ID=$(ec2-metadata --instance-id 2>/dev/null | cut -d " " -f 2 || echo "unknown")
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
IAM_USER="${AWS_SSM_TARGET_ID:-unknown}"

# Extract username from ARN if available
if [[ "$IAM_USER" =~ arn:aws:iam::[0-9]+:user/(.+) ]]; then
    IAM_USERNAME="${BASH_REMATCH[1]}"
else
    IAM_USERNAME="${IAM_USER}"
fi

# Configuration (will be replaced by setup script)
S3_BUCKET="S3_BUCKET_PLACEHOLDER"
CLOUDWATCH_LOG_GROUP="CLOUDWATCH_LOG_GROUP_PLACEHOLDER"
AWS_REGION="AWS_REGION_PLACEHOLDER"

# Log directory and files - use temp for session, upload on exit
TMP_DIR=$(mktemp -d)
TEXT_LOG="${TMP_DIR}/session.log"
RECORDING_FILE="${TMP_DIR}/session.cast"
COMMANDS_LOG="${TMP_DIR}/commands.txt"
METADATA_LOG="${TMP_DIR}/metadata.json"

# Create metadata
cat > "$METADATA_LOG" <<EOF
{
  "session_id": "$SESSION_ID",
  "instance_id": "$INSTANCE_ID",
  "iam_user": "$IAM_USERNAME",
  "start_time": "$(date -Iseconds)",
  "timestamp": "$TIMESTAMP"
}
EOF

# Log session start
{
    echo "=== SSM Session Started ==="
    echo "Session ID: $SESSION_ID"
    echo "IAM User: $IAM_USERNAME"
    echo "Instance: $INSTANCE_ID"
    echo "Time: $(date)"
} | sudo tee -a /var/log/ssm-session-activity.log >/dev/null 2>&1

# Cleanup function - uploads logs on exit
cleanup() {
    local EXIT_CODE=$?

    # Update metadata with end time
    cat >> "$METADATA_LOG" <<EOF
  "end_time": "$(date -Iseconds)",
  "exit_code": $EXIT_CODE
}
EOF

    echo "=== Session Ended (exit: $EXIT_CODE) ===" | sudo tee -a /var/log/ssm-session-activity.log >/dev/null 2>&1

    # Upload to S3
    [ -f "$TEXT_LOG" ] && aws s3 cp "$TEXT_LOG" "s3://${S3_BUCKET}/sessions/${INSTANCE_ID}/${IAM_USERNAME}/${SESSION_ID}-${TIMESTAMP}.log" --region "$AWS_REGION" 2>&1 | sudo tee -a /var/log/ssm-session-activity.log >/dev/null || true
    [ -f "$RECORDING_FILE" ] && aws s3 cp "$RECORDING_FILE" "s3://${S3_BUCKET}/recordings/${INSTANCE_ID}/${IAM_USERNAME}/${SESSION_ID}-${TIMESTAMP}.cast" --region "$AWS_REGION" 2>&1 | sudo tee -a /var/log/ssm-session-activity.log >/dev/null || true
    [ -f "$COMMANDS_LOG" ] && aws s3 cp "$COMMANDS_LOG" "s3://${S3_BUCKET}/commands/${INSTANCE_ID}/${IAM_USERNAME}/${SESSION_ID}-${TIMESTAMP}-commands.txt" --region "$AWS_REGION" 2>&1 | sudo tee -a /var/log/ssm-session-activity.log >/dev/null || true
    [ -f "$METADATA_LOG" ] && aws s3 cp "$METADATA_LOG" "s3://${S3_BUCKET}/metadata/${INSTANCE_ID}/${IAM_USERNAME}/${SESSION_ID}-${TIMESTAMP}.json" --region "$AWS_REGION" 2>&1 | sudo tee -a /var/log/ssm-session-activity.log >/dev/null || true

    # Cleanup temp directory
    rm -rf "$TMP_DIR" 2>/dev/null || true
}

trap cleanup EXIT SIGTERM SIGINT

# Configure bash history
export HISTFILE="$COMMANDS_LOG"
export HISTTIMEFORMAT="%Y-%m-%d %H:%M:%S "
export PROMPT_COMMAND='history -a'

# Print banner
cat <<'BANNER'
╔══════════════════════════════════════════════════════════════╗
║          SSM SESSION WITH ENHANCED LOGGING ENABLED           ║
╚══════════════════════════════════════════════════════════════╝

⚠️  IMPORTANT NOTICE:
   • This session is being recorded
   • All commands and output are logged
   • Logs are stored in S3 and CloudWatch
   • Your IAM identity is tracked

BANNER

echo "Session ID: $SESSION_ID"
echo "IAM User: $IAM_USERNAME"
echo "Started at: $(date)"
echo ""

# Start recording - simplified to avoid permission issues
if command -v asciinema >/dev/null 2>&1; then
    asciinema rec --command "script -q -f $TEXT_LOG" "$RECORDING_FILE" 2>/dev/null || script -q -f "$TEXT_LOG"
else
    script -q -f "$TEXT_LOG"
fi
WRAPPER_EOF

# Replace placeholders
echo "🔄 Configuring S3 bucket and region..."
sed -i.bak "s|S3_BUCKET_PLACEHOLDER|${BUCKET_NAME}|g" /tmp/ssm-session-wrapper-fixed.sh
sed -i.bak "s|CLOUDWATCH_LOG_GROUP_PLACEHOLDER|/aws/ssm/sessions|g" /tmp/ssm-session-wrapper-fixed.sh
sed -i.bak "s|AWS_REGION_PLACEHOLDER|ap-southeast-1|g" /tmp/ssm-session-wrapper-fixed.sh
rm -f /tmp/ssm-session-wrapper-fixed.sh.bak

# Upload to S3
echo ""
echo "📤 Uploading to S3..."
aws s3 cp /tmp/ssm-session-wrapper-fixed.sh \
  s3://${BUCKET_NAME}/scripts/ssm-session-wrapper.sh \
  --region ap-southeast-1

echo "✅ Uploaded to S3"

# Deploy to instance
echo ""
echo "🚀 Deploying to instance ${INSTANCE_ID}..."
aws ssm send-command \
  --instance-ids ${INSTANCE_ID} \
  --document-name "AWS-RunShellScript" \
  --parameters "commands=[
    'aws s3 cp s3://${BUCKET_NAME}/scripts/ssm-session-wrapper.sh /tmp/ssm-session-wrapper.sh --region ap-southeast-1',
    'sudo mv /tmp/ssm-session-wrapper.sh /usr/local/bin/ssm-session-wrapper.sh',
    'sudo chmod +x /usr/local/bin/ssm-session-wrapper.sh',
    'sudo chown root:root /usr/local/bin/ssm-session-wrapper.sh',
    'echo WRAPPER_UPDATED_SUCCESSFULLY'
  ]" \
  --region ap-southeast-1 \
  --output json > /tmp/deploy-command.json

COMMAND_ID=$(cat /tmp/deploy-command.json | jq -r '.Command.CommandId')
echo "Command ID: $COMMAND_ID"

echo ""
echo "⏳ Waiting for deployment (10 seconds)..."
sleep 10

# Check result
echo ""
echo "🔍 Checking deployment result..."
RESULT=$(aws ssm list-command-invocations \
  --instance-id ${INSTANCE_ID} \
  --max-items 1 \
  --region ap-southeast-1 \
  --query 'CommandInvocations[0].CommandPlugins[0].Output' \
  --output text)

if echo "$RESULT" | grep -q "WRAPPER_UPDATED_SUCCESSFULLY"; then
    echo "✅ Wrapper successfully updated!"
    echo ""
    echo "=========================================="
    echo "✅ FIX COMPLETE!"
    echo "=========================================="
    echo ""
    echo "You can now test with:"
    echo "  1. Grant access: ./jit-admin-session-v1.0.4 -u tony-04 -i ${INSTANCE_ID} -d 30 --purge-existing"
    echo "  2. Connect: aws ssm start-session --target ${INSTANCE_ID} --region ap-southeast-1 --profile tony-04"
    echo ""
    echo "You should see the logging banner!"
else
    echo "❌ Deployment may have failed. Output:"
    echo "$RESULT"
    echo ""
    echo "Try checking the command manually:"
    echo "  aws ssm get-command-invocation --command-id ${COMMAND_ID} --instance-id ${INSTANCE_ID} --region ap-southeast-1"
fi

# Cleanup
rm -f /tmp/ssm-session-wrapper-fixed.sh /tmp/deploy-command.json

echo ""
