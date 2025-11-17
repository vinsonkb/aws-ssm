#!/usr/bin/env bash
set -euo pipefail
#
# install-requester-tools-v1.0.1.sh
# Installs AWS CLI v2, jq, and Session Manager plugin (for macOS or Linux)
#
# Usage:
#   curl -sSL https://yourdomain.com/install-requester-tools-v1.0.1.sh | bash
#
# v1.0.1: Added Session Manager plugin installation
#

echo "🚀 Installing prerequisites for AWS SSM requester..."
echo "-----------------------------------------------"

# Detect platform
if [[ "$OSTYPE" == "darwin"* ]]; then
  PLATFORM="macos"
  # Detect Mac architecture
  if [[ "$(uname -m)" == "arm64" ]]; then
    ARCH="arm64"
  else
    ARCH="x86_64"
  fi
elif [[ -f /etc/os-release ]]; then
  . /etc/os-release
  PLATFORM="$ID"
  ARCH="$(uname -m)"
else
  PLATFORM="linux"
  ARCH="$(uname -m)"
fi

echo "ℹ️  Detected: $PLATFORM ($ARCH)"
echo ""

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
      if [[ "$ARCH" == "aarch64" ]] || [[ "$ARCH" == "arm64" ]]; then
        curl -sSL "https://awscli.amazonaws.com/awscli-exe-linux-aarch64.zip" -o awscliv2.zip
      else
        curl -sSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o awscliv2.zip
      fi
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

# --- Install Session Manager Plugin ---
echo ""
echo "🔧 Installing Session Manager plugin..."
if command -v session-manager-plugin >/dev/null 2>&1; then
  echo "✅ Session Manager plugin already installed"
  session-manager-plugin --version 2>&1 || echo "(version info not available)"
else
  case "$PLATFORM" in
    macos)
      if command -v brew >/dev/null 2>&1; then
        echo "Installing via Homebrew..."
        brew install --cask session-manager-plugin
      else
        echo "Installing via pkg file..."
        tmpdir=$(mktemp -d)
        cd "$tmpdir"
        if [[ "$ARCH" == "arm64" ]]; then
          curl -sSL "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/mac_arm64/session-manager-plugin.pkg" -o session-manager-plugin.pkg
        else
          curl -sSL "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/mac/session-manager-plugin.pkg" -o session-manager-plugin.pkg
        fi
        sudo installer -pkg session-manager-plugin.pkg -target /
        cd -
        rm -rf "$tmpdir"
      fi
      ;;
    ubuntu|debian)
      tmpdir=$(mktemp -d)
      cd "$tmpdir"
      if [[ "$ARCH" == "aarch64" ]] || [[ "$ARCH" == "arm64" ]]; then
        curl -sSL "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/ubuntu_arm64/session-manager-plugin.deb" -o session-manager-plugin.deb
      else
        curl -sSL "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/ubuntu_64bit/session-manager-plugin.deb" -o session-manager-plugin.deb
      fi
      sudo dpkg -i session-manager-plugin.deb
      cd -
      rm -rf "$tmpdir"
      ;;
    amzn|amazon|rhel|centos|rocky|alma|ol)
      tmpdir=$(mktemp -d)
      cd "$tmpdir"
      if [[ "$ARCH" == "aarch64" ]] || [[ "$ARCH" == "arm64" ]]; then
        curl -sSL "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/linux_arm64/session-manager-plugin.rpm" -o session-manager-plugin.rpm
      else
        curl -sSL "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/linux_64bit/session-manager-plugin.rpm" -o session-manager-plugin.rpm
      fi
      if command -v dnf >/dev/null 2>&1; then
        sudo dnf install -y session-manager-plugin.rpm
      else
        sudo yum install -y session-manager-plugin.rpm
      fi
      cd -
      rm -rf "$tmpdir"
      ;;
    *)
      echo "⚠️ Unsupported OS for Session Manager plugin auto-install."
      echo "Please install manually from:"
      echo "  https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html"
      ;;
  esac

  # Verify installation
  if command -v session-manager-plugin >/dev/null 2>&1; then
    echo "✅ Session Manager plugin installed successfully"
  else
    echo "⚠️ Session Manager plugin installation may have failed. Please verify manually."
  fi
fi

echo ""
echo "✅ Installation completed!"
echo "-----------------------------------------------"
echo "Verifying installations:"
aws --version 2>&1
jq --version 2>&1
session-manager-plugin --version 2>&1 || echo "Session Manager plugin: installed (version info not available)"
echo "-----------------------------------------------"
echo ""
echo "🎉 You're ready to use AWS SSM!"
echo "Next step: Run the setup script provided by your administrator"
