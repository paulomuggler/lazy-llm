#!/bin/bash

# A script to install the llm-dev-session environment.

# --- Setup and Configuration ---
set -e # Exit immediately if a command exits with a non-zero status.

# Color codes for messages
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}Starting llm-dev-session installation...${NC}"

# --- 1. Determine Neovim Configuration Path ---
# Respect XDG_CONFIG_HOME if set, otherwise default to ~/.config
NVIM_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/nvim"
echo "--> Checking for Neovim config at: $NVIM_CONFIG_DIR"

if [ ! -d "$NVIM_CONFIG_DIR" ]; then
  echo -e "${YELLOW}Error: Neovim configuration directory not found.${NC}"
  echo "Please ensure Neovim is installed and has been run at least once."
  exit 1
fi

# --- 2. Check for LazyVim ---
LAZY_LOCK_FILE="$NVIM_CONFIG_DIR/lazy-lock.json"
echo "--> Checking for LazyVim installation..."
if [ ! -f "$LAZY_LOCK_FILE" ]; then
  echo -e "${YELLOW}Error: lazy-lock.json not found in Neovim config.${NC}"
  echo "This installer requires a Neovim setup managed by LazyVim."
  exit 1
fi
echo "    LazyVim installation confirmed."

# --- 3. Check for Dependencies ---
DEPS=("git" "nvim" "tmux")
echo "--> Checking for dependencies: ${DEPS[*]}"
for dep in "${DEPS[@]}"; do
  if ! command -v "$dep" &>/dev/null; then
    echo -e "${YELLOW}    Warning: Dependency '$dep' not found in PATH.${NC}"
  fi
done
echo "    Dependency check complete."

# --- 4. Install Binary Scripts ---
BIN_DIR="$HOME/.local/bin"
echo "--> Installing scripts to $BIN_DIR..."
mkdir -p "$BIN_DIR"

cp "bin/llm-send" "$BIN_DIR/"
cp "bin/dev-session" "$BIN_DIR/"

chmod +x "$BIN_DIR/llm-send"
chmod +x "$BIN_DIR/dev-session"
echo "    Scripts installed and made executable."

# --- 5. Install Neovim Plugins ---
NVIM_PLUGINS_DIR="$NVIM_CONFIG_DIR/lua/plugins"
echo "--> Installing Neovim plugins to $NVIM_PLUGINS_DIR..."
mkdir -p "$NVIM_PLUGINS_DIR"

cp "nvim_config/lua/plugins/llm-send.lua" "$NVIM_PLUGINS_DIR/"
cp "nvim_config/lua/plugins/git.lua" "$NVIM_PLUGINS_DIR/"
echo "    Plugins installed."

# --- 6. Check PATH and Provide Final Instructions ---
PATH_INCLUDES_LOCAL_BIN=false
if [[ ":$PATH:" == *":$BIN_DIR:"* ]]; then
  PATH_INCLUDES_LOCAL_BIN=true
fi

echo -e "\n${GREEN}--- Installation Complete! ---${NC}\n"

if [ "$PATH_INCLUDES_LOCAL_BIN" = false ]; then
  echo -e "${YELLOW}ACTION REQUIRED: Add ~/.local/bin to your PATH${NC}"
  echo "Your shell needs to know where to find the 'llm-send' and 'dev-session' commands."
  echo "Add the following line to your shell's configuration file (e.g., ~/.bashrc, ~/.zshrc):"
  echo ""
  echo "  export PATH=\"$HOME/.local/bin:\$PATH\""
  echo ""
  echo "You must restart your shell for this change to take effect."
  echo ""
fi

echo "Restart Neovim for the new plugins to be loaded."
