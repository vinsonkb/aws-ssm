#!/usr/bin/env bash
set -euo pipefail
#
# install-requester-tools.sh
# Installs AWS CLI v2 and jq (for macOS or Linux)
#
# Usage:
#   curl -sSL https://yourdomain.com/install-requester-tools.sh | bash
#

echo "🚀 Installing prerequisites for AWS SSM requester..."
echo "-----------------------------------------------"

# Detect platform
if [[ "$OSTYPE" == "darwin"* ]]; then
  PLATFORM="macos"
elif [[ -f /etc/os-release ]]; then
  . /etc/os-release
  PLATFORM="$ID"
else
  PLATFORM="linux"
fi

# --- Install jq ---
echo "🔧 Installing jq..."
if command -v jq >/dev/null 2>&1; then
  echo "✅ jq already installed: $(jq --version)"
else
  case "$PLATFORM" in
    macos)
      if command -v brew >/dev/null 2>&1; then
        brew install jq
      else
        echo "❌ Homebrew not found. Install from https://brew.sh first."
        exit 1
      fi
      ;;
    ubuntu|debian)
      sudo apt-get update -y && sudo apt-get install -y jq
      ;;
    amzn|amazon|rhel|centos|rocky|alma|ol)
      if command -v dnf >/dev/null 2>&1; then
        sudo dnf install -y jq
      else
        sudo yum install -y jq
      fi
      ;;
    *)
      echo "⚠️ Unsupported OS for jq auto-install. Please install jq manually."
      ;;
  esac
fi

# --- Install AWS CLI v2 ---
echo ""
echo "🔧 Installing AWS CLI v2..."
if command -v aws >/dev/null 2>&1; then
  echo "✅ AWS CLI already installed: $(aws --version 2>&1)"
else
  case "$PLATFORM" in
    macos)
      if command -v brew >/dev/null 2>&1; then
        brew install awscli
      else
        echo "❌ Homebrew not found. Install from https://brew.sh first."
        exit 1
      fi
      ;;
    ubuntu|debian|amzn|amazon|rhel|centos|rocky|alma|ol|linux)
      tmpdir=$(mktemp -d)
      cd "$tmpdir"
      curl -sSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o awscliv2.zip
      unzip -q awscliv2.zip
      sudo ./aws/install
      cd -
      rm -rf "$tmpdir"
      ;;
    *)
      echo "⚠️ Unsupported OS for AWS CLI auto-install. Please install manually."
      ;;
  esac
fi

echo ""
echo "✅ Installation completed!"
echo "Run: aws --version && jq --version"
echo "-----------------------------------------------"
