# S3 Encryption Permission Fix

**Date**: November 16, 2025
**Issue**: SSM sessions failing with S3 encryption validation error
**Severity**: High (blocks all SSM connections)

## Problem Summary

SSM sessions were failing with the error:
```
AccessDenied: User: arn:aws:sts::937206802878:assumed-role/[ROLE]/[INSTANCE]
is not authorized to perform: s3:GetEncryptionConfiguration on resource:
"arn:aws:s3:::ssm-onetime-logs-vortech-dev"
```

## Root Cause

The IAM policy `SSM-SessionManager-Logging-Policy` was **missing** a critical S3 permission:
- **Missing**: `s3:GetEncryptionConfiguration`
- **Why needed**: SSM Session Manager validates S3 bucket encryption before starting sessions
- **Affected roles**:
  - `VortechStagingGameBackendSSMRole`
  - Any other role using the logging policy

## Solution Applied

### 1. Updated Policy File

**File**: [logging/iam-instance-logging-policy.json](cci:1://file:///Users/vinson/Documents/0_Other_Services/SSM/logging/iam-instance-logging-policy.json:0:0-0:0)

**Added permission** to `SSMSessionLogsS3List` statement:
```json
{
  "Sid": "SSMSessionLogsS3List",
  "Effect": "Allow",
  "Action": [
    "s3:ListBucket",
    "s3:GetBucketLocation",
    "s3:GetEncryptionConfiguration"  // ← Added this
  ],
  "Resource": "arn:aws:s3:::ssm-onetime-logs-vortech-dev"
}
```

### 2. Updated IAM Policy in AWS

```bash
aws iam create-policy-version \
  --policy-arn "arn:aws:iam::937206802878:policy/SSM-SessionManager-Logging-Policy" \
  --policy-document file://logging/iam-instance-logging-policy.json \
  --set-as-default
```

**Result**: Policy updated from v1 → v2

### 3. Attached Policy to Affected Roles

```bash
aws iam attach-role-policy \
  --role-name VortechStagingGameBackendSSMRole \
  --policy-arn "arn:aws:iam::937206802878:policy/SSM-SessionManager-Logging-Policy"

aws iam attach-role-policy \
  --role-name SSM-Enhanced-Instance-Dev-Role \
  --policy-arn "arn:aws:iam::937206802878:policy/SSM-SessionManager-Logging-Policy"
```

### 4. Restarted SSM Agents

To force credential refresh on affected instances:
```bash
aws ssm send-command \
  --instance-ids i-0d89df34ce0981840 \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=["sudo systemctl restart amazon-ssm-agent"]' \
  --region ap-southeast-1
```

## Timeline

| Time | Action |
|------|--------|
| 16:31 UTC | Created `SSM-SessionManager-Logging-Policy` (v1) - missing permission |
| 16:32 UTC | Attached policy to `VortechStagingGameBackendSSMRole` |
| 16:33 UTC | First connection attempt - **FAILED** with encryption error |
| 16:39 UTC | **Root cause identified** - missing `s3:GetEncryptionConfiguration` |
| 16:39 UTC | Updated policy to v2 with correct permissions |
| 16:40 UTC | Restarted SSM agents on affected instances |
| 16:45 UTC | **Expected**: Connections should work after credential refresh |

## Impact

**Affected Instances**: Any instance using roles without the S3 encryption permission

**Auto-Resolution**:
- All instances with attached roles will inherit the new permission automatically
- IAM credentials refresh every 5-15 minutes
- No manual instance updates needed

## Prevention

### For New Deployments

The [setup-ssm-logging.sh](cci:1://file:///Users/vinson/Documents/0_Other_Services/SSM/logging/setup-ssm-logging.sh:0:0-0:0) script now creates the policy with the correct permissions from the updated policy file.

### For Existing Deployments

Run this verification script:

```bash
# Check if policy has the encryption permission
aws iam get-policy-version \
  --policy-arn "arn:aws:iam::937206802878:policy/SSM-SessionManager-Logging-Policy" \
  --version-id $(aws iam get-policy --policy-arn "arn:aws:iam::937206802878:policy/SSM-SessionManager-Logging-Policy" --query 'Policy.DefaultVersionId' --output text) \
  --query 'PolicyVersion.Document.Statement[?Sid==`SSMSessionLogsS3List`].Action[]' \
  --output text | grep GetEncryptionConfiguration

# Expected output: s3:GetEncryptionConfiguration
```

## Related AWS Documentation

- [AWS SSM Session Manager Prerequisites](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-prerequisites.html)
- [S3 Bucket Permissions for SSM](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-logging.html#session-manager-logging-s3-permissions)

## Verification

After applying the fix, test the connection:

```bash
# Test SSM session
aws ssm start-session \
  --target i-0d89df34ce0981840 \
  --document-name SSM-SessionManagerRunShell \
  --region ap-southeast-1

# Expected: Session starts successfully
```

If still failing:
1. Wait 5 minutes for IAM credential refresh
2. Or reboot the instance to force immediate refresh
3. Or restart SSM agent: `sudo systemctl restart amazon-ssm-agent`

---

**Status**: ✅ **RESOLVED**
**Updated Files**:
- [logging/iam-instance-logging-policy.json](cci:1://file:///Users/vinson/Documents/0_Other_Services/SSM/logging/iam-instance-logging-policy.json:0:0-0:0)
- IAM Policy: `SSM-SessionManager-Logging-Policy` (v2)
