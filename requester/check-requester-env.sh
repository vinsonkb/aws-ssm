#!/usr/bin/env bash
set -euo pipefail
#
# check-requester-env.sh
# For requesters (not admins)
# Ensures they have AWS CLI v2, jq, and correct credentials before running SSM session
#
# Usage:
#   ./check-requester-env.sh [-p PROFILE] [-r REGION]
#   ./check-requester-env.sh --help
#

REGION="ap-southeast-1"
PROFILE=""
QUIET=0

usage() {
  echo "Usage: $0 [-p PROFILE] [-r REGION]"
  echo "Checks AWS CLI, jq, credentials, and SSM connectivity."
  echo
  echo "Example:"
  echo "  ./check-requester-env.sh -p vinson-04 -r ap-southeast-1"
  exit 0
}

say() { [[ $QUIET -eq 1 ]] || echo "$*"; }
ok()  { say "✅ $*"; }
err() { echo "❌ $*" >&2; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    -p|--profile) PROFILE="$2"; shift 2;;
    -r|--region) REGION="$2"; shift 2;;
    -q|--quiet) QUIET=1; shift;;
    -h|--help) usage;;
    *) err "Unknown arg: $1"; usage;;
  esac
done

has() { command -v "$1" >/dev/null 2>&1; }

# ---- Check tools ----
say "🔍 Checking required tools..."
if has aws; then
  ok "AWS CLI found: $(aws --version 2>&1 | head -n1)"
else
  err "AWS CLI not found. Install AWS CLI v2 from https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"
  exit 1
fi

if has jq; then
  ok "jq found: $(jq --version)"
else
  err "jq not found. Install it (brew install jq or apt/yum install jq)"
  exit 1
fi

# ---- Verify AWS credentials ----
say ""
say "🔐 Checking AWS credentials..."
AWS=(aws --region "$REGION")
[[ -n "$PROFILE" ]] && AWS+=(--profile "$PROFILE")

if ! ID_JSON=$("${AWS[@]}" sts get-caller-identity 2>/dev/null); then
  err "AWS credentials not configured or invalid. Run: aws configure --profile ${PROFILE:-default}"
  exit 1
fi
ARN=$(jq -r '.Arn' <<<"$ID_JSON")
ok "Authenticated as: $ARN"

# ---- Verify SSM access ----
say ""
say "🧠 Checking SSM permissions..."
if ! "${AWS[@]}" ssm describe-instance-information --max-results 1 >/dev/null 2>&1; then
  err "Cannot call ssm:DescribeInstanceInformation. You may not have SSM permissions yet."
  echo "Ask your admin to grant you a one-time session via JIT Admin Session."
  exit 1
fi
ok "You can reach AWS Systems Manager."

# ---- Final guidance ----
say ""
ok "Environment ready ✅"
say "You can now connect using:"
say "  aws ssm start-session --target i-xxxxxxxxxxxxxxxxx --region ${REGION} --profile ${PROFILE:-your-profile}"
say ""
say "Tip: If you just received access, wait ~30s for permissions to propagate."
