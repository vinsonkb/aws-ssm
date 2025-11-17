# Complete Guide: jit-admin-session-v1.0.5

**Just-In-Time (JIT) Admin Access for AWS SSM Session Manager**

This guide covers all use cases with real-world examples for granting temporary, secure access to EC2 instances via AWS Systems Manager.

---

## 📋 Table of Contents

1. [Overview](#overview)
2. [Quick Reference](#quick-reference)
3. [Use Case 1: New Developer Onboarding](#use-case-1-new-developer-onboarding)
4. [Use Case 2: Emergency Access](#use-case-2-emergency-access)
5. [Use Case 3: Contractor Short-Term Access](#use-case-3-contractor-short-term-access)
6. [Use Case 4: Renewing Existing User Access](#use-case-4-renewing-existing-user-access)
7. [Use Case 5: Multi-Instance Access](#use-case-5-multi-instance-access)
8. [Use Case 6: Tagged Instance Access](#use-case-6-tagged-instance-access)
9. [Use Case 7: Revoking Access Immediately](#use-case-7-revoking-access-immediately)
10. [Use Case 8: Audit and Monitoring](#use-case-8-audit-and-monitoring)
11. [Use Case 9: Self-Service User Setup](#use-case-9-self-service-user-setup)
12. [Use Case 10: Bulk Access Management](#use-case-10-bulk-access-management)
13. [Advanced Scenarios](#advanced-scenarios)
14. [Troubleshooting](#troubleshooting)
15. [Best Practices](#best-practices)

---

## Overview

### What is jit-admin-session?

`jit-admin-session-v1.0.5` is a secure, automated tool for granting time-limited SSH-like access to EC2 instances via AWS Systems Manager (SSM).

### Key Features

✅ **Time-Limited Access** - Auto-expiring credentials (1-240 minutes)
✅ **Document Enforcement** - Forces users to use `SSM-SessionManagerRunShell` for logging
✅ **Auto-Termination** - Kills active sessions when access expires
✅ **Complete Logging** - All commands logged to S3, CloudWatch, and instance
✅ **Zero SSH Keys** - No SSH keys needed, all through IAM
✅ **Tag-Based Access** - Restrict to instances with specific tags
✅ **Easy Cleanup** - One command to revoke all access and terminate sessions

### System Requirements

| Requirement | Details |
|-------------|---------|
| **AWS CLI** | v2.x or higher |
| **jq** | JSON processor |
| **openssl** | For random token generation |
| **Permissions** | IAM admin rights in target account |
| **Region** | Default: ap-southeast-1 (configurable) |

---

## Quick Reference

### Common Commands

```bash
# Create new user with 30-min access
./jit-admin-session-v1.0.5 -u USERNAME -i INSTANCE_ID -d 30 --new-user --create-keys --output-script setup.sh

# Renew existing user
./jit-admin-session-v1.0.5 -u USERNAME -i INSTANCE_ID -d 60 --purge-existing

# Revoke access immediately
./jit-admin-session-v1.0.5 --purge-session USERNAME

# With tag requirement
./jit-admin-session-v1.0.5 -u USERNAME -i INSTANCE_ID -d 30 --new-user --create-keys --require-tag Environment=Production
```

### All Options

```
Required:
  -u USER           IAM username
  -i INSTANCE       EC2 instance ID
  -d MINUTES        Duration (1-240)

Optional:
  --new-user                    Create IAM user if missing
  --create-keys                 Generate access keys
  --configure-profile NAME      Configure local AWS profile
  --output-script PATH          Generate all-in-one setup script
  --purge-existing              Delete old policies first
  --purge-session USER          Cleanup mode
  --require-tag KEY=VALUE       Restrict to tagged instances
  -r, --region REGION           AWS region (default: ap-southeast-1)
  --local-admin-profile NAME    Use specific AWS profile
  -h, --help                    Show help
```

---

## Use Case 1: New Developer Onboarding

**Scenario:** A new developer joins the team and needs access to the development environment.

### Requirements
- Developer name: `john-dev`
- Instance: `i-0ee0bc84a481f7852` (dev server)
- Duration: 8 hours (480 minutes)
- Need: All-in-one setup script for the developer

### Step-by-Step

#### 1. Admin Creates Access

```bash
cd /Users/vinson/Documents/0_Other_Services/SSM/jit-admin

./jit-admin-session-v1.0.5 \
  -u john-dev \
  -i i-0ee0bc84a481f7852 \
  -d 480 \
  --new-user \
  --create-keys \
  --output-script setup-john-dev.sh \
  --region ap-southeast-1
```

#### 2. Output

```
✅ Created IAM user: john-dev
✅ Access keys created.
✅ All-in-one setup script generated: setup-john-dev.sh

📤 Send this ONE file to the user: setup-john-dev.sh

📋 User instructions:
   1. Run: bash setup-john-dev.sh
   2. Script will install tools if needed and connect automatically
   3. To reconnect later: bash setup-john-dev.sh (reusable!)
```

#### 3. Admin Sends File to Developer

```bash
# Email or Slack the script
# Or use secure file transfer
scp setup-john-dev.sh john@example.com:~/

# Or share via S3 presigned URL
aws s3 cp setup-john-dev.sh s3://temp-bucket/
aws s3 presign s3://temp-bucket/setup-john-dev.sh --expires-in 3600
```

#### 4. Developer Uses the Script

```bash
# Developer downloads and runs
bash setup-john-dev.sh
```

**What happens:**
- ✅ Installs AWS CLI, jq, Session Manager plugin (if needed)
- ✅ Configures AWS credentials automatically
- ✅ Connects to the instance immediately
- ✅ Can reconnect anytime within 8 hours by running the script again

#### 5. After 8 Hours

Access automatically expires:
- ✅ IAM policy deleted
- ✅ Active sessions terminated
- ✅ Developer can no longer connect

### When to Use This Pattern

✅ New team members
✅ Regular developers needing daily access
✅ Users who need to reconnect multiple times

---

## Use Case 2: Emergency Access

**Scenario:** Production incident at 2 AM, need to grant immediate access to on-call engineer.

### Requirements
- Engineer: `sarah-oncall`
- Instance: `i-0abc123def456789` (production web server)
- Duration: 2 hours (120 minutes) - just enough to fix the issue
- Need: FAST, no waiting for script distribution

### Quick Command

```bash
cd /Users/vinson/Documents/0_Other_Services/SSM/jit-admin

# Check if user exists
aws iam get-user --user-name sarah-oncall 2>/dev/null && USER_EXISTS=true || USER_EXISTS=false

# If user exists (returning on-call engineer)
./jit-admin-session-v1.0.5 \
  -u sarah-oncall \
  -i i-0abc123def456789 \
  -d 120 \
  --purge-existing \
  --region ap-southeast-1

# If new user
./jit-admin-session-v1.0.5 \
  -u sarah-oncall \
  -i i-0abc123def456789 \
  -d 120 \
  --new-user \
  --create-keys \
  --configure-profile sarah-oncall \
  --region ap-southeast-1
```

### Share Connection Command Immediately

```bash
# Copy this command and send via Slack/Teams
aws ssm start-session \
  --target i-0abc123def456789 \
  --document-name SSM-SessionManagerRunShell \
  --region ap-southeast-1 \
  --profile sarah-oncall
```

### If User Needs Keys NOW

```bash
# Keys are shown in output:
# Send securely via password manager or encrypted channel
"AccessKeyId": "AKIA...",
"SecretAccessKey": "..."
```

### After Emergency

```bash
# Revoke access immediately after incident is resolved
./jit-admin-session-v1.0.5 --purge-session sarah-oncall --region ap-southeast-1
```

### When to Use This Pattern

✅ Production incidents
✅ Emergency debugging
✅ After-hours access
✅ Critical security patches

---

## Use Case 3: Contractor Short-Term Access

**Scenario:** External contractor needs to test integration for 3 days.

### Requirements
- Contractor: `vendor-alice`
- Instance: `i-0test123staging456`
- Duration: Start with 4 hours, renew as needed
- Need: Track and limit access carefully

### Day 1: Initial Access

```bash
./jit-admin-session-v1.0.5 \
  -u vendor-alice \
  -i i-0test123staging456 \
  -d 240 \
  --new-user \
  --create-keys \
  --output-script setup-vendor-alice.sh \
  --require-tag Environment=Staging \
  --region ap-southeast-1
```

**Why `--require-tag`?**
- Ensures contractor can ONLY access staging instances
- Even with credentials, production instances are blocked

### Day 2: Renew Access

```bash
# Contractor requests renewal
./jit-admin-session-v1.0.5 \
  -u vendor-alice \
  -i i-0test123staging456 \
  -d 240 \
  --purge-existing \
  --region ap-southeast-1
```

### Day 3: Different Instance

```bash
# Contractor needs different staging instance
./jit-admin-session-v1.0.5 \
  -u vendor-alice \
  -i i-0staging789newtest \
  -d 240 \
  --purge-existing \
  --require-tag Environment=Staging \
  --region ap-southeast-1
```

### End of Contract: Full Cleanup

```bash
# Remove all access, sessions, and keys
./jit-admin-session-v1.0.5 \
  --purge-session vendor-alice \
  --region ap-southeast-1

# Verify user is gone
aws iam get-user --user-name vendor-alice
# Should return: NoSuchEntity error ✅
```

### Audit Trail

```bash
# Review all contractor activity
aws s3 ls s3://ssm-onetime-logs-vortech-dev/sessions/ | grep vendor-alice

# Download all session logs
aws s3 cp s3://ssm-onetime-logs-vortech-dev/sessions/ \
  ./vendor-alice-audit/ \
  --recursive \
  --exclude "*" \
  --include "vendor-alice-*"

# Review in CloudWatch
aws logs filter-log-events \
  --log-group-name /aws/ssm/onetime-sessions-dev \
  --filter-pattern "vendor-alice" \
  --region ap-southeast-1
```

### When to Use This Pattern

✅ External contractors
✅ Temporary consultants
✅ Third-party integrations
✅ Security audits
✅ Penetration testing access

---

## Use Case 4: Renewing Existing User Access

**Scenario:** Developer's access expired, needs to continue working.

### Scenario A: Same Instance, Extend Time

```bash
# Original access expired after 4 hours
# Developer needs another 4 hours

./jit-admin-session-v1.0.5 \
  -u john-dev \
  -i i-0ee0bc84a481f7852 \
  -d 240 \
  --purge-existing \
  --region ap-southeast-1
```

**What happens:**
- ✅ Deletes old expired policy
- ✅ Creates new policy with fresh 4-hour timer
- ✅ Developer reconnects with existing credentials
- ✅ No need to reconfigure AWS CLI

### Scenario B: Different Instance

```bash
# Developer needs to access a different server

./jit-admin-session-v1.0.5 \
  -u john-dev \
  -i i-0different987654321 \
  -d 240 \
  --purge-existing \
  --region ap-southeast-1
```

### Scenario C: Multiple Renewals in One Day

```bash
# 9 AM - Initial access (4 hours)
./jit-admin-session-v1.0.5 -u john-dev -i i-0ee0bc84a481f7852 -d 240 --new-user --create-keys --configure-profile john-dev

# 1 PM - Renew for afternoon (4 hours)
./jit-admin-session-v1.0.5 -u john-dev -i i-0ee0bc84a481f7852 -d 240 --purge-existing

# 5 PM - Late fix needed (2 hours)
./jit-admin-session-v1.0.5 -u john-dev -i i-0ee0bc84a481f7852 -d 120 --purge-existing

# End of day - revoke all access
./jit-admin-session-v1.0.5 --purge-session john-dev
```

### Checking Current Access

```bash
# Check if user has active policy
aws iam list-user-policies --user-name john-dev

# Check active sessions
aws ssm describe-sessions \
  --state Active \
  --region ap-southeast-1 \
  --filters "key=Owner,value=john-dev"
```

### When to Use This Pattern

✅ Daily developer workflows
✅ Extended debugging sessions
✅ Access expired during active work
✅ Switching between instances

---

## Use Case 5: Multi-Instance Access

**Scenario:** Database admin needs to access multiple database instances for migration.

### Requirements
- Admin: `dba-mike`
- Instances: 3 database servers
- Duration: 8 hours for entire migration
- Need: Access to all instances simultaneously

### Approach 1: Sequential Access (One Instance at a Time)

```bash
# Access first database
./jit-admin-session-v1.0.5 \
  -u dba-mike \
  -i i-0db001primary \
  -d 480 \
  --new-user \
  --create-keys \
  --configure-profile dba-mike \
  --region ap-southeast-1

# When done with first, switch to second
./jit-admin-session-v1.0.5 \
  -u dba-mike \
  -i i-0db002replica \
  -d 480 \
  --purge-existing \
  --region ap-southeast-1

# Switch to third
./jit-admin-session-v1.0.5 \
  -u dba-mike \
  -i i-0db003backup \
  -d 480 \
  --purge-existing \
  --region ap-southeast-1
```

### Approach 2: Simultaneous Access (Tag-Based)

**Prerequisites:** Tag all database instances with `Role=Database`

```bash
# Grant access to ANY instance with Database tag
./jit-admin-session-v1.0.5 \
  -u dba-mike \
  -i i-0db001primary \
  -d 480 \
  --new-user \
  --create-keys \
  --configure-profile dba-mike \
  --require-tag Role=Database \
  --region ap-southeast-1
```

**Connect to any database:**

```bash
# Primary
aws ssm start-session --target i-0db001primary \
  --document-name SSM-SessionManagerRunShell --profile dba-mike

# Replica
aws ssm start-session --target i-0db002replica \
  --document-name SSM-SessionManagerRunShell --profile dba-mike

# Backup
aws ssm start-session --target i-0db003backup \
  --document-name SSM-SessionManagerRunShell --profile dba-mike
```

### Approach 3: Scripted Batch Access

```bash
#!/bin/bash
# grant-multi-instance-access.sh

USER="dba-mike"
DURATION=480
INSTANCES=(
  "i-0db001primary"
  "i-0db002replica"
  "i-0db003backup"
)

# Create user on first instance
./jit-admin-session-v1.0.5 \
  -u "$USER" \
  -i "${INSTANCES[0]}" \
  -d "$DURATION" \
  --new-user \
  --create-keys \
  --configure-profile "$USER" \
  --region ap-southeast-1

echo ""
echo "User can now access these instances:"
for instance in "${INSTANCES[@]}"; do
  echo "  aws ssm start-session --target $instance --document-name SSM-SessionManagerRunShell --profile $USER"
done
```

### When to Use This Pattern

✅ Database migrations
✅ Infrastructure updates across multiple servers
✅ Load balancer pool maintenance
✅ Cluster-wide operations

---

## Use Case 6: Tagged Instance Access

**Scenario:** Only allow access to instances marked as safe for specific users.

### Setup: Tag Your Instances

```bash
# Production instances
aws ec2 create-tags \
  --resources i-0prod001 i-0prod002 i-0prod003 \
  --tags Key=Environment,Value=Production \
  --region ap-southeast-1

# Staging instances
aws ec2 create-tags \
  --resources i-0staging001 i-0staging002 \
  --tags Key=Environment,Value=Staging \
  --region ap-southeast-1

# JIT-allowed instances
aws ec2 create-tags \
  --resources i-0test001 \
  --tags Key=JITAccess,Value=Allowed \
  --region ap-southeast-1
```

### Grant Tag-Restricted Access

#### Example 1: Staging Only

```bash
./jit-admin-session-v1.0.5 \
  -u qa-tester \
  -i i-0staging001 \
  -d 240 \
  --new-user \
  --create-keys \
  --output-script setup-qa-tester.sh \
  --require-tag Environment=Staging \
  --region ap-southeast-1
```

**Result:**
- ✅ Can access: i-0staging001, i-0staging002 (any staging instance)
- ❌ Cannot access: Production instances (blocked by IAM policy)

#### Example 2: JIT-Allowed Only

```bash
./jit-admin-session-v1.0.5 \
  -u developer-test \
  -i i-0test001 \
  -d 60 \
  --new-user \
  --create-keys \
  --configure-profile developer-test \
  --require-tag JITAccess=Allowed \
  --region ap-southeast-1
```

#### Example 3: Multiple Tag Restrictions

```bash
# For instances that are BOTH staging AND JIT-allowed
# Note: Current version supports one tag, for multiple tags you need custom policy

./jit-admin-session-v1.0.5 \
  -u contractor-limited \
  -i i-0test001 \
  -d 120 \
  --new-user \
  --create-keys \
  --require-tag JITAccess=Allowed \
  --region ap-southeast-1
```

### Testing Tag Enforcement

```bash
# This WILL work (correct tag)
aws ssm start-session \
  --target i-0test001 \
  --document-name SSM-SessionManagerRunShell \
  --profile contractor-limited

# This will FAIL (no JITAccess tag)
aws ssm start-session \
  --target i-0prod001 \
  --document-name SSM-SessionManagerRunShell \
  --profile contractor-limited
# Error: AccessDeniedException
```

### When to Use This Pattern

✅ Contractors/vendors (staging only)
✅ Junior developers (dev environments only)
✅ Compliance requirements (separate prod/non-prod access)
✅ Testing environments
✅ Security-sensitive instances

---

## Use Case 7: Revoking Access Immediately

**Scenario:** Need to immediately terminate access and all active sessions.

### Quick Revoke

```bash
./jit-admin-session-v1.0.5 --purge-session USERNAME --region ap-southeast-1
```

### What Gets Cleaned Up

```
🧹 Purge mode for user: USERNAME
==============================================

✅ Terminates all active SSM sessions
✅ Deletes all OneTimeSSM-* IAM policies
✅ Deletes all access keys (with confirmation)
✅ Leaves IAM user account (can be reused)
```

### Detailed Example

```bash
./jit-admin-session-v1.0.5 --purge-session john-dev --region ap-southeast-1
```

**Output:**
```
🧹 Purge mode for user: john-dev
==============================================

🔍 Looking for active SSM sessions...
Found active session(s):
  - john-dev-0ee0bc84a481f7852-abc123def456

⛔ Terminating sessions...
  ✅ Terminated john-dev-0ee0bc84a481f7852-abc123def456

🗑️  Deleting OneTimeSSM-* policies...
  - Deleting OneTimeSSM-onetime-d8f9d6898df32be0
  ✅ Deleted 1 policy(ies)

🔑 Deleting access keys...
Found 1 access key(s):
  - AKIA5UNPA5G7OKD2DVCS (created: 2025-11-15T10:40:09+00:00)

Delete all 1 access key(s)? [y/N] y
  - Deleting AKIA5UNPA5G7OKD2DVCS
  ✅ Deleted all access keys

✅ Purge complete for john-dev!
==============================================
```

### Scenarios Requiring Immediate Revoke

#### 1. Security Incident

```bash
# Employee reports credential leak
./jit-admin-session-v1.0.5 --purge-session compromised-user --region ap-southeast-1

# Verify no active sessions
aws ssm describe-sessions \
  --state Active \
  --region ap-southeast-1 \
  --filters "key=Owner,value=compromised-user"
# Should return empty
```

#### 2. Employee Termination

```bash
# Immediately revoke all access
./jit-admin-session-v1.0.5 --purge-session terminated-employee --region ap-southeast-1

# Also delete the IAM user entirely
aws iam delete-user --user-name terminated-employee
```

#### 3. Contractor End of Contract

```bash
# Cleanup contractor access
./jit-admin-session-v1.0.5 --purge-session vendor-alice --region ap-southeast-1

# Archive their session logs
aws s3 sync s3://ssm-onetime-logs-vortech-dev/sessions/ \
  ./archived-logs/vendor-alice/ \
  --exclude "*" \
  --include "vendor-alice-*"
```

#### 4. Suspicious Activity Detected

```bash
# Immediately terminate
./jit-admin-session-v1.0.5 --purge-session suspicious-user --region ap-southeast-1

# Review their activity
aws s3 ls s3://ssm-onetime-logs-vortech-dev/sessions/ | grep suspicious-user
```

### Bulk Revoke (Multiple Users)

```bash
#!/bin/bash
# bulk-revoke.sh

USERS=(
  "contractor-1"
  "contractor-2"
  "temp-developer"
)

for user in "${USERS[@]}"; do
  echo "Revoking access for: $user"
  ./jit-admin-session-v1.0.5 --purge-session "$user" --region ap-southeast-1
  echo ""
done
```

### When to Use This Pattern

✅ Security incidents
✅ Credential compromise
✅ Employee offboarding
✅ Contract completion
✅ Policy violations
✅ Suspicious activity

---

## Use Case 8: Audit and Monitoring

**Scenario:** Track who has access and monitor their activity.

### Check Active Users

```bash
# List all JIT users (users with OneTimeSSM policies)
aws iam list-users --query 'Users[*].UserName' --output text | while read user; do
  policies=$(aws iam list-user-policies --user-name "$user" --query 'PolicyNames' --output text 2>/dev/null)
  if echo "$policies" | grep -q "OneTimeSSM"; then
    echo "Active JIT User: $user"
    echo "  Policies: $policies"

    # Check expiry from policy
    policy_name=$(echo "$policies" | tr '\t' '\n' | grep OneTimeSSM | head -1)
    echo "  Policy: $policy_name"
    echo ""
  fi
done
```

### List Active Sessions

```bash
# All active sessions
aws ssm describe-sessions \
  --state Active \
  --region ap-southeast-1 \
  --query 'Sessions[*].[SessionId,Target,Owner,StartDate]' \
  --output table

# Filter by specific user
aws ssm describe-sessions \
  --state Active \
  --region ap-southeast-1 \
  --filters "key=Owner,value=john-dev" \
  --query 'Sessions[*].[SessionId,Target,StartDate]' \
  --output table
```

### Review Session Logs

#### S3 Audit

```bash
# List all sessions in the last 24 hours
aws s3 ls s3://ssm-onetime-logs-vortech-dev/sessions/ \
  --region ap-southeast-1 \
  --recursive | grep $(date -u -v-24H +%Y-%m-%d)

# Count sessions per user
aws s3 ls s3://ssm-onetime-logs-vortech-dev/sessions/ --recursive | \
  awk '{print $4}' | cut -d'-' -f1-2 | sort | uniq -c | sort -rn

# Download specific user's logs
aws s3 sync s3://ssm-onetime-logs-vortech-dev/sessions/ \
  ./audit/john-dev/ \
  --exclude "*" \
  --include "john-dev-*"
```

#### CloudWatch Audit

```bash
# Search for specific command
aws logs filter-log-events \
  --log-group-name /aws/ssm/onetime-sessions-dev \
  --filter-pattern "sudo" \
  --start-time $(date -u -v-24H +%s)000 \
  --region ap-southeast-1

# Search for specific user
aws logs filter-log-events \
  --log-group-name /aws/ssm/onetime-sessions-dev \
  --filter-pattern "john-dev" \
  --start-time $(date -u -v-7d +%s)000 \
  --region ap-southeast-1 \
  --query 'events[*].message' \
  --output text
```

### Generate Access Report

```bash
#!/bin/bash
# generate-access-report.sh

REPORT_FILE="jit-access-report-$(date +%Y%m%d).txt"

echo "JIT Access Report - $(date)" > "$REPORT_FILE"
echo "========================================" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"

echo "Active Users with JIT Access:" >> "$REPORT_FILE"
echo "----------------------------" >> "$REPORT_FILE"

aws iam list-users --query 'Users[*].UserName' --output text | while read user; do
  policies=$(aws iam list-user-policies --user-name "$user" --query 'PolicyNames' --output text 2>/dev/null)
  if echo "$policies" | grep -q "OneTimeSSM"; then
    echo "User: $user" >> "$REPORT_FILE"
    echo "  Policies: $policies" >> "$REPORT_FILE"

    # Check sessions
    sessions=$(aws ssm describe-sessions --state Active --region ap-southeast-1 \
      --filters "key=Owner,value=$user" --query 'Sessions[*].SessionId' --output text)

    if [ -n "$sessions" ]; then
      echo "  Active Sessions: $sessions" >> "$REPORT_FILE"
    else
      echo "  Active Sessions: None" >> "$REPORT_FILE"
    fi
    echo "" >> "$REPORT_FILE"
  fi
done

echo "" >> "$REPORT_FILE"
echo "Recent Session Activity (Last 7 Days):" >> "$REPORT_FILE"
echo "--------------------------------------" >> "$REPORT_FILE"

aws s3 ls s3://ssm-onetime-logs-vortech-dev/sessions/ --recursive | \
  grep $(date -u -v-7d +%Y-%m-%d) | \
  awk '{print $4}' | cut -d'-' -f1-2 | sort | uniq -c | sort -rn >> "$REPORT_FILE"

echo "" >> "$REPORT_FILE"
echo "Report generated: $(date)" >> "$REPORT_FILE"

cat "$REPORT_FILE"
```

### Set Up Alerts

#### CloudWatch Alarm for Failed Access

```bash
# Create SNS topic for alerts
aws sns create-topic --name ssm-access-alerts --region ap-southeast-1

# Subscribe to alerts
aws sns subscribe \
  --topic-arn arn:aws:sns:ap-southeast-1:937206802878:ssm-access-alerts \
  --protocol email \
  --notification-endpoint admin@company.com

# Create metric filter for AccessDenied
aws logs put-metric-filter \
  --log-group-name /aws/ssm/onetime-sessions-dev \
  --filter-name SSMAccessDenied \
  --filter-pattern "AccessDeniedException" \
  --metric-transformations \
    metricName=SSMAccessDeniedCount,metricNamespace=SSM,metricValue=1

# Create alarm
aws cloudwatch put-metric-alarm \
  --alarm-name ssm-access-denied-alarm \
  --alarm-description "Alert on SSM access denied attempts" \
  --metric-name SSMAccessDeniedCount \
  --namespace SSM \
  --statistic Sum \
  --period 300 \
  --evaluation-periods 1 \
  --threshold 3 \
  --comparison-operator GreaterThanThreshold \
  --alarm-actions arn:aws:sns:ap-southeast-1:937206802878:ssm-access-alerts
```

### When to Use This Pattern

✅ Compliance audits
✅ Security reviews
✅ Access tracking
✅ Activity monitoring
✅ Incident investigation

---

## Use Case 9: Self-Service User Setup

**Scenario:** Allow developers to set up their own access via a portal or chatbot.

### Wrapper Script for Self-Service

```bash
#!/bin/bash
# self-service-jit-access.sh

set -euo pipefail

# Configuration
ADMIN_PROFILE="admin"
REGION="ap-southeast-1"
DEFAULT_DURATION=240  # 4 hours
JIT_SCRIPT="/path/to/jit-admin-session-v1.0.5"

# Get user input
echo "🔐 JIT Access Self-Service Portal"
echo "=================================="
echo ""

read -p "Enter your username: " USERNAME
read -p "Enter instance ID (i-xxxxx): " INSTANCE_ID
read -p "Duration in minutes (default: 240): " DURATION
DURATION=${DURATION:-$DEFAULT_DURATION}

# Validate
if [[ ! "$USERNAME" =~ ^[a-zA-Z0-9-]+$ ]]; then
  echo "❌ Invalid username. Use only letters, numbers, and hyphens."
  exit 1
fi

if [[ ! "$INSTANCE_ID" =~ ^i-[a-f0-9]{8,17}$ ]]; then
  echo "❌ Invalid instance ID format."
  exit 1
fi

if [[ "$DURATION" -lt 1 || "$DURATION" -gt 240 ]]; then
  echo "❌ Duration must be between 1 and 240 minutes."
  exit 1
fi

# Verify instance exists and is online
echo ""
echo "🔍 Verifying instance..."
INSTANCE_STATUS=$(aws ssm describe-instance-information \
  --filters "Key=InstanceIds,Values=$INSTANCE_ID" \
  --region "$REGION" \
  --profile "$ADMIN_PROFILE" \
  --query 'InstanceInformationList[0].PingStatus' \
  --output text 2>/dev/null || echo "NOT_FOUND")

if [ "$INSTANCE_STATUS" != "Online" ]; then
  echo "❌ Instance $INSTANCE_ID is not available or not online."
  exit 1
fi

echo "✅ Instance verified: $INSTANCE_ID"
echo ""

# Check if user exists
USER_EXISTS=$(aws iam get-user --user-name "$USERNAME" --profile "$ADMIN_PROFILE" 2>/dev/null && echo "true" || echo "false")

if [ "$USER_EXISTS" = "true" ]; then
  echo "ℹ️  User $USERNAME already exists. Renewing access..."

  "$JIT_SCRIPT" \
    -u "$USERNAME" \
    -i "$INSTANCE_ID" \
    -d "$DURATION" \
    --purge-existing \
    --region "$REGION" \
    --local-admin-profile "$ADMIN_PROFILE"
else
  echo "🆕 Creating new user $USERNAME..."

  SCRIPT_NAME="setup-${USERNAME}.sh"

  "$JIT_SCRIPT" \
    -u "$USERNAME" \
    -i "$INSTANCE_ID" \
    -d "$DURATION" \
    --new-user \
    --create-keys \
    --output-script "$SCRIPT_NAME" \
    --region "$REGION" \
    --local-admin-profile "$ADMIN_PROFILE"

  echo ""
  echo "✅ Setup complete!"
  echo ""
  echo "📄 Your setup script: $SCRIPT_NAME"
  echo ""
  echo "📋 Next steps:"
  echo "   1. Download: $SCRIPT_NAME"
  echo "   2. Run: bash $SCRIPT_NAME"
  echo ""
fi
```

### Slack Bot Integration Example

```python
# slack_jit_bot.py
import subprocess
import re
from slack_bolt import App

app = App(token="xoxb-your-token")

@app.command("/jit-access")
def handle_jit_access(ack, command, respond):
    ack()

    # Parse command: /jit-access i-0abc123def456 60
    params = command['text'].split()

    if len(params) < 1:
        respond("Usage: /jit-access <instance-id> [duration-minutes]")
        return

    instance_id = params[0]
    duration = params[1] if len(params) > 1 else "240"
    username = command['user_name']

    # Validate instance ID
    if not re.match(r'^i-[a-f0-9]{8,17}$', instance_id):
        respond(f"❌ Invalid instance ID: {instance_id}")
        return

    # Run jit-admin-session
    try:
        result = subprocess.run([
            './jit-admin-session-v1.0.5',
            '-u', username,
            '-i', instance_id,
            '-d', duration,
            '--new-user',
            '--create-keys',
            '--configure-profile', username,
            '--region', 'ap-southeast-1'
        ], capture_output=True, text=True, timeout=60)

        if result.returncode == 0:
            respond(f"""✅ Access granted!

**User:** {username}
**Instance:** {instance_id}
**Duration:** {duration} minutes

**Connect with:**
```
aws ssm start-session \\
  --target {instance_id} \\
  --document-name SSM-SessionManagerRunShell \\
  --region ap-southeast-1 \\
  --profile {username}
```

Access expires in {duration} minutes.
""")
        else:
            respond(f"❌ Error granting access:\n```{result.stderr}```")

    except subprocess.TimeoutExpired:
        respond("❌ Request timed out. Please try again.")
    except Exception as e:
        respond(f"❌ Error: {str(e)}")

if __name__ == "__main__":
    app.start(port=3000)
```

### When to Use This Pattern

✅ Large teams with frequent access needs
✅ Self-service portals
✅ Chatbot integrations (Slack, Teams)
✅ Automated approval workflows
✅ Developer productivity tools

---

## Use Case 10: Bulk Access Management

**Scenario:** Grant access to multiple users for a training session or team event.

### Bulk User Creation

```bash
#!/bin/bash
# bulk-create-users.sh

INSTANCE_ID="i-0training123456789"
DURATION=480  # 8 hours
REGION="ap-southeast-1"

# List of users
USERS=(
  "trainee-alice"
  "trainee-bob"
  "trainee-carol"
  "trainee-david"
  "trainee-eve"
)

echo "🚀 Bulk JIT Access Creation"
echo "==========================="
echo "Instance: $INSTANCE_ID"
echo "Duration: $DURATION minutes"
echo "Users: ${#USERS[@]}"
echo ""

for user in "${USERS[@]}"; do
  echo "Creating access for: $user"

  ./jit-admin-session-v1.0.5 \
    -u "$user" \
    -i "$INSTANCE_ID" \
    -d "$DURATION" \
    --new-user \
    --create-keys \
    --output-script "setup-${user}.sh" \
    --region "$REGION"

  echo "✅ $user created"
  echo ""
done

echo ""
echo "✅ All users created!"
echo ""
echo "📤 Distribute setup scripts:"
for user in "${USERS[@]}"; do
  echo "  - setup-${user}.sh → ${user}@company.com"
done
```

### Bulk Renewal

```bash
#!/bin/bash
# bulk-renew-users.sh

INSTANCE_ID="i-0training123456789"
DURATION=240
REGION="ap-southeast-1"

USERS=(
  "trainee-alice"
  "trainee-bob"
  "trainee-carol"
  "trainee-david"
  "trainee-eve"
)

for user in "${USERS[@]}"; do
  echo "Renewing access for: $user"

  ./jit-admin-session-v1.0.5 \
    -u "$user" \
    -i "$INSTANCE_ID" \
    -d "$DURATION" \
    --purge-existing \
    --region "$REGION"

  echo "✅ $user renewed"
done
```

### Bulk Cleanup

```bash
#!/bin/bash
# bulk-cleanup-users.sh

REGION="ap-southeast-1"

USERS=(
  "trainee-alice"
  "trainee-bob"
  "trainee-carol"
  "trainee-david"
  "trainee-eve"
)

echo "🧹 Bulk Cleanup"
echo "==============="
echo ""

for user in "${USERS[@]}"; do
  echo "Cleaning up: $user"

  ./jit-admin-session-v1.0.5 \
    --purge-session "$user" \
    --region "$REGION" <<< "y"  # Auto-confirm key deletion

  # Optionally delete the user entirely
  # aws iam delete-user --user-name "$user"

  echo ""
done

echo "✅ Cleanup complete!"
```

### CSV-Based Bulk Access

```bash
#!/bin/bash
# csv-bulk-access.sh

# users.csv format:
# username,instance_id,duration
# john-dev,i-0abc123,240
# jane-ops,i-0def456,480

CSV_FILE="users.csv"
REGION="ap-southeast-1"

while IFS=, read -r username instance_id duration; do
  # Skip header
  if [ "$username" = "username" ]; then
    continue
  fi

  echo "Creating access: $username → $instance_id ($duration min)"

  ./jit-admin-session-v1.0.5 \
    -u "$username" \
    -i "$instance_id" \
    -d "$duration" \
    --new-user \
    --create-keys \
    --output-script "setup-${username}.sh" \
    --region "$REGION"

  echo ""
done < "$CSV_FILE"
```

### When to Use This Pattern

✅ Training sessions
✅ Workshops
✅ Hackathons
✅ Team onboarding
✅ Temporary project teams

---

## Advanced Scenarios

### Scenario 1: Different Regions

```bash
# US East
./jit-admin-session-v1.0.5 \
  -u user-us \
  -i i-0useast123456789 \
  -d 240 \
  --new-user \
  --create-keys \
  --region us-east-1

# EU West
./jit-admin-session-v1.0.5 \
  -u user-eu \
  -i i-0euwest123456789 \
  -d 240 \
  --new-user \
  --create-keys \
  --region eu-west-1

# Asia Pacific
./jit-admin-session-v1.0.5 \
  -u user-ap \
  -i i-0apsouth123456789 \
  -d 240 \
  --new-user \
  --create-keys \
  --region ap-southeast-1
```

### Scenario 2: Cross-Account Access

```bash
# Assume role in target account first
aws sts assume-role \
  --role-arn arn:aws:iam::123456789012:role/JITAdminRole \
  --role-session-name jit-admin-session > /tmp/creds.json

# Export credentials
export AWS_ACCESS_KEY_ID=$(jq -r '.Credentials.AccessKeyId' /tmp/creds.json)
export AWS_SECRET_ACCESS_KEY=$(jq -r '.Credentials.SecretAccessKey' /tmp/creds.json)
export AWS_SESSION_TOKEN=$(jq -r '.Credentials.SessionToken' /tmp/creds.json)

# Now run jit-admin-session
./jit-admin-session-v1.0.5 \
  -u user-cross-account \
  -i i-0targetaccount123 \
  -d 240 \
  --new-user \
  --create-keys \
  --region ap-southeast-1
```

### Scenario 3: Integration with Approval Workflow

```bash
#!/bin/bash
# approved-jit-access.sh

# Get approval from manager
echo "🔐 JIT Access Request"
echo "===================="
read -p "Username: " USERNAME
read -p "Instance ID: " INSTANCE_ID
read -p "Duration (minutes): " DURATION
read -p "Business justification: " JUSTIFICATION

# Log request
echo "$(date): $USERNAME requested $DURATION min access to $INSTANCE_ID - $JUSTIFICATION" \
  >> /var/log/jit-requests.log

# Send approval request (example: email)
echo "JIT Access Request

User: $USERNAME
Instance: $INSTANCE_ID
Duration: $DURATION minutes
Justification: $JUSTIFICATION

Approve: ./approve-jit.sh $USERNAME $INSTANCE_ID $DURATION
Deny: ./deny-jit.sh $USERNAME
" | mail -s "JIT Access Request - $USERNAME" manager@company.com

echo "✅ Request submitted. Awaiting approval..."
```

### Scenario 4: Time-Window Restrictions

```bash
#!/bin/bash
# business-hours-jit.sh

CURRENT_HOUR=$(date +%H)
CURRENT_DAY=$(date +%u)  # 1-7 (Mon-Sun)

# Only allow 9 AM - 6 PM, Monday-Friday
if [ "$CURRENT_HOUR" -lt 9 ] || [ "$CURRENT_HOUR" -ge 18 ]; then
  echo "❌ JIT access only available during business hours (9 AM - 6 PM)"
  exit 1
fi

if [ "$CURRENT_DAY" -gt 5 ]; then
  echo "❌ JIT access only available on weekdays"
  exit 1
fi

# Proceed with access grant
./jit-admin-session-v1.0.5 "$@"
```

---

## Troubleshooting

### Issue 1: AccessDeniedException when starting session

**Symptoms:**
```
An error occurred (AccessDeniedException) when calling the StartSession operation
```

**Diagnosis:**
```bash
# Check if user has active policy
aws iam list-user-policies --user-name USERNAME

# Check if policy has expired
# Policies expire after the duration specified
```

**Solutions:**

1. **Policy Expired** - Renew access:
```bash
./jit-admin-session-v1.0.5 \
  -u USERNAME \
  -i INSTANCE_ID \
  -d 240 \
  --purge-existing
```

2. **Missing Document Name** - Use correct command:
```bash
# Wrong (will fail)
aws ssm start-session --target i-xxx --profile USERNAME

# Correct
aws ssm start-session \
  --target i-xxx \
  --document-name SSM-SessionManagerRunShell \
  --profile USERNAME
```

3. **Tag Mismatch** - Instance doesn't have required tag:
```bash
# Check instance tags
aws ec2 describe-tags --filters "Name=resource-id,Values=INSTANCE_ID"

# Add required tag
aws ec2 create-tags \
  --resources INSTANCE_ID \
  --tags Key=Environment,Value=Staging
```

### Issue 2: Instance not online in SSM

**Diagnosis:**
```bash
aws ssm describe-instance-information \
  --filters "Key=InstanceIds,Values=INSTANCE_ID" \
  --region REGION
```

**Solutions:**

1. **SSM Agent not running:**
```bash
# SSH to instance
sudo systemctl status amazon-ssm-agent
sudo systemctl start amazon-ssm-agent
```

2. **Missing IAM role:**
```bash
# Check instance profile
aws ec2 describe-instances \
  --instance-ids INSTANCE_ID \
  --query 'Reservations[0].Instances[0].IamInstanceProfile'

# Attach role with AmazonSSMManagedInstanceCore policy
```

3. **Network connectivity:**
- Check security groups allow outbound HTTPS (443)
- Check VPC endpoints for Systems Manager

### Issue 3: User creation fails

**Error:**
```
EntityAlreadyExists: User with name USERNAME already exists
```

**Solution:**
```bash
# Remove --new-user flag if user exists
./jit-admin-session-v1.0.5 \
  -u USERNAME \
  -i INSTANCE_ID \
  -d 240 \
  --purge-existing  # Remove --new-user
```

### Issue 4: No logs in S3

**Diagnosis:**
```bash
# Check session document configuration
aws ssm get-document \
  --name SSM-SessionManagerRunShell \
  --query 'Content' \
  --output text | jq '.inputs'
```

**Issue:** Using `send-command` instead of `start-session`

**Solution:** Use proper session command:
```bash
# Wrong (no logs)
aws ssm send-command --document-name "AWS-RunShellScript"

# Correct (creates logs)
aws ssm start-session \
  --document-name SSM-SessionManagerRunShell
```

### Issue 5: Script not found

**Error:**
```bash
./jit-admin-session-v1.0.5: No such file or directory
```

**Solution:**
```bash
# Make sure you're in the right directory
cd /Users/vinson/Documents/0_Other_Services/SSM/jit-admin

# Make script executable
chmod +x jit-admin-session-v1.0.5

# Or use full path
/Users/vinson/Documents/0_Other_Services/SSM/jit-admin/jit-admin-session-v1.0.5 \
  -u USERNAME -i INSTANCE_ID -d 240 --new-user --create-keys
```

---

## Best Practices

### Security Best Practices

1. **Principle of Least Privilege**
```bash
# Shortest duration necessary
./jit-admin-session-v1.0.5 -u USER -i INSTANCE -d 30  # 30 min, not 240 min

# Use tag restrictions
--require-tag Environment=NonProd

# Revoke immediately after use
./jit-admin-session-v1.0.5 --purge-session USER
```

2. **Regular Audits**
```bash
# Weekly access review
./generate-access-report.sh

# Review session logs monthly
aws s3 ls s3://ssm-onetime-logs-vortech-dev/sessions/ --recursive
```

3. **Never Share Credentials**
```bash
# Generate individual setup scripts
--output-script setup-USERNAME.sh

# Each user gets their own IAM user
# Never share AWS access keys
```

### Operational Best Practices

1. **Document Access Requests**
```bash
# Log all access grants
echo "$(date): Granted $USERNAME access to $INSTANCE_ID for $DURATION min - Reason: $REASON" \
  >> /var/log/jit-access.log
```

2. **Set Appropriate Durations**
```bash
# Emergency fix: 1-2 hours
-d 120

# Development work: 4-8 hours
-d 480

# Never use maximum (240 min = 4 hours) unless necessary
```

3. **Use Descriptive Usernames**
```bash
# Good
-u john-dev-frontend
-u sarah-dba-migration
-u vendor-acme-integration

# Bad
-u user1
-u temp
-u test
```

### Automation Best Practices

1. **Use Environment Variables**
```bash
# .env file
export JIT_DEFAULT_REGION="ap-southeast-1"
export JIT_DEFAULT_DURATION="240"
export JIT_SCRIPT_PATH="/Users/vinson/Documents/0_Other_Services/SSM/jit-admin/jit-admin-session-v1.0.5"

# In scripts
"$JIT_SCRIPT_PATH" -u "$USER" -i "$INSTANCE" -d "$JIT_DEFAULT_DURATION"
```

2. **Error Handling**
```bash
#!/bin/bash
set -euo pipefail

if ! ./jit-admin-session-v1.0.5 -u "$USER" -i "$INSTANCE" -d 240 --new-user --create-keys; then
  echo "❌ Failed to create access for $USER"
  # Send alert
  curl -X POST "https://hooks.slack.com/..." \
    -d "{\"text\":\"JIT access creation failed for $USER\"}"
  exit 1
fi
```

3. **Idempotency**
```bash
# Always use --purge-existing for renewals
# This makes scripts idempotent (safe to run multiple times)

./jit-admin-session-v1.0.5 \
  -u "$USER" \
  -i "$INSTANCE" \
  -d 240 \
  --purge-existing  # Cleanup old access first
```

### Monitoring Best Practices

1. **Set Up Alerts**
```bash
# Alert on failed access attempts
# Alert on access duration > 4 hours
# Alert on access outside business hours
```

2. **Regular Cleanup**
```bash
# Weekly cleanup script
#!/bin/bash
# Find users with expired policies (no OneTimeSSM policies)
# Check for orphaned access keys
# Review and remove unused IAM users
```

3. **Log Retention**
```bash
# S3 lifecycle policy for session logs
# Keep logs for 90 days minimum
# Archive older logs to Glacier
```

---

## Quick Decision Tree

```
Need JIT Access?
│
├─ New User?
│  ├─ Yes → Use: --new-user --create-keys --output-script
│  └─ No → Use: --purge-existing
│
├─ Multiple Instances?
│  ├─ Sequential → Renew with different -i for each
│  └─ Simultaneous → Use: --require-tag
│
├─ Contractor/Vendor?
│  └─ Yes → Use: --require-tag Environment=Staging
│
├─ Emergency?
│  └─ Yes → Use: short duration (60-120 min)
│
└─ Done with Access?
   └─ Use: --purge-session
```

---

## Summary

### Most Common Commands

```bash
# 1. New developer (most common)
./jit-admin-session-v1.0.5 -u USERNAME -i INSTANCE_ID -d 240 \
  --new-user --create-keys --output-script setup-USERNAME.sh

# 2. Renew access (second most common)
./jit-admin-session-v1.0.5 -u USERNAME -i INSTANCE_ID -d 240 --purge-existing

# 3. Emergency access
./jit-admin-session-v1.0.5 -u USERNAME -i INSTANCE_ID -d 120 --new-user --create-keys --configure-profile USERNAME

# 4. Revoke access
./jit-admin-session-v1.0.5 --purge-session USERNAME

# 5. Contractor with restrictions
./jit-admin-session-v1.0.5 -u CONTRACTOR -i INSTANCE_ID -d 240 \
  --new-user --create-keys --output-script setup-CONTRACTOR.sh \
  --require-tag Environment=Staging
```

---

## Getting Help

### Built-in Help
```bash
./jit-admin-session-v1.0.5 --help
```

### Documentation
- **Setup Guide:** `/Users/vinson/Documents/0_Other_Services/SSM/SETUP_GUIDE.md`
- **Logging Guide:** `/Users/vinson/Documents/0_Other_Services/SSM/HOW_TO_SEE_LOGS.md`
- **Test Results:** `/Users/vinson/Documents/0_Other_Services/SSM/TEST_RESULTS.md`

### Support Resources
- AWS SSM Documentation: https://docs.aws.amazon.com/systems-manager/
- Session Manager: https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager.html

---

**Document Version:** 1.0
**Last Updated:** November 15, 2025
**Script Version:** jit-admin-session-v1.0.5
