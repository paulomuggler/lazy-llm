#!/bin/bash

# A script to install the llm-dev-session environment using stow.

# --- Setup and Configuration ---
set -e # Exit immediately if a command exits with a non-zero status.

# Color codes for messages
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}Starting llm-dev-session installation...${NC}"

# --- 1. Dependency & Environment Checks ---
echo "--> Checking dependencies and environment..."

DEPS=("stow" "git" "nvim" "tmux")
for dep in "${DEPS[@]}"; do
  if ! command -v "$dep" &>/dev/null; then
    echo -e "${YELLOW}Error: Dependency '$dep' not found in PATH. Please install it first.${NC}"
    exit 1
  fi
done

NVIM_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/nvim"
if [ ! -d "$NVIM_CONFIG_DIR" ] || [ ! -f "$NVIM_CONFIG_DIR/lazy-lock.json" ]; then
  echo -e "${YELLOW}Error: A Neovim setup managed by LazyVim is required.${NC}"
  echo "Looked for config at: $NVIM_CONFIG_DIR"
  exit 1
fi
echo "    Checks passed."

# --- 2. Conflict Resolution ---
echo "--> Checking for conflicting files..."

STOW_PACKAGES=("llm-send-bin" "lazy-llm-bin" "nvim-git-plugin" "nvim-llm-send-plugin" "nvim-dropbar-plugin")
CONFLICT_FOUND=false
for package in "${STOW_PACKAGES[@]}"; do
  # Find every file within the package directory
  for file_to_stow in $(find "$package" -type f); do
    # Construct the target path in the HOME directory
    target_file="$HOME/$(echo "$file_to_stow" | sed -e "s#^$package/##")"

    if [ -e "$target_file" ]; then
      # Skip symlinks - stow will handle them with --restow
      if [ -L "$target_file" ]; then
        continue
      fi

      # Only prompt for actual files (not symlinks)
      CONFLICT_FOUND=true
      echo -e "${YELLOW}Conflict: File already exists at $target_file${NC}"
      read -p "    Overwrite and create a backup (.bak)? (y/n) " -n 1 -r
      echo
      if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "    Backing up '$target_file' to '$target_file.bak'..."
        mv "$target_file" "$target_file.bak"
      else
        echo "Aborting installation due to conflict."
        exit 1
      fi
    fi
  done
done

if [ "$CONFLICT_FOUND" = false ]; then
  echo "    No conflicts found."
fi

# --- 3. Run Stow ---
echo "--> Running stow to create symlinks..."
for package in "${STOW_PACKAGES[@]}"; do
  stow --restow --target="$HOME" "$package"
done
echo "    Symlinks created."

# --- 5. Final Instructions ---
BIN_DIR="$HOME/.local/bin"
echo "--> Checking user PATH for $BIN_DIR..."
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
    echo "  export PATH=\"$HOME/.local/bin:$PATH\""
    echo ""
    echo "You must restart your shell for this change to take effect."
    echo ""
fi

echo "Restart Neovim for the new plugins to be loaded."

