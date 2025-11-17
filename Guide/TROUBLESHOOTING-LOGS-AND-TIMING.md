# Troubleshooting: Logs and Timing Issues

**Understanding SSM Session Manager logging delays and IAM eventual consistency**

---

## 🎯 Common Issues Explained

### Issue 1: "I Can't Find Logs in S3!"

**Symptom:** Sessions completed but no logs in S3 bucket

**Root Cause:** **AWS SSM uploads S3 logs in batches with 5-15 minute delay**

**Why This Happens:**
- CloudWatch logs stream in **real-time** (instant)
- S3 logs upload in **batches** every 5-15 minutes
- This is normal AWS behavior, not a configuration issue

**Timeline:**
```
Session Starts     → CloudWatch logs appear immediately
Session Ends       → CloudWatch has full log
   ↓ (5-15 minutes delay)
S3 Upload          → S3 log file appears
```

**✅ Solution:**

Use the log checker script:
```bash
cd /Users/vinson/Documents/0_Other_Services/SSM/jit-admin
./check-session-logs.sh USERNAME
```

Or check CloudWatch for immediate logs:
```bash
# Real-time logs (no delay)
aws logs tail /aws/ssm/onetime-sessions-dev \
  --follow \
  --filter-pattern "USERNAME" \
  --region ap-southeast-1
```

Wait 15 minutes then check S3:
```bash
# S3 logs (5-15 min delay)
aws s3 ls s3://ssm-onetime-logs-vortech-dev/sessions/ \
  --region ap-southeast-1 | grep USERNAME
```

---

### Issue 2: "User Can Still Connect After Time Expired!"

**Symptom:**
- 3-minute timer expired
- User got kicked out
- User ran script again and could reconnect
- After 2-3 reconnects, finally got AccessDenied

**Root Cause:** **IAM Eventual Consistency** (AWS global propagation delay)

**Why This Happens:**
1. ✅ **Timer expires** (e.g., 3 minutes)
2. ✅ **Enforcer deletes IAM policy** immediately
3. ⏳ **AWS takes 5-60 seconds** to propagate deletion globally
4. ⚠️ **User can still connect** during propagation window
5. ✅ **AccessDenied appears** after full propagation (30-90 seconds)

**Timeline:**
```
00:00 - Policy created
03:00 - Timer expires
03:00 - Enforcer deletes policy (instant)
03:05 - User tries to connect → SUCCESS (IAM not propagated yet)
03:10 - Enforcer terminates session
03:15 - User tries to connect → SUCCESS (cached credentials)
03:20 - Enforcer terminates session again
03:30 - User tries to connect → DENIED (IAM fully propagated)
```

**✅ Solution (Improved in v1.0.5):**

The script now runs **3 termination rounds over 60 seconds**:
```bash
# Old behavior (v1.0.4)
Expire → Delete policy once → Terminate sessions once

# New behavior (v1.0.5)
Expire → Delete policy → Terminate (round 1)
       → Wait 20 sec    → Terminate (round 2)
       → Wait 20 sec    → Terminate (round 3)
```

**Expected Behavior:**
- First reconnect might work (5-30 seconds)
- Gets terminated within 20 seconds
- Second reconnect might work (rare)
- Gets terminated within 20 seconds
- Third reconnect → AccessDenied (IAM propagated)

**This is normal AWS behavior and CANNOT be completely eliminated.**

---

## 📊 Timing Reference Guide

### CloudWatch Logs
| Event | Delay | Available |
|-------|-------|-----------|
| Session starts | 0 seconds | ✅ Immediate |
| Command executed | 0-5 seconds | ✅ Real-time |
| Session ends | 0 seconds | ✅ Immediate |

### S3 Logs
| Event | Delay | Available |
|-------|-------|-----------|
| Session starts | N/A | ⏳ Not yet |
| Session ends | **5-15 minutes** | ⏳ Batch upload |
| Log file created | After upload | ✅ Permanent |

### IAM Policy Changes
| Event | Delay | Effect |
|-------|-------|--------|
| Policy created | 0-5 seconds | ⏳ Eventual consistency |
| Policy deleted | 5-60 seconds | ⏳ Global propagation |
| Fully propagated | 30-90 seconds | ✅ AccessDenied works |

### Session Termination
| Event | Delay | Result |
|-------|-------|--------|
| Enforcer runs | 0 seconds | ✅ Immediate |
| terminate-session | 1-5 seconds | ⏳ Terminating |
| Session closed | 5-10 seconds | ✅ Terminated |

---

## 🔍 How to Check Logs

### Method 1: Use Log Checker Script (Recommended)

```bash
cd /Users/vinson/Documents/0_Other_Services/SSM/jit-admin
./check-session-logs.sh vinson-devops
```

**Shows:**
- ✅ S3 logs (if available)
- ✅ CloudWatch logs (real-time)
- ✅ Session history

---

### Method 2: Check S3 Manually

```bash
# List logs for specific user
aws s3 ls s3://ssm-onetime-logs-vortech-dev/sessions/ \
  --region ap-southeast-1 | grep USERNAME

# Download latest log
aws s3 cp s3://ssm-onetime-logs-vortech-dev/sessions/USERNAME-*.log \
  ./session.log \
  --region ap-southeast-1

# View log
cat ./session.log
```

---

### Method 3: Check CloudWatch (Real-Time)

```bash
# Tail logs (live streaming)
aws logs tail /aws/ssm/onetime-sessions-dev \
  --follow \
  --filter-pattern "USERNAME" \
  --region ap-southeast-1

# Search last hour
aws logs filter-log-events \
  --log-group-name /aws/ssm/onetime-sessions-dev \
  --filter-pattern "USERNAME" \
  --start-time $(($(date +%s) - 3600))000 \
  --region ap-southeast-1
```

---

### Method 4: Check Session History

```bash
# All sessions for user
aws ssm describe-sessions \
  --state History \
  --region ap-southeast-1 \
  --max-results 50 \
  --query "Sessions[?contains(Owner, 'USERNAME')].[SessionId,Status,StartDate,EndDate]" \
  --output table

# Active sessions
aws ssm describe-sessions \
  --state Active \
  --region ap-southeast-1 \
  --filters "key=Owner,value=USERNAME"
```

---

## 🎓 Understanding the Flow

### Complete Session Lifecycle

```
┌─────────────────────────────────────────────────────────────┐
│ ADMIN: Create Access                                        │
│ ./jit-admin-session-v1.0.5 -u USER -i INSTANCE -d 3        │
└─────────────────────────────────────────────────────────────┘
                           ↓
┌─────────────────────────────────────────────────────────────┐
│ IAM Policy Created                                          │
│ ⏳ 0-5 sec: Policy propagating                              │
│ ✅ 5-10 sec: Policy active globally                         │
└─────────────────────────────────────────────────────────────┘
                           ↓
┌─────────────────────────────────────────────────────────────┐
│ USER: bash setup-USER.sh                                    │
│ ✅ Connects to instance                                     │
│ ✅ CloudWatch logging starts (real-time)                    │
└─────────────────────────────────────────────────────────────┘
                           ↓
┌─────────────────────────────────────────────────────────────┐
│ USER: Runs commands                                         │
│ whoami, ls, pwd, etc.                                       │
│ ✅ CloudWatch: Logs appear immediately                      │
│ ⏳ S3: Logs batched (not uploaded yet)                      │
└─────────────────────────────────────────────────────────────┘
                           ↓
┌─────────────────────────────────────────────────────────────┐
│ Timer Expires (3 minutes)                                   │
│ ✅ Enforcer deletes IAM policy                              │
│ ⏳ IAM propagation starts (5-60 sec)                        │
└─────────────────────────────────────────────────────────────┘
                           ↓
┌─────────────────────────────────────────────────────────────┐
│ Enforcer Round 1                                            │
│ ✅ Terminates active sessions                               │
│ ⏳ Wait 20 seconds                                          │
└─────────────────────────────────────────────────────────────┘
                           ↓
┌─────────────────────────────────────────────────────────────┐
│ User Tries to Reconnect                                     │
│ ⚠️ May succeed (IAM not propagated)                         │
│ ✅ Session terminated within 20 sec                         │
└─────────────────────────────────────────────────────────────┘
                           ↓
┌─────────────────────────────────────────────────────────────┐
│ Enforcer Round 2 (T+20s)                                    │
│ ✅ Terminates any new sessions                              │
│ ⏳ Wait 20 seconds                                          │
└─────────────────────────────────────────────────────────────┘
                           ↓
┌─────────────────────────────────────────────────────────────┐
│ Enforcer Round 3 (T+40s)                                    │
│ ✅ Final termination sweep                                  │
│ ✅ IAM fully propagated                                     │
└─────────────────────────────────────────────────────────────┘
                           ↓
┌─────────────────────────────────────────────────────────────┐
│ User Tries to Reconnect Again                               │
│ ❌ AccessDeniedException                                    │
│ ✅ Policy deleted and propagated                            │
└─────────────────────────────────────────────────────────────┘
                           ↓
┌─────────────────────────────────────────────────────────────┐
│ Session Ends                                                │
│ ✅ CloudWatch: Full log available                           │
│ ⏳ S3: Uploading batch (5-15 min)                           │
└─────────────────────────────────────────────────────────────┘
                           ↓ (5-15 minutes later)
┌─────────────────────────────────────────────────────────────┐
│ S3 Log File Created                                         │
│ ✅ s3://...sessions/USERNAME-{session-id}.log               │
└─────────────────────────────────────────────────────────────┘
```

---

## 📋 Expected Behavior Summary

### Normal Scenarios

#### Scenario 1: User Completes Work Before Timer
```
1. Create 30-min access ✅
2. User connects ✅
3. User works for 20 minutes ✅
4. User exits ✅
5. Check logs:
   - CloudWatch: ✅ Immediate
   - S3: ⏳ Wait 5-15 minutes ✅
```

#### Scenario 2: Timer Expires While User Working
```
1. Create 3-min access ✅
2. User connects ✅
3. User working... ✅
4. Timer expires → Session terminated ✅
5. User sees: "Connection closed" ✅
6. User tries to reconnect → May work 1-2 times ⚠️
7. After 30-60 sec → AccessDenied ✅
8. Check logs:
   - CloudWatch: ✅ Immediate
   - S3: ⏳ Wait 5-15 minutes ✅
```

#### Scenario 3: Very Short Duration (Testing)
```
1. Create 1-min access ✅
2. User connects ✅
3. Run quick commands ✅
4. Timer expires quickly → Terminated ✅
5. Try reconnect → AccessDenied after 30-60 sec ✅
6. Check logs:
   - CloudWatch: ✅ Available now
   - S3: ⏳ Wait 10-15 minutes (very short sessions upload slower)
```

---

## 🔧 Improvements in v1.0.5

### Before (v1.0.4)
```bash
# Single-pass enforcement
Timer expires → Delete policy → Terminate once → Done
```
**Problem:** User could reconnect during IAM propagation

### After (v1.0.5)
```bash
# Triple-pass enforcement
Timer expires → Delete policy
             → Terminate (Round 1)
             → Wait 20 sec
             → Terminate (Round 2)
             → Wait 20 sec
             → Terminate (Round 3)
```
**Improvement:** Catches reconnection attempts during IAM propagation

---

## 💡 Best Practices

### For Admins

1. **Set Appropriate Durations**
   ```bash
   # Too short (causes confusion)
   -d 1  # 1 minute - user barely connects before timeout

   # Good for testing
   -d 5  # 5 minutes - enough to verify logs

   # Good for work
   -d 240  # 4 hours - full work session
   ```

2. **Explain Timing to Users**
   ```
   "Access expires in 4 hours. You'll get disconnected when time is up.
    You might be able to reconnect once, but you'll be kicked off again
    within 30 seconds. That's normal - it means your access truly expired."
   ```

3. **Check Logs After Sufficient Time**
   ```bash
   # Wrong (too soon)
   Session ends → Check S3 immediately → No logs found ❌

   # Right (wait for upload)
   Session ends → Wait 15 minutes → Check S3 → Logs found ✅

   # Or use CloudWatch for immediate logs
   Session ends → Check CloudWatch → Logs available ✅
   ```

### For Users

1. **Expect Disconnection at Timer**
   - Normal to get disconnected when timer expires
   - Normal to see "Connection closed"
   - Don't panic - check with admin if needed more time

2. **Don't Fight AccessDenied**
   - If you get AccessDenied, your time expired
   - Ask admin to renew access
   - Takes 10 seconds to renew

3. **Your Commands Are Logged**
   - Every command is logged to S3 and CloudWatch
   - Admins can see what you did
   - Be professional in your commands and comments

---

## 🎯 Quick Troubleshooting

### "No S3 logs found"
```bash
# 1. Check how long ago session ended
aws ssm describe-sessions --state History | grep USERNAME

# 2. If < 15 minutes ago → Wait longer

# 3. If > 15 minutes → Check CloudWatch instead
aws logs tail /aws/ssm/onetime-sessions-dev --filter-pattern "USERNAME"

# 4. If CloudWatch also empty → Session didn't use correct document
#    (This shouldn't happen with v1.0.5)
```

### "User still connecting after expiry"
```bash
# 1. Check if policy exists
aws iam list-user-policies --user-name USERNAME

# 2. If empty → IAM propagation delay (wait 60 seconds)

# 3. Check enforcer log
cat /tmp/jit-admin-session.USERNAME.log

# 4. Wait 60-90 seconds total, user will get AccessDenied
```

### "Session not terminated"
```bash
# 1. List active sessions
aws ssm describe-sessions --state Active --filters "key=Owner,value=USERNAME"

# 2. Manually terminate if needed
aws ssm terminate-session --session-id SESSION_ID

# 3. Check enforcer is running
ps aux | grep jit-admin-session
```

---

## 📞 Support

**For log-related issues:**
1. Run: `./check-session-logs.sh USERNAME`
2. Wait 15 minutes for S3 logs
3. Check CloudWatch for immediate logs

**For timing/access issues:**
1. Normal: 30-90 second delay for full AccessDenied
2. Check: `cat /tmp/jit-admin-session.USERNAME.log`
3. Wait: IAM propagation is AWS behavior, not a bug

**Script Version:** jit-admin-session-v1.0.5
**Last Updated:** November 16, 2025
