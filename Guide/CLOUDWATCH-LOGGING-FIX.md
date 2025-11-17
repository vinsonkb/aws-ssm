# CloudWatch Logging Fix Summary

**Date:** November 16, 2025
**Issue:** CloudWatch real-time logging not working
**Status:** ✅ RESOLVED

---

## 🔍 Problem Discovery

CloudWatch logs were not appearing despite:
- ✅ CloudWatch log group existing (`/aws/ssm/onetime-sessions-dev`)
- ✅ SSM document properly configured with CloudWatch settings
- ✅ S3 logging working perfectly
- ✅ IAM policy seemingly having correct permissions

**Error in SSM Agent Logs:**
```
ERROR AccessDeniedException: User: arn:aws:sts::937206802878:assumed-role/
SSM-Enhanced-Instance-Dev-Role/i-0ee0bc84a481f7852 is not authorized to
perform: logs:DescribeLogGroups on resource:
arn:aws:logs:ap-southeast-1:937206802878:log-group::log-stream: because
no identity-based policy allows the logs:DescribeLogGroups action
```

---

## 🎯 Root Cause

The IAM policy had `logs:DescribeLogGroups` permission, BUT it was scoped to a specific log group resource:

```json
{
  "Action": [
    "logs:DescribeLogGroups",  // ❌ This needs Resource: "*"
    "logs:CreateLogStream",
    "logs:PutLogEvents"
  ],
  "Resource": [
    "arn:aws:logs:ap-southeast-1:*:log-group:/aws/ssm/onetime-sessions-dev",
    "arn:aws:logs:ap-southeast-1:*:log-group:/aws/ssm/onetime-sessions-dev:*"
  ]
}
```

**Why this failed:**
- `logs:DescribeLogGroups` is a **list operation** that queries ALL log groups
- It cannot be scoped to a specific log group
- AWS requires `Resource: "*"` for this action
- When the SSM agent called `DescribeLogGroups`, it didn't specify a log group name, causing the permission check to fail

---

## ✅ Solution

### 1. Split CloudWatch Permissions

**Updated** `logging/iam-instance-logging-policy.json`:

```json
{
  "Sid": "SSMSessionLogsCloudWatchDescribe",
  "Effect": "Allow",
  "Action": [
    "logs:DescribeLogGroups"
  ],
  "Resource": "*"  // ✅ Must be wildcard for list operations
},
{
  "Sid": "SSMSessionLogsCloudWatch",
  "Effect": "Allow",
  "Action": [
    "logs:CreateLogGroup",
    "logs:CreateLogStream",
    "logs:PutLogEvents",
    "logs:DescribeLogStreams"
  ],
  "Resource": [
    "arn:aws:logs:ap-southeast-1:*:log-group:/aws/ssm/onetime-sessions-dev",
    "arn:aws:logs:ap-southeast-1:*:log-group:/aws/ssm/onetime-sessions-dev:*"
  ]
}
```

**Key changes:**
- ✅ `logs:DescribeLogGroups` → separate statement with `Resource: "*"`
- ✅ Other CloudWatch actions → scoped to specific log group
- ✅ Maintains least-privilege principle while fixing the issue

### 2. Deployed Updated Policy

```bash
aws iam put-role-policy \
  --role-name SSM-Enhanced-Instance-Dev-Role \
  --policy-name SSM-Enhanced-Logging-Dev-Policy \
  --policy-document file://logging/iam-instance-logging-policy.json \
  --region ap-southeast-1
```

### 3. Restarted SSM Agent

```bash
aws ssm send-command \
  --instance-ids i-0ee0bc84a481f7852 \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=["sudo systemctl restart amazon-ssm-agent"]' \
  --region ap-southeast-1
```

### 4. Additional Improvements

**Upgraded SSM Agent:**
- Old version: 3.3.2299.0
- New version: 3.3.3270.0 (latest)
- Fixed IOConfig CloudWatch issues

**Cleaned SSM Document:**
- Deleted broken versions 2 & 3
- Kept version 1 (default) with correct configuration

---

## ✅ Verification

### Test 1: CloudWatch Real-Time Logging
```bash
# Start new session
aws ssm start-session \
  --target i-0ee0bc84a481f7852 \
  --document-name SSM-SessionManagerRunShell \
  --region ap-southeast-1 \
  --profile vinson-devops-03

# In another terminal, tail logs
aws logs tail /aws/ssm/onetime-sessions-dev \
  --follow \
  --region ap-southeast-1
```

**Result:** ✅ Logs appear in real-time (1-5 second delay)

### Test 2: S3 Logging
```bash
# After session ends, check S3
aws s3 ls s3://ssm-onetime-logs-vortech-dev/sessions/ \
  --recursive \
  --region ap-southeast-1 \
  | grep vinson-devops-03
```

**Result:** ✅ Logs upload within 1-2 minutes (faster than expected 5-15 min)

### Test 3: SSM Agent Logs
```bash
# Check agent logs for errors
aws ssm send-command \
  --instance-ids i-0ee0bc84a481f7852 \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=["sudo grep -i \"cloudwatch\\|error\" /var/log/amazon/ssm/amazon-ssm-agent.log | tail -20"]' \
  --region ap-southeast-1
```

**Result:** ✅ No more AccessDeniedException errors

---

## 📊 Final Status

| Component | Before Fix | After Fix |
|-----------|------------|-----------|
| **CloudWatch Logs** | ❌ Not working | ✅ Working (1-5 sec delay) |
| **S3 Logs** | ✅ Working | ✅ Working (1-2 min delay) |
| **Instance Logs** | ✅ Working | ✅ Working |
| **SSM Agent** | ⚠️ v3.3.2299.0 | ✅ v3.3.3270.0 (latest) |
| **IAM Policy** | ❌ Incorrect scope | ✅ Correct scope |
| **SSM Document** | ⚠️ 3 versions | ✅ 1 version (clean) |

---

## 📚 Key Learnings

1. **AWS IAM List Operations**
   - Actions like `DescribeLogGroups`, `ListBuckets`, etc. require `Resource: "*"`
   - Cannot be scoped to specific resources
   - Always check AWS documentation for resource-level permissions

2. **SSM Agent Logging**
   - Agent logs provide critical error details (`/var/log/amazon/ssm/amazon-ssm-agent.log`)
   - Check `IOConfig.CloudWatchConfig` in agent logs for actual runtime configuration
   - Empty `CloudWatchConfig.LogGroupName` indicates CloudWatch streaming is disabled

3. **IAM Credential Refresh**
   - EC2 instances cache IAM role credentials
   - Changes to IAM policies require SSM agent restart or credential refresh (5-15 min)
   - Use `sudo systemctl restart amazon-ssm-agent` to force immediate refresh

4. **SSM Document Versioning**
   - Multiple versions can exist (default vs. latest)
   - Always verify which version is the default
   - Clean up unused versions to avoid confusion

---

## 🔗 Related Files Updated

1. ✅ `/logging/iam-instance-logging-policy.json` - Fixed IAM permissions
2. ✅ `/Guide/TEST_RESULTS.md` - Added CloudWatch fix section
3. ✅ `/Guide/CLOUDWATCH-LOGGING-FIX.md` - This document

---

## 🎯 Action Items for Future Setups

When setting up CloudWatch logging for SSM:

1. **Always split `logs:DescribeLogGroups` into separate statement** with `Resource: "*"`
2. **Verify SSM agent version** - use latest version (3.3.3270.0+)
3. **Test CloudWatch logging** immediately after setup
4. **Check SSM agent logs** for permission errors
5. **Clean up old SSM document versions** to avoid confusion

---

**Fix applied by:** Claude Code
**Verified by:** User testing
**Status:** ✅ Production ready
**Date:** November 16, 2025
