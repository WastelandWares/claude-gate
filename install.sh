#!/bin/bash
set -euo pipefail

echo "Building claude-gate..."
swift build --configuration release

BINARY=".build/release/claude-gate"
INSTALL_DIR="/usr/local/bin"
CONFIG_DIR="$HOME/.config/claude-gate"

echo "Installing binary to $INSTALL_DIR..."
sudo cp "$BINARY" "$INSTALL_DIR/claude-gate"
sudo chmod +x "$INSTALL_DIR/claude-gate"

echo "Seeding default config..."
mkdir -p "$CONFIG_DIR"
if [ ! -f "$CONFIG_DIR/rules.toml" ]; then
  cp Config/default-rules.toml "$CONFIG_DIR/rules.toml"
  echo "Created $CONFIG_DIR/rules.toml - edit to customize."
else
  echo "$CONFIG_DIR/rules.toml already exists, skipping."
fi

echo ""
echo "Add this to ~/.claude/settings.json:"
echo '  "hooks": {'
echo '    "PreToolUse": [{'
echo '      "matcher": "*",'
echo '      "hooks": [{"type": "command", "command": "/usr/local/bin/claude-gate"}]'
echo '    }]'
echo '  }'
echo ""
echo "Done."
