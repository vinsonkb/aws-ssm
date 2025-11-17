# jit-admin-session Quick Reference Card

**One-page cheat sheet for common operations**

---

## 🚀 Most Common Commands

### 1️⃣ Create New Developer Access (Most Common)
```bash
./jit-admin-session-v1.0.5 \
  -u john-dev \
  -i i-0ee0bc84a481f7852 \
  -d 240 \
  --new-user \
  --create-keys \
  --output-script setup-john-dev.sh
```
**Sends:** `setup-john-dev.sh` to user
**Result:** User runs script, gets 4-hour access

---

### 2️⃣ Renew Existing User (Second Most Common)
```bash
./jit-admin-session-v1.0.5 \
  -u john-dev \
  -i i-0ee0bc84a481f7852 \
  -d 240 \
  --purge-existing
```
**Result:** Extends access for another 4 hours

---

### 3️⃣ Emergency Quick Access
```bash
./jit-admin-session-v1.0.5 \
  -u oncall-sarah \
  -i i-0prod123456789 \
  -d 120 \
  --new-user \
  --create-keys \
  --configure-profile oncall-sarah
```
**Result:** 2-hour access, ready to connect immediately

---

### 4️⃣ Revoke Access NOW
```bash
./jit-admin-session-v1.0.5 --purge-session john-dev
```
**Result:** Terminates sessions, deletes policies & keys

---

### 5️⃣ Contractor with Tag Restriction
```bash
./jit-admin-session-v1.0.5 \
  -u vendor-alice \
  -i i-0staging123456 \
  -d 240 \
  --new-user \
  --create-keys \
  --output-script setup-vendor-alice.sh \
  --require-tag Environment=Staging
```
**Result:** Can ONLY access staging instances (tag-enforced)

---

## 📊 Common Durations

| Duration | Minutes | Use Case |
|----------|---------|----------|
| **30 min** | `-d 30` | Quick check/test |
| **1 hour** | `-d 60` | Debug session |
| **2 hours** | `-d 120` | Emergency fix |
| **4 hours** | `-d 240` | Development work |
| **8 hours** | `-d 480` | Full workday |

---

## 🔧 Command Options Reference

### Required
```bash
-u USERNAME      # IAM username
-i INSTANCE_ID   # EC2 instance (i-xxxxx)
-d MINUTES       # Duration (1-240)
```

### Common Options
```bash
--new-user                  # Create IAM user
--create-keys              # Generate AWS keys
--output-script FILE       # Generate all-in-one script
--configure-profile NAME   # Setup local AWS profile
--purge-existing           # Delete old policies first
--require-tag KEY=VALUE    # Tag restriction
-r REGION                  # AWS region (default: ap-southeast-1)
```

### Special Modes
```bash
--purge-session USER       # Cleanup: delete policies, sessions, keys
--local-admin-profile NAME # Use specific AWS profile for admin
-h, --help                 # Show help
```

---

## 👤 User Workflow

### Admin Side
```bash
# 1. Create access
./jit-admin-session-v1.0.5 -u USER -i INSTANCE -d 240 \
  --new-user --create-keys --output-script setup-USER.sh

# 2. Send script to user
# Email: setup-USER.sh

# 3. (Later) Revoke when done
./jit-admin-session-v1.0.5 --purge-session USER
```

### User Side
```bash
# 1. Receive setup-USER.sh

# 2. Run it
bash setup-USER.sh

# 3. Auto-connects!

# 4. To reconnect later
bash setup-USER.sh
```

---

## 🔍 Checking Status

### List Active Users
```bash
aws ssm describe-sessions --state Active --region ap-southeast-1
```

### Check User's Policies
```bash
aws iam list-user-policies --user-name USERNAME
```

### View Session Logs
```bash
# S3
aws s3 ls s3://ssm-onetime-logs-vortech-dev/sessions/ | grep USERNAME

# CloudWatch
aws logs tail /aws/ssm/onetime-sessions-dev --follow --filter-pattern "USERNAME"
```

---

## 🎯 Decision Tree

```
What do you need?
├─ New user? → Use: --new-user --create-keys --output-script
├─ Renew user? → Use: --purge-existing
├─ Revoke access? → Use: --purge-session
├─ Contractor? → Add: --require-tag Environment=Staging
└─ Emergency? → Use: --configure-profile (skip --output-script)
```

---

## 📋 User Connection Command

After creating user, they connect with:

```bash
aws ssm start-session \
  --target i-INSTANCE_ID \
  --document-name SSM-SessionManagerRunShell \
  --region ap-southeast-1 \
  --profile USERNAME
```

**⚠️ Important:** Must include `--document-name SSM-SessionManagerRunShell`

---

## 🚨 Common Errors & Fixes

### Error: AccessDeniedException
**Fix:** Renew access or check document name
```bash
./jit-admin-session-v1.0.5 -u USER -i INSTANCE -d 240 --purge-existing
```

### Error: User already exists
**Fix:** Remove `--new-user` flag
```bash
./jit-admin-session-v1.0.5 -u USER -i INSTANCE -d 240 --purge-existing
```

### Error: Instance not online
**Fix:** Start SSM agent on instance
```bash
# On instance:
sudo systemctl start amazon-ssm-agent
```

### Error: No such file or directory
**Fix:** Use full path or cd to directory
```bash
cd /Users/vinson/Documents/0_Other_Services/SSM/jit-admin
./jit-admin-session-v1.0.5 ...
```

---

## 🔐 Security Checklist

- ✅ Use shortest duration needed
- ✅ Use `--require-tag` for contractors
- ✅ Revoke access immediately when done
- ✅ Never share AWS access keys
- ✅ Review logs weekly
- ✅ Set up CloudWatch alarms for failed access

---

## 📁 File Locations

```
/Users/vinson/Documents/0_Other_Services/SSM/
├── jit-admin/
│   └── jit-admin-session-v1.0.5          # Main script
├── Guide/
│   ├── JIT-ADMIN-COMPLETE-GUIDE.md       # Full guide with examples
│   └── QUICK-REFERENCE.md                # This file
├── SETUP_GUIDE.md                         # Initial setup
├── HOW_TO_SEE_LOGS.md                     # Logging guide
└── TEST_RESULTS.md                        # Validation results
```

---

## 💡 Pro Tips

1. **Always purge before renewal** → Cleaner, fewer orphaned policies
2. **Tag your instances** → Better access control
3. **Use descriptive usernames** → `john-dev` not `user1`
4. **Generate scripts for reusability** → `--output-script`
5. **Set up alerts** → Know when access is used
6. **Review logs regularly** → S3 bucket fills up
7. **Document access reasons** → Audit trail

---

## 📞 Need More Help?

- **Full Guide:** [JIT-ADMIN-COMPLETE-GUIDE.md](JIT-ADMIN-COMPLETE-GUIDE.md)
- **Built-in Help:** `./jit-admin-session-v1.0.5 --help`
- **Test Logs:** [../TEST_RESULTS.md](../TEST_RESULTS.md)

---

**Quick Reference v1.0** | Last Updated: November 15, 2025
