#!/usr/bin/env bash
set -euo pipefail

# prepare-jit-env.sh
# One-shot preparer for JIT SSM requesters.
# - Installs/validates: AWS CLI v2, jq, bash >=5
# - Verifies AWS credentials & basic IAM capabilities
# - Optionally checks SSM instance online
# - Optionally checks Lambda backend presence (create/track/terminate/cleanup)
#
# Usage:
#   ./prepare-jit-env.sh [-r REGION] [-i INSTANCE_ID] [--check-backend] [--install-only]
#
# Examples:
#   ./prepare-jit-env.sh -r ap-southeast-1
#   ./prepare-jit-env.sh -r ap-southeast-1 -i i-0ee0bc84a481f7852 --check-backend
#
# Notes:
# - macOS requires Homebrew for auto-install. If missing, you'll get a hint.
# - Linux install path for AWS CLI v2: /usr/local/aws-cli
#
REGION="${REGION:-ap-southeast-1}"
INSTANCE_ID=""
CHECK_BACKEND=0
INSTALL_ONLY=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    -r|--region) REGION="$2"; shift 2;;
    -i|--instance-id) INSTANCE_ID="$2"; shift 2;;
    --check-backend) CHECK_BACKEND=1; shift;;
    --install-only) INSTALL_ONLY=1; shift;;
    -h|--help)
      sed -n '1,60p' "$0"
      exit 0
      ;;
    *) echo "Unknown arg: $1" >&2; exit 1;;
  esac
done

say()  { printf '%b\n' "$*"; }
ok()   { say "✅  $*"; }
warn() { say "⚠️  $*"; }
err()  { say "❌  $*" >&2; }

need_root_linux() {
  if [[ "$(uname -s)" != "Darwin" ]] && [[ $EUID -ne 0 ]]; then
    warn "Some installs need sudo. Re-run with sudo if prompted fails."
  fi
}

platform_id() {
  if [[ "$OSTYPE" == "darwin"* ]]; then echo "macos"; return; fi
  if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    echo "${ID:-linux}"
  else
    echo "linux"
  fi
}

has_cmd() { command -v "$1" >/dev/null 2>&1; }

install_jq() {
  if has_cmd jq; then ok "jq present: $(jq --version)"; return; fi
  case "$(platform_id)" in
    macos)
      if has_cmd brew; then
        say "Installing jq via Homebrew..."
        brew install jq
      else
        err "Homebrew not found. Install from https://brew.sh then re-run."; exit 1
      fi
      ;;
    ubuntu|debian)
      need_root_linux
      sudo apt-get update -y && sudo apt-get install -y jq
      ;;
    amzn|amazon|rhel|centos|rocky|alma|ol)
      need_root_linux
      if has_cmd dnf; then sudo dnf install -y jq; else sudo yum install -y jq; fi
      ;;
    *)
      err "Unsupported distro for automatic jq install. Install jq manually."; exit 1;;
  esac
  ok "jq installed: $(jq --version)"
}

install_bash5() {
  local v="${BASH_VERSION%%.*}"
  if [[ -n "${BASH_VERSION:-}" && "$v" -ge 5 ]]; then
    ok "bash version OK: $BASH_VERSION"
    return
  fi
  warn "bash < 5 detected (${BASH_VERSION:-unknown}). Attempting upgrade..."
  case "$(platform_id)" in
    macos)
      if has_cmd brew; then
        brew install bash
        ok "Installed Homebrew bash. To use it by default: sudo chsh -s /opt/homebrew/bin/bash \"$USER\""
      else
        err "Homebrew not found. Install from https://brew.sh then re-run."; exit 1
      fi
      ;;
    ubuntu|debian)
      need_root_linux
      sudo apt-get update -y && sudo apt-get install -y bash
      ;;
    amzn|amazon|rhel|centos|rocky|alma|ol)
      need_root_linux
      if has_cmd dnf; then sudo dnf install -y bash; else sudo yum install -y bash; fi
      ;;
    *)
      warn "Could not auto-upgrade bash. Please install bash >=5 manually."
      ;;
  esac
  ok "bash now: $(bash -c 'echo $BASH_VERSION' 2>/dev/null || echo unknown)"
}

install_awscli_v2() {
  if has_cmd aws; then
    local v; v=$(aws --version 2>&1 || true)
    ok "AWS CLI present: $v"
    return
  fi
  say "Installing AWS CLI v2 ..."
  case "$(platform_id)" in
    macos)
      if has_cmd brew; then
        brew install awscli
      else
        err "Homebrew not found. Install from https://brew.sh then re-run."; exit 1
      fi
      ;;
    ubuntu|debian|amzn|amazon|rhel|centos|rocky|alma|ol|linux)
      need_root_linux
      tmp="$(mktemp -d)"
      pushd "$tmp" >/dev/null
      curl -sSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o awscliv2.zip
      unzip -q awscliv2.zip
      sudo ./aws/install
      popd >/dev/null
      rm -rf "$tmp"
      ;;
    *)
      err "Unsupported platform for automatic AWS CLI install."; exit 1;;
  esac
  ok "AWS CLI installed: $(aws --version 2>&1)"
}

check_aws_creds() {
  say "Checking AWS credentials..."
  if ! aws --version >/dev/null 2>&1; then err "AWS CLI not found"; exit 1; fi
  if aws sts get-caller-identity --region "$REGION" >/dev/null 2>&1; then
    local acct arn
    acct=$(aws sts get-caller-identity --query Account --output text --region "$REGION")
    arn=$(aws sts get-caller-identity --query Arn --output text --region "$REGION")
    ok "Using identity: $arn (acct $acct)"
  else
    err "AWS credentials not configured. Run: aws configure"; exit 1
  fi
}

check_min_permissions() {
  say "Validating minimal IAM capabilities for requester..."
  local okcount=0
  if aws iam get-user >/dev/null 2>&1; then ((okcount++)); fi
  if aws ec2 describe-instances --max-items 1 --region "$REGION" >/dev/null 2>&1; then ((okcount++)); fi
  if aws ssm describe-instance-information --max-results 1 --region "$REGION" >/dev/null 2>&1; then ((okcount++)); fi
  if aws lambda list-functions --max-items 1 --region "$REGION" >/dev/null 2>&1; then ((okcount++)); fi
  if (( okcount >= 3 )); then
    ok "Requester has sufficient read privileges for JIT flow."
  else
    warn "Requester appears to have limited IAM read privileges. JIT may still work if admin runs grants."
  fi
}

check_instance_online() {
  [[ -z "$INSTANCE_ID" ]] && return 0
  say "Checking SSM PingStatus for $INSTANCE_ID in $REGION ..."
  local out
  out=$(aws ssm describe-instance-information \
    --query "InstanceInformationList[?InstanceId=='$INSTANCE_ID'].[InstanceId,PingStatus,PlatformName,PlatformVersion]" \
    --output text --region "$REGION" || true)
  if [[ -z "$out" ]]; then
    err "Instance not found in SSM inventory, or no permission."
    return 1
  fi
  say "$out"
  if grep -q "Online" <<<"$out"; then
    ok "Instance is Online in SSM."
  else
    warn "Instance is not Online. Ensure SSM Agent + IAM role are set."
  fi
}

check_backend() {
  (( CHECK_BACKEND == 1 )) || return 0
  say "Checking Lambda backend (create/track/terminate/cleanup) in $REGION ..."
  local miss=0
  for fn in create_onetime_session track_onetime_session terminate_session cleanup_onetime_session; do
    if aws lambda get-function --function-name "$fn" --region "$REGION" >/dev/null 2>&1; then
      ok "Lambda present: $fn"
    else
      warn "Lambda missing: $fn"
      ((miss++))
    fi
  done
  if (( miss > 0 )); then
    warn "Backend incomplete. You can still use admin-only script grants (jit-admin-session)."
  else
    ok "Backend complete."
  fi
}

main() {
  say "=== Preparing JIT SSM requester environment ==="
  install_jq
  install_bash5
  install_awscli_v2
  check_aws_creds
  check_min_permissions

  if (( INSTALL_ONLY == 1 )); then
    ok "Install-only mode completed."; exit 0
  fi

  check_instance_online
  check_backend

  say ""
  ok "Environment ready."
  say "Region: $REGION"
  [[ -n "$INSTANCE_ID" ]] && say "Instance: $INSTANCE_ID"
  say ""
  say "Next steps:"
  say "  • If you're an admin: run ./jit-admin-session to grant time-bound access"
  say "  • If you're a requester: use aws ssm start-session once admin grants you access"
}

main "$@"
