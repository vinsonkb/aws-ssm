#!/usr/bin/env bash
set -euo pipefail
#
# ssm-requester.sh — Simple client for USERS (not admins)
# - Lists SSM-online instances you can reach
# - Starts an SSM session once your admin has granted access
# - Can wait/retry until the grant becomes active (--wait N seconds)
#
# Requirements: AWS CLI v2, jq
# Default region: ap-southeast-1
#
# Examples:
#   ./ssm-requester.sh                          # interactive list + connect
#   ./ssm-requester.sh -i i-0123456789abcdef0   # connect directly
#   ./ssm-requester.sh -p vinson-04 --wait 300  # wait up to 5m for admin grant
#   ./ssm-requester.sh --list                   # only list reachable instances
#

REGION="${REGION:-ap-southeast-1}"
PROFILE="${PROFILE:-}"
INSTANCE_ID=""
LIST_ONLY=0
WAIT_SECS=0
QUIET=0

usage() {
  cat <<'EOS'
Usage:
  ssm-requester.sh [-r REGION] [-p PROFILE] [-i INSTANCE_ID] [--list] [--wait SECONDS] [-q]

Options:
  -r, --region REGION       AWS region (default: ap-southeast-1)
  -p, --profile PROFILE     AWS CLI profile to use (your own user)
  -i, --instance-id ID      Connect to this instance directly
  --list                    Only list SSM-online instances you can target
  --wait SECONDS            Retry start-session until success or timeout
  -q, --quiet               Less verbose output
  -h, --help                Show this help

Notes:
- You must already have access granted by an admin (temporary SSM permission).
- If access was just granted, it can take a few seconds to propagate; use --wait.
EOS
  exit 0
}

say()  { [[ $QUIET -eq 1 ]] || printf '%b\n' "$*"; }
ok()   { say "✅  $*"; }
warn() { say "⚠️  $*"; }
err()  { printf '❌  %b\n' "$*" >&2; }

has() { command -v "$1" >/dev/null 2>&1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    -r|--region) REGION="$2"; shift 2;;
    -p|--profile) PROFILE="$2"; shift 2;;
    -i|--instance-id) INSTANCE_ID="$2"; shift 2;;
    --list) LIST_ONLY=1; shift;;
    --wait) WAIT_SECS="$2"; shift 2;;
    -q|--quiet) QUIET=1; shift;;
    -h|--help) usage ;;
    *) err "Unknown arg: $1"; usage ;;
  esac
done

# Preconditions
if ! has aws; then err "AWS CLI v2 not found. Install and try again."; exit 1; fi
if ! has jq; then err "jq not found. Install and try again."; exit 1; fi

AWS=(aws --region "$REGION")
[[ -n "$PROFILE" ]] && AWS+=(--profile "$PROFILE")

# Confirm identity
say "🔎 Checking caller identity..."
if ! ID_JSON="$("${AWS[@]}" sts get-caller-identity 2>/dev/null)"; then
  err "AWS credentials not configured or invalid. Run: aws configure"
  exit 1
fi
ARN=$(jq -r '.Arn' <<<"$ID_JSON")
ok "Using identity: $ARN"

# Helper: list SSM-online instances visible to the account
list_instances() {
  say ""
  say "Fetching SSM-online instances in $REGION ..."
  # Query SSM managed instances that are Online
  # Join with EC2 to show Name + Private IP (best-effort)
  SSM_IDS=$("${AWS[@]}" ssm describe-instance-information \
    --filter "Key=PingStatus,Values=Online" \
    --query "InstanceInformationList[].InstanceId" --output text 2>/dev/null | tr '\t' '\n' | sed '/^$/d' || true)

  if [[ -z "$SSM_IDS" ]]; then
    warn "No SSM-online instances found (or you lack permission to list)."
    return
  fi

  # Build a filter list for EC2 describe-instances
  MAPFILE_A=()
  while read -r iid; do
    [[ -n "$iid" ]] && MAPFILE_A+=("Name=instance-id,Values=$iid")
  done <<<"$SSM_IDS"

  if [[ ${#MAPFILE_A[@]} -gt 0 ]]; then
    EC2_JSON=$("${AWS[@]}" ec2 describe-instances --filters "${MAPFILE_A[@]}" --output json 2>/dev/null || echo '{}')
  else
    EC2_JSON='{}'
  fi

  say ""
  printf " %-3s %-20s %-35s %-15s\n" "#" "INSTANCE ID" "NAME" "PRIVATE IP"
  printf -- "--------------------------------------------------------------------------------\n"

  # Build a table
  idx=1
  for iid in $SSM_IDS; do
    name=$(jq -r --arg iid "$iid" '
      (.Reservations[]?.Instances[]? // empty)
      | select(.InstanceId==$iid)
      | (.Tags // [])
      | map(select(.Key=="Name"))[0].Value // "-" ' <<<"$EC2_JSON")
    pip=$(jq -r --arg iid "$iid" '
      (.Reservations[]?.Instances[]? // empty)
      | select(.InstanceId==$iid)
      | .PrivateIpAddress // "-" ' <<<"$EC2_JSON")
    printf " %-3s %-20s %-35s %-15s\n" "$idx" "$iid" "$name" "$pip"
    ((idx++))
  done
  say ""
}

# If only listing
if [[ $LIST_ONLY -eq 1 ]]; then
  list_instances
  exit 0
fi

# If no instance specified, list and prompt
if [[ -z "$INSTANCE_ID" ]]; then
  list_instances
  read -rp "Select instance # or paste instance-id: " CHOICE

  # If looks like an instance-id, use directly
  if [[ "$CHOICE" =~ ^i-[a-z0-9]+$ ]]; then
    INSTANCE_ID="$CHOICE"
  else
    # Pick by row number
    if ! [[ "$CHOICE" =~ ^[0-9]+$ ]]; then
      err "Invalid selection."
      exit 1
    fi
    # Re-create SSM_IDS list to index by number
    SSM_IDS=$("${AWS[@]}" ssm describe-instance-information \
      --filter "Key=PingStatus,Values=Online" \
      --query "InstanceInformationList[].InstanceId" --output text 2>/dev/null | tr '\t' '\n' | sed '/^$/d' || true)
    INSTANCE_ID=$(echo "$SSM_IDS" | sed -n "${CHOICE}p" || true)
    if [[ -z "$INSTANCE_ID" ]]; then
      err "Invalid selection."
      exit 1
    fi
  fi
fi

say ""
say "🎯 Target: $INSTANCE_ID"
say "🗺️  Region: $REGION"
[[ -n "$PROFILE" ]] && say "👤 Profile: $PROFILE"

# Helper: attempt to start session once; return status message
try_start() {
  set +e
  OUT=$("${AWS[@]}" ssm start-session --target "$INSTANCE_ID" 2>&1)
  RC=$?
  set -e

  if [[ $RC -eq 0 ]]; then
    # Session established; control transfers to SSM plugin so we won't reach here
    return 0
  fi

  # Classify common errors
  if grep -q "TargetNotConnected" <<<"$OUT"; then
    err "Instance is not connected to SSM (TargetNotConnected). Ensure SSM Agent is running and IAM role attached."
  elif grep -q "AccessDeniedException" <<<"$OUT" || grep -q "UnauthorizedRequest" <<<"$OUT"; then
    warn "Access denied. Your admin may not have granted StartSession yet, or it hasn't propagated."
    warn "Error: $(echo "$OUT" | tail -n1)"
    return 2
  elif grep -qi "The config profile .* could not be found" <<<"$OUT"; then
    err "AWS CLI profile not found. Use -p PROFILE or configure your credentials."
  else
    err "StartSession failed. Output:"
    echo "$OUT" >&2
  fi
  return 1
}

# Optional wait loop until permissions are active
if (( WAIT_SECS > 0 )); then
  say ""
  say "⏳ Waiting up to $WAIT_SECS seconds for admin grant to become active..."
  until try_start; do
    code=$?
    # 2 = AccessDenied-ish; retry; 1 = other error -> bail unless still have time
    if (( code == 2 )); then
      (( WAIT_SECS -= 5 ))
      if (( WAIT_SECS <= 0 )); then
        err "Timed out waiting for access. Ask your admin to (re)grant StartSession."
        exit 2
      fi
      sleep 5
      say " … still waiting for permission propagation …"
    else
      # If not access denied, bail immediately
      exit 1
    fi
  done
else
  # Single attempt
  try_start || exit $?
fi

# If we got here with RC 0, the SSM plugin should take over the terminal.
# When the session ends, we can print a friendly message.
say ""
ok "Session ended."
exit 0
