#!/usr/bin/env bash
set -euo pipefail
#
# SSM Session Manager Logging Self-Check Script
# This script validates the entire logging setup by:
# 1. Creating a test user with 5-minute access
# 2. Starting a session and running test commands
# 3. Verifying logs in CloudWatch, S3, and instance
#

REGION="${1:-ap-southeast-1}"
INSTANCE_ID="${2:-}"
TEST_USER="ssm-test-$(date +%s)"
DURATION_MIN=5

echo "🧪 SSM Session Manager Logging Self-Check"
echo "=============================================="
echo "Region: $REGION"
echo "Test User: $TEST_USER"
echo "Duration: ${DURATION_MIN} minutes"
echo "=============================================="
echo ""

if [ -z "$INSTANCE_ID" ]; then
    echo "📋 Available SSM-managed instances:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    INSTANCES=$(aws ssm describe-instance-information \
        --region "$REGION" \
        --query 'InstanceInformationList[?PingStatus==`Online`].[InstanceId,PlatformName,IPAddress,PingStatus]' \
        --output text 2>/dev/null || echo "")

    if [ -z "$INSTANCES" ]; then
        echo "❌ No online SSM-managed instances found in region $REGION"
        echo ""
        echo "💡 Make sure:"
        echo "   1. SSM agent is installed and running on your EC2 instances"
        echo "   2. Instance has proper IAM role with SSM permissions"
        echo "   3. Instance has network connectivity to SSM endpoints"
        exit 1
    fi

    echo "$INSTANCES" | while read -r ID PLATFORM IP STATUS; do
        echo "  📦 $ID | $PLATFORM | IP: $IP | Status: $STATUS"
    done

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    read -p "Enter instance ID to test: " INSTANCE_ID
fi

if [ -z "$INSTANCE_ID" ]; then
    echo "❌ Instance ID is required"
    exit 1
fi

echo "🎯 Testing with instance: $INSTANCE_ID"
echo ""

# Check if instance exists and is online
echo "🔍 Checking instance status..."
INSTANCE_STATUS=$(aws ssm describe-instance-information \
    --region "$REGION" \
    --filters "Key=InstanceIds,Values=$INSTANCE_ID" \
    --query 'InstanceInformationList[0].[PingStatus,PlatformType,PlatformName]' \
    --output text 2>/dev/null || echo "NOT_FOUND")

if [ "$INSTANCE_STATUS" == "NOT_FOUND" ]; then
    echo "❌ Instance $INSTANCE_ID not found or not managed by SSM"
    exit 1
fi

PING_STATUS=$(echo "$INSTANCE_STATUS" | awk '{print $1}')
PLATFORM_TYPE=$(echo "$INSTANCE_STATUS" | awk '{print $2}')
PLATFORM_NAME=$(echo "$INSTANCE_STATUS" | cut -f3-)

if [ "$PING_STATUS" != "Online" ]; then
    echo "❌ Instance is not online. Status: $PING_STATUS"
    exit 1
fi

echo "✅ Instance is online"
echo "   Platform: $PLATFORM_NAME ($PLATFORM_TYPE)"
echo ""

# Check if SSM-SessionManagerRunShell document exists
echo "🔍 Checking SSM document..."
if aws ssm describe-document --name "SSM-SessionManagerRunShell" --region "$REGION" >/dev/null 2>&1; then
    echo "✅ SSM-SessionManagerRunShell document exists"
else
    echo "⚠️  SSM-SessionManagerRunShell document not found"
    echo "   This is OK - we'll use the default document for testing"
fi
echo ""

# Get account ID
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo "📋 Account ID: $ACCOUNT_ID"
echo ""

# Check for S3 bucket
S3_BUCKET="ssm-session-logs-${ACCOUNT_ID}-${REGION}"
echo "🔍 Checking S3 bucket: $S3_BUCKET"
if aws s3 ls "s3://$S3_BUCKET" 2>/dev/null; then
    echo "✅ S3 bucket exists"
else
    echo "⚠️  S3 bucket not found - logs won't be stored in S3"
fi
echo ""

# Check for CloudWatch Log Group
CLOUDWATCH_LOG_GROUP="/aws/ssm/sessions"
echo "🔍 Checking CloudWatch Log Group: $CLOUDWATCH_LOG_GROUP"
if aws logs describe-log-groups --log-group-name-prefix "$CLOUDWATCH_LOG_GROUP" \
    --region "$REGION" --query 'logGroups[0]' --output text 2>/dev/null | grep -q "$CLOUDWATCH_LOG_GROUP"; then
    echo "✅ CloudWatch Log Group exists"
else
    echo "⚠️  CloudWatch Log Group not found - logs won't be streamed to CloudWatch"
fi
echo ""

# Check if wrapper script is deployed on instance
echo "🔍 Checking if session wrapper is deployed on instance..."
WRAPPER_CHECK=$(aws ssm send-command \
    --instance-ids "$INSTANCE_ID" \
    --document-name "AWS-RunShellScript" \
    --parameters 'commands=["test -x /usr/local/bin/ssm-session-wrapper.sh && echo FOUND || echo NOT_FOUND"]' \
    --region "$REGION" \
    --output json 2>/dev/null || echo '{}')

COMMAND_ID=$(echo "$WRAPPER_CHECK" | jq -r '.Command.CommandId // empty')

if [ -n "$COMMAND_ID" ]; then
    sleep 3
    WRAPPER_RESULT=$(aws ssm get-command-invocation \
        --command-id "$COMMAND_ID" \
        --instance-id "$INSTANCE_ID" \
        --region "$REGION" \
        --query 'StandardOutputContent' \
        --output text 2>/dev/null || echo "")

    if echo "$WRAPPER_RESULT" | grep -q "FOUND"; then
        echo "✅ Session wrapper script is deployed"
    else
        echo "⚠️  Session wrapper script not found on instance"
        echo "   Commands will still be logged by SSM, but not locally on the instance"
    fi
else
    echo "⚠️  Could not check wrapper script (SSM Run Command failed)"
fi
echo ""

# Check instance IAM role
echo "🔍 Checking instance IAM role..."
INSTANCE_ROLE=$(aws ec2 describe-instances \
    --instance-ids "$INSTANCE_ID" \
    --region "$REGION" \
    --query 'Reservations[0].Instances[0].IamInstanceProfile.Arn' \
    --output text 2>/dev/null | grep -oP 'instance-profile/\K[^/]+' || echo "")

if [ -n "$INSTANCE_ROLE" ]; then
    echo "✅ Instance has IAM role: $INSTANCE_ROLE"

    # Check if role has logging policy
    ATTACHED_POLICIES=$(aws iam list-attached-role-policies --role-name "$INSTANCE_ROLE" --query 'AttachedPolicies[].PolicyName' --output text 2>/dev/null || echo "")

    if echo "$ATTACHED_POLICIES" | grep -q "SSM-SessionManager-Logging-Policy"; then
        echo "✅ Logging policy is attached to instance role"
    else
        echo "⚠️  SSM-SessionManager-Logging-Policy not found on instance role"
        echo "   Instance may not be able to upload logs to S3/CloudWatch"
    fi
else
    echo "⚠️  Instance has no IAM role or role not found"
fi
echo ""

echo "=============================================="
echo "🚀 Starting Interactive Test Session"
echo "=============================================="
echo ""
echo "This will create a test user and start an interactive session."
echo "You'll be able to run commands and verify logging."
echo ""
read -p "Continue with interactive test? [Y/n] " -n 1 -r
echo ""

if [[ ! $REPLY =~ ^[Yy]$ ]] && [[ -n $REPLY ]]; then
    echo "Test cancelled"
    exit 0
fi

# Find jit-admin-session script
JIT_SCRIPT="/Users/vinson/Documents/0_Other_Services/SSM/jit-admin/jit-admin-session-v1.0.5"

if [ ! -f "$JIT_SCRIPT" ]; then
    echo "❌ jit-admin-session script not found at: $JIT_SCRIPT"
    exit 1
fi

echo ""
echo "🔧 Creating test user and granting access..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Create test user with JIT access
"$JIT_SCRIPT" \
    -u "$TEST_USER" \
    -i "$INSTANCE_ID" \
    -d "$DURATION_MIN" \
    --new-user \
    --create-keys \
    --configure-profile "$TEST_USER" \
    --purge-existing \
    --region "$REGION"

echo ""
echo "✅ Test user created: $TEST_USER"
echo ""
echo "=============================================="
echo "🎯 Starting Test Session"
echo "=============================================="
echo ""
echo "Instructions:"
echo "1. When connected, run these test commands:"
echo "   - whoami"
echo "   - pwd"
echo "   - ls -la"
echo "   - echo 'Test command from $TEST_USER'"
echo "   - date"
echo "2. Type 'exit' when done"
echo ""
echo "We'll verify logs after the session ends."
echo ""
read -p "Press Enter to start the session..."

# Start the test session
SESSION_START_TIME=$(date +%s)
echo ""
echo "🔗 Connecting to $INSTANCE_ID..."
echo ""

# Try with document name first, fallback to without
if aws ssm start-session \
    --target "$INSTANCE_ID" \
    --document-name "SSM-SessionManagerRunShell" \
    --region "$REGION" \
    --profile "$TEST_USER" 2>/dev/null; then
    echo "Session ended with document"
elif aws ssm start-session \
    --target "$INSTANCE_ID" \
    --region "$REGION" \
    --profile "$TEST_USER" 2>/dev/null; then
    echo "Session ended without document"
else
    echo "❌ Failed to start session"
    echo ""
    echo "Cleaning up test user..."
    "$JIT_SCRIPT" --purge-session "$TEST_USER" --region "$REGION"
    exit 1
fi

SESSION_END_TIME=$(date +%s)
echo ""
echo "✅ Session ended"
echo ""

echo "=============================================="
echo "🔍 Verifying Logs"
echo "=============================================="
echo ""

# Wait a few seconds for logs to propagate
echo "⏳ Waiting 10 seconds for logs to propagate..."
sleep 10

# Check CloudWatch Logs
echo ""
echo "📊 Checking CloudWatch Logs..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

CW_LOGS=$(aws logs filter-log-events \
    --log-group-name "$CLOUDWATCH_LOG_GROUP" \
    --start-time "$((SESSION_START_TIME * 1000))" \
    --end-time "$((SESSION_END_TIME * 1000))" \
    --region "$REGION" \
    --query 'events[*].message' \
    --output text 2>/dev/null || echo "")

if [ -n "$CW_LOGS" ]; then
    echo "✅ Found logs in CloudWatch!"
    echo ""
    echo "Recent log entries:"
    echo "$CW_LOGS" | head -20
else
    echo "⚠️  No logs found in CloudWatch (may take a few minutes to appear)"
fi

# Check S3 Logs
echo ""
echo "📦 Checking S3 Logs..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if aws s3 ls "s3://$S3_BUCKET" 2>/dev/null; then
    S3_FILES=$(aws s3 ls "s3://$S3_BUCKET/session-logs/" --recursive --region "$REGION" 2>/dev/null | tail -5 || echo "")

    if [ -n "$S3_FILES" ]; then
        echo "✅ Found logs in S3!"
        echo ""
        echo "Recent session log files:"
        echo "$S3_FILES"
    else
        echo "⚠️  No logs found in S3 yet (may take a few minutes to upload)"
    fi
else
    echo "⚠️  S3 bucket not accessible or doesn't exist"
fi

# Check instance local logs
echo ""
echo "💾 Checking Instance Local Logs..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

LOCAL_LOG_CHECK=$(aws ssm send-command \
    --instance-ids "$INSTANCE_ID" \
    --document-name "AWS-RunShellScript" \
    --parameters 'commands=["sudo ls -lht /var/log/ssm-sessions/ 2>/dev/null | head -5 || echo NO_LOGS_FOUND"]' \
    --region "$REGION" \
    --output json 2>/dev/null || echo '{}')

LOCAL_COMMAND_ID=$(echo "$LOCAL_LOG_CHECK" | jq -r '.Command.CommandId // empty')

if [ -n "$LOCAL_COMMAND_ID" ]; then
    sleep 3
    LOCAL_LOGS=$(aws ssm get-command-invocation \
        --command-id "$LOCAL_COMMAND_ID" \
        --instance-id "$INSTANCE_ID" \
        --region "$REGION" \
        --query 'StandardOutputContent' \
        --output text 2>/dev/null || echo "")

    if echo "$LOCAL_LOGS" | grep -q "NO_LOGS_FOUND"; then
        echo "⚠️  No local logs found on instance"
        echo "   (Wrapper script may not be deployed or configured)"
    else
        echo "✅ Found local logs on instance!"
        echo ""
        echo "Recent log files:"
        echo "$LOCAL_LOGS"

        # Try to get the latest log content
        echo ""
        echo "Fetching latest log content..."
        LATEST_LOG=$(aws ssm send-command \
            --instance-ids "$INSTANCE_ID" \
            --document-name "AWS-RunShellScript" \
            --parameters 'commands=["sudo tail -50 $(sudo ls -t /var/log/ssm-sessions/*.log 2>/dev/null | head -1) 2>/dev/null || echo NO_CONTENT"]' \
            --region "$REGION" \
            --output json 2>/dev/null || echo '{}')

        LATEST_COMMAND_ID=$(echo "$LATEST_LOG" | jq -r '.Command.CommandId // empty')
        if [ -n "$LATEST_COMMAND_ID" ]; then
            sleep 3
            LOG_CONTENT=$(aws ssm get-command-invocation \
                --command-id "$LATEST_COMMAND_ID" \
                --instance-id "$INSTANCE_ID" \
                --region "$REGION" \
                --query 'StandardOutputContent' \
                --output text 2>/dev/null || echo "")

            if [ -n "$LOG_CONTENT" ] && ! echo "$LOG_CONTENT" | grep -q "NO_CONTENT"; then
                echo ""
                echo "Latest log content:"
                echo "----------------------------------------"
                echo "$LOG_CONTENT"
                echo "----------------------------------------"
            fi
        fi
    fi
else
    echo "⚠️  Could not check instance logs (SSM Run Command failed)"
fi

echo ""
echo "=============================================="
echo "🧹 Cleanup"
echo "=============================================="
echo ""

read -p "Delete test user $TEST_USER? [Y/n] " -n 1 -r
echo ""

if [[ $REPLY =~ ^[Yy]$ ]] || [[ -z $REPLY ]]; then
    echo "Cleaning up test user..."
    "$JIT_SCRIPT" --purge-session "$TEST_USER" --region "$REGION"
    echo "✅ Test user cleaned up"
else
    echo "⚠️  Test user $TEST_USER was not deleted"
    echo "   Delete manually later with:"
    echo "   $JIT_SCRIPT --purge-session $TEST_USER --region $REGION"
fi

echo ""
echo "=============================================="
echo "📋 Self-Check Summary"
echo "=============================================="
echo ""
echo "Test completed at: $(date)"
echo "Instance tested: $INSTANCE_ID"
echo "Test user: $TEST_USER"
echo ""
echo "Check the logs above to verify:"
echo "  ✓ CloudWatch Logs contain session activity"
echo "  ✓ S3 bucket contains session recordings"
echo "  ✓ Instance has local command logs (if wrapper deployed)"
echo ""
echo "For detailed logs, check:"
echo "  - CloudWatch: aws logs tail $CLOUDWATCH_LOG_GROUP --follow"
echo "  - S3: aws s3 ls s3://$S3_BUCKET/session-logs/ --recursive"
echo "  - Instance: /var/log/ssm-sessions/"
echo ""
echo "=============================================="
