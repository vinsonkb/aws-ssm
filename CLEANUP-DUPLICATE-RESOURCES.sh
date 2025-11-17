#!/usr/bin/env bash
set -euo pipefail
#
# Cleanup Script for Duplicate SSM Logging Resources
#
# This script removes the duplicate S3 bucket and CloudWatch log group
# that were created by running setup-ssm-logging.sh with old defaults.
#
# PRODUCTION RESOURCES (DO NOT DELETE):
# - S3 Bucket: ssm-onetime-logs-vortech-dev
# - CloudWatch Log Group: /aws/ssm/onetime-sessions-dev
#
# DUPLICATE RESOURCES (TO BE DELETED):
# - S3 Bucket: ssm-session-logs-937206802878
# - CloudWatch Log Group: /aws/ssm/sessions
#

REGION="${1:-ap-southeast-1}"
DRY_RUN="${2:-true}"  # Set to "false" to actually delete

DUPLICATE_BUCKET="ssm-session-logs-937206802878"
DUPLICATE_LOG_GROUP="/aws/ssm/sessions"

PRODUCTION_BUCKET="ssm-onetime-logs-vortech-dev"
PRODUCTION_LOG_GROUP="/aws/ssm/onetime-sessions-dev"

echo "========================================"
echo "SSM Logging Resources Cleanup"
echo "========================================"
echo ""
echo "🔍 Checking for duplicate resources..."
echo ""

# Function to check if bucket has any objects
check_bucket_empty() {
    local bucket=$1
    local count=$(aws s3 ls "s3://$bucket" --recursive --region "$REGION" 2>/dev/null | wc -l)
    echo "$count"
}

# Function to check if log group has any streams
check_log_group_streams() {
    local log_group=$1
    local count=$(aws logs describe-log-streams \
        --log-group-name "$log_group" \
        --region "$REGION" 2>/dev/null \
        | jq -r '.logStreams | length' 2>/dev/null || echo "0")
    echo "$count"
}

# Check duplicate S3 bucket
echo "📦 Checking S3 bucket: $DUPLICATE_BUCKET"
if aws s3 ls "s3://$DUPLICATE_BUCKET" --region "$REGION" >/dev/null 2>&1; then
    OBJECT_COUNT=$(check_bucket_empty "$DUPLICATE_BUCKET")
    echo "   ✅ Bucket exists"
    echo "   📊 Object count: $OBJECT_COUNT"

    if [ "$OBJECT_COUNT" -gt 0 ]; then
        echo "   ⚠️  WARNING: Bucket contains $OBJECT_COUNT objects"
        echo "   📋 Listing recent objects:"
        aws s3 ls "s3://$DUPLICATE_BUCKET/sessions/" \
            --recursive \
            --human-readable \
            --region "$REGION" 2>/dev/null | head -10 || echo "      (No sessions/ prefix found)"
    else
        echo "   ✅ Bucket is empty - safe to delete"
    fi
    DELETE_BUCKET=true
else
    echo "   ℹ️  Bucket not found (already deleted or never existed)"
    DELETE_BUCKET=false
fi
echo ""

# Check duplicate CloudWatch log group
echo "📊 Checking CloudWatch log group: $DUPLICATE_LOG_GROUP"
if aws logs describe-log-groups \
    --log-group-name-prefix "$DUPLICATE_LOG_GROUP" \
    --region "$REGION" 2>/dev/null \
    | grep -q "$DUPLICATE_LOG_GROUP"; then

    STREAM_COUNT=$(check_log_group_streams "$DUPLICATE_LOG_GROUP")
    echo "   ✅ Log group exists"
    echo "   📊 Log stream count: $STREAM_COUNT"

    if [ "$STREAM_COUNT" -gt 0 ]; then
        echo "   ⚠️  WARNING: Log group contains $STREAM_COUNT log streams"
        echo "   📋 Listing recent streams:"
        aws logs describe-log-streams \
            --log-group-name "$DUPLICATE_LOG_GROUP" \
            --order-by LastEventTime \
            --descending \
            --max-items 5 \
            --region "$REGION" 2>/dev/null \
            | jq -r '.logStreams[] | "\(.logStreamName) - Last event: \(.lastEventTimestamp // 0 | tonumber / 1000 | strftime("%Y-%m-%d %H:%M:%S"))"' || true
    else
        echo "   ✅ Log group is empty - safe to delete"
    fi
    DELETE_LOG_GROUP=true
else
    echo "   ℹ️  Log group not found (already deleted or never existed)"
    DELETE_LOG_GROUP=false
fi
echo ""

# Verify production resources are NOT touched
echo "🔒 Verifying production resources (will NOT be deleted):"
echo ""
echo "📦 Production S3 bucket: $PRODUCTION_BUCKET"
if aws s3 ls "s3://$PRODUCTION_BUCKET" --region "$REGION" >/dev/null 2>&1; then
    PROD_COUNT=$(check_bucket_empty "$PRODUCTION_BUCKET")
    echo "   ✅ Exists with $PROD_COUNT objects"
else
    echo "   ❌ NOT FOUND - This should exist!"
fi

echo ""
echo "📊 Production CloudWatch log group: $PRODUCTION_LOG_GROUP"
if aws logs describe-log-groups \
    --log-group-name-prefix "$PRODUCTION_LOG_GROUP" \
    --region "$REGION" 2>/dev/null \
    | grep -q "$PRODUCTION_LOG_GROUP"; then
    echo "   ✅ Exists"
else
    echo "   ❌ NOT FOUND - This should exist!"
fi
echo ""

# Summary
echo "========================================"
echo "Summary"
echo "========================================"
if [ "$DELETE_BUCKET" = true ]; then
    echo "✅ Will delete S3 bucket: $DUPLICATE_BUCKET"
else
    echo "⏭️  Skip S3 bucket (not found)"
fi

if [ "$DELETE_LOG_GROUP" = true ]; then
    echo "✅ Will delete CloudWatch log group: $DUPLICATE_LOG_GROUP"
else
    echo "⏭️  Skip log group (not found)"
fi
echo ""

# Dry run or actual deletion
if [ "$DRY_RUN" = "true" ]; then
    echo "========================================"
    echo "🔍 DRY RUN MODE - No changes will be made"
    echo "========================================"
    echo ""
    echo "To actually delete these resources, run:"
    echo "   $0 $REGION false"
    echo ""
    echo "⚠️  IMPORTANT: Review the object/stream counts above before proceeding!"
    echo ""
else
    echo "========================================"
    echo "⚠️  DELETION MODE - Resources will be deleted!"
    echo "========================================"
    echo ""
    read -p "Are you sure you want to delete these resources? (type 'yes' to confirm): " CONFIRM

    if [ "$CONFIRM" != "yes" ]; then
        echo "❌ Cancelled by user"
        exit 1
    fi

    # Delete S3 bucket
    if [ "$DELETE_BUCKET" = true ]; then
        echo ""
        echo "🗑️  Deleting S3 bucket: $DUPLICATE_BUCKET"

        # Empty bucket first
        if [ "$OBJECT_COUNT" -gt 0 ]; then
            echo "   📦 Emptying bucket..."
            aws s3 rm "s3://$DUPLICATE_BUCKET" --recursive --region "$REGION"
        fi

        # Delete bucket
        echo "   🗑️  Removing bucket..."
        aws s3 rb "s3://$DUPLICATE_BUCKET" --region "$REGION"
        echo "   ✅ Bucket deleted"
    fi

    # Delete CloudWatch log group
    if [ "$DELETE_LOG_GROUP" = true ]; then
        echo ""
        echo "🗑️  Deleting CloudWatch log group: $DUPLICATE_LOG_GROUP"
        aws logs delete-log-group \
            --log-group-name "$DUPLICATE_LOG_GROUP" \
            --region "$REGION"
        echo "   ✅ Log group deleted"
    fi

    echo ""
    echo "========================================"
    echo "✅ Cleanup Complete!"
    echo "========================================"
    echo ""
    echo "Remaining production resources:"
    echo "   - S3: s3://$PRODUCTION_BUCKET"
    echo "   - CloudWatch: $PRODUCTION_LOG_GROUP"
    echo ""
fi
