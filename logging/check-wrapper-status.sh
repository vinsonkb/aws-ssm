#!/usr/bin/env bash
set -euo pipefail

# check-wrapper-status.sh
# Verifies wrapper script installation status across multiple EC2 instances
#
# Usage:
#   ./check-wrapper-status.sh <region> <instances-file>
#
# Example:
#   ./check-wrapper-status.sh ap-southeast-1 instances.txt

REGION="${1:-}"
INSTANCES_FILE="${2:-instances.txt}"

if [[ -z "$REGION" ]]; then
    echo "Usage: $0 <region> [instances-file]"
    echo "Example: $0 ap-southeast-1 instances.txt"
    exit 1
fi

if [[ ! -f "$INSTANCES_FILE" ]]; then
    echo "Error: Instances file not found: $INSTANCES_FILE"
    exit 1
fi

echo "========================================"
echo "SSM Wrapper Installation Status Check"
echo "========================================"
echo "Region: $REGION"
echo "Instances file: $INSTANCES_FILE"
echo ""

# Counters
TOTAL=0
ONLINE=0
OFFLINE=0
WRAPPER_INSTALLED=0
WRAPPER_MISSING=0
WRAPPER_UNKNOWN=0

# Arrays to store results
declare -a INSTANCES_ONLINE
declare -a INSTANCES_OFFLINE
declare -a INSTANCES_WITH_WRAPPER
declare -a INSTANCES_WITHOUT_WRAPPER
declare -a INSTANCES_CHECK_FAILED

echo "Checking instances..."
echo ""

while IFS=$'\t' read -r INSTANCE_ID INSTANCE_NAME; do
    # Skip empty lines
    [[ -z "$INSTANCE_ID" ]] && continue

    ((TOTAL++))
    TOTAL_COUNT=$(wc -l < "$INSTANCES_FILE" | tr -d ' ')
    printf "[%2d/%2d] Checking %-25s (%s)... " "$TOTAL" "$TOTAL_COUNT" "$INSTANCE_NAME" "$INSTANCE_ID"

    # Check if instance is online in SSM
    PING_STATUS=$(aws ssm describe-instance-information \
        --filters "Key=InstanceIds,Values=$INSTANCE_ID" \
        --query 'InstanceInformationList[0].PingStatus' \
        --output text \
        --region "$REGION" 2>/dev/null || echo "None")

    if [[ "$PING_STATUS" != "Online" ]]; then
        echo "OFFLINE"
        ((OFFLINE++))
        INSTANCES_OFFLINE+=("$INSTANCE_ID\t$INSTANCE_NAME")
        continue
    fi

    ((ONLINE++))
    INSTANCES_ONLINE+=("$INSTANCE_ID\t$INSTANCE_NAME")

    # Check if wrapper script exists
    COMMAND_ID=$(aws ssm send-command \
        --instance-ids "$INSTANCE_ID" \
        --document-name "AWS-RunShellScript" \
        --parameters 'commands=["test -f /usr/local/bin/ssm-session-wrapper.sh && echo INSTALLED || echo MISSING"]' \
        --region "$REGION" \
        --query 'Command.CommandId' \
        --output text 2>/dev/null || echo "FAILED")

    if [[ "$COMMAND_ID" == "FAILED" ]]; then
        echo "CHECK FAILED"
        ((WRAPPER_UNKNOWN++))
        INSTANCES_CHECK_FAILED+=("$INSTANCE_ID\t$INSTANCE_NAME")
        continue
    fi

    # Wait for command to complete
    sleep 2

    # Get command result
    RESULT=$(aws ssm get-command-invocation \
        --command-id "$COMMAND_ID" \
        --instance-id "$INSTANCE_ID" \
        --region "$REGION" \
        --query 'StandardOutputContent' \
        --output text 2>/dev/null || echo "UNKNOWN")

    if echo "$RESULT" | grep -q "INSTALLED"; then
        echo "✅ INSTALLED"
        ((WRAPPER_INSTALLED++))
        INSTANCES_WITH_WRAPPER+=("$INSTANCE_ID\t$INSTANCE_NAME")
    elif echo "$RESULT" | grep -q "MISSING"; then
        echo "❌ MISSING"
        ((WRAPPER_MISSING++))
        INSTANCES_WITHOUT_WRAPPER+=("$INSTANCE_ID\t$INSTANCE_NAME")
    else
        echo "⚠️ UNKNOWN"
        ((WRAPPER_UNKNOWN++))
        INSTANCES_CHECK_FAILED+=("$INSTANCE_ID\t$INSTANCE_NAME")
    fi

done < "$INSTANCES_FILE"

echo ""
echo "========================================"
echo "Summary"
echo "========================================"
echo "Total instances checked: $TOTAL"
echo ""
echo "SSM Status:"
echo "  - Online: $ONLINE"
echo "  - Offline/Not in SSM: $OFFLINE"
echo ""
echo "Wrapper Script Status (for online instances):"
echo "  - ✅ Installed: $WRAPPER_INSTALLED"
echo "  - ❌ Missing: $WRAPPER_MISSING"
echo "  - ⚠️  Unknown/Check failed: $WRAPPER_UNKNOWN"
echo ""

# Show detailed results
if [[ $OFFLINE -gt 0 ]]; then
    echo "========================================"
    echo "Offline/Not in SSM Instances ($OFFLINE)"
    echo "========================================"
    printf '%b\n' "${INSTANCES_OFFLINE[@]}" | column -t -s $'\t'
    echo ""
fi

if [[ $WRAPPER_MISSING -gt 0 ]]; then
    echo "========================================"
    echo "Instances Missing Wrapper ($WRAPPER_MISSING)"
    echo "========================================"
    printf '%b\n' "${INSTANCES_WITHOUT_WRAPPER[@]}" | column -t -s $'\t'
    echo ""
    echo "To deploy wrapper to these instances, run:"
    echo "  ./deploy-wrapper-to-instances.sh $REGION <instance-ids>"
    echo ""
fi

if [[ $WRAPPER_UNKNOWN -gt 0 ]]; then
    echo "========================================"
    echo "Instances with Unknown Status ($WRAPPER_UNKNOWN)"
    echo "========================================"
    printf '%b\n' "${INSTANCES_CHECK_FAILED[@]}" | column -t -s $'\t'
    echo ""
fi

if [[ $WRAPPER_INSTALLED -gt 0 ]]; then
    echo "========================================"
    echo "Instances with Wrapper Installed ($WRAPPER_INSTALLED)"
    echo "========================================"
    printf '%b\n' "${INSTANCES_WITH_WRAPPER[@]}" | column -t -s $'\t'
    echo ""
fi

echo "========================================"
echo "Check complete!"
echo "========================================"
