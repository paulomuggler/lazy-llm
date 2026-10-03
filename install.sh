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

DEPS=("stow" "git" "nvim" "tmux" "jq")

for dep in "${DEPS[@]}"; do
  if ! command -v "$dep" &>/dev/null; then
    echo -e "${YELLOW}Error: Dependency '$dep' not found in PATH. Please install it first.${NC}"
    exit 1
  fi
done

# Check for clipboard tool (needed for Gemini CLI multiline paste strategy)
if ! command -v wl-copy &>/dev/null && ! command -v xclip &>/dev/null && ! command -v pbcopy &>/dev/null; then
  echo -e "${YELLOW}Warning: No clipboard tool found (wl-copy, xclip, or pbcopy).${NC}"
  echo -e "${YELLOW}Note: A clipboard tool is required for the Gemini CLI multiline paste strategy.${NC}"
fi

NVIM_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/nvim"
if [ ! -d "$NVIM_CONFIG_DIR" ] || [ ! -f "$NVIM_CONFIG_DIR/lazy-lock.json" ]; then
  echo -e "${YELLOW}Error: A Neovim setup managed by LazyVim is required.${NC}"
  echo "Looked for config at: $NVIM_CONFIG_DIR"
  exit 1
fi
echo "    Checks passed."

# --- 2. Conflict Resolution ---
echo "--> Checking for conflicting files..."

STOW_PACKAGES=("llm-send-bin" "lazy-llm-bin" "llm-add-bin" "llm-cycle-bin" "llm-remove-bin" "llm-status-bin" "llm-wt-bin" "nvim-git-plugin" "nvim-llm-send-plugin" "nvim-dropbar-plugin" "nvim-note-plugin" "nvim-glow-plugin" "nvim-session-plugin")
CONFLICT_FOUND=false
for package in "${STOW_PACKAGES[@]}"; do
  # Find every file within the package directory
  for file_to_stow in $(find "$package" -type f); do
    # Construct the target path in the HOME directory
    target_file="$HOME/$(echo "$file_to_stow" | sed -e "s#^$package/##")"

    if [ -e "$target_file" ]; then
      # Skip symlinks - stow will handle them with --restow. That includes a
      # file reached through a symlinked (stow-folded) directory, which
      # resolves to this very package file.
      if [ -L "$target_file" ] || [ "$(realpath "$target_file")" = "$(realpath "$file_to_stow")" ]; then
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

# --- 4. Claude Code plugin ---
# Registers this repo as a Claude Code marketplace and installs its plugin
# (claude-plugin/), whose hooks feed pane status (waiting / unread / idle) and
# the model shown on the AI pane border. Optional: without it, Claude panes
# fall back to screen-scraped status and show no model.
#
# The marketplace source is this checkout's GitHub remote when it has one, not
# its local path: Claude Code records the source in ~/.claude/settings.json,
# which is often a dotfiles-managed file shared across machines, and a
# home-directory path baked in there breaks on the next machine. The plugin
# itself is only a shim over the stowed llm-claude-hook, so pulling it from
# GitHub instead of the local checkout costs nothing in freshness.
#
# `claude plugin update` only touches one auto-detected scope (normally user).
# Projects that enable the plugin in a checked-in .claude/settings.json get
# project-scope installs, recorded per projectPath in installed_plugins.json,
# and each one is updated only by running the update from inside that project.
# Never fails: every problem is a warning, and it always returns 0.
update_lazy_llm_project_installs() {
  local plugin="lazy-llm@lazy-llm"
  local installed="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/installed_plugins.json"
  [[ -f "$installed" ]] || return 0

  local paths
  if command -v jq &>/dev/null; then
    if ! paths=$(jq -r --arg p "$plugin" '
        [(.plugins[$p] // [])[]
         | select(type == "object" and .scope == "project")
         | .projectPath | strings | select(length > 0)]
        | unique | .[]' "$installed" 2>/dev/null); then
      echo -e "    ${YELLOW}Warning: could not parse $installed; project-scope installs not updated.${NC}"
      return 0
    fi
  elif command -v python3 &>/dev/null; then
    if ! paths=$(python3 - "$installed" "$plugin" 2>/dev/null <<'PY'
import json, sys
with open(sys.argv[1]) as f:
    entries = (json.load(f).get("plugins") or {}).get(sys.argv[2]) or []
found = set()
for e in entries:
    p = e.get("projectPath") if isinstance(e, dict) and e.get("scope") == "project" else None
    if isinstance(p, str) and p:
        found.add(p)
for p in sorted(found):
    print(p)
PY
    ); then
      echo -e "    ${YELLOW}Warning: could not parse $installed; project-scope installs not updated.${NC}"
      return 0
    fi
  else
    echo "    Neither jq nor python3 found; project-scope plugin installs not checked."
    return 0
  fi

  local path
  while IFS= read -r path; do
    [[ -n "$path" ]] || continue
    if [[ ! -d "$path" ]]; then
      echo "    Skipped project-scope install in $path (directory no longer exists)."
    elif (cd "$path" && claude plugin update "$plugin" --scope project) >/dev/null 2>&1; then
      echo "    Updated project-scope install in $path"
    else
      echo -e "    ${YELLOW}Warning: could not update the project-scope install in $path.${NC}"
    fi
  done <<<"$paths"
  return 0
}

echo "--> Setting up the Claude Code plugin..."
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MARKETPLACE_SOURCE="$REPO_DIR"
origin_url=$(git -C "$REPO_DIR" remote get-url origin 2>/dev/null || true)
if [[ "$origin_url" =~ github\.com[:/]([^/]+/[^/]+)$ ]]; then
  MARKETPLACE_SOURCE="${BASH_REMATCH[1]%.git}"
fi
if ! command -v claude &>/dev/null; then
  echo -e "    ${YELLOW}claude not found; skipped. Re-run this script after installing Claude Code.${NC}"
else
  if claude plugin marketplace list 2>/dev/null | grep -qE '❯ lazy-llm$'; then
    claude plugin marketplace update lazy-llm >/dev/null 2>&1 \
      || echo -e "    ${YELLOW}Warning: could not update the lazy-llm marketplace.${NC}"
  else
    claude plugin marketplace add "$MARKETPLACE_SOURCE" >/dev/null 2>&1 \
      || echo -e "    ${YELLOW}Warning: could not add $MARKETPLACE_SOURCE as a marketplace.${NC}"
  fi
  if claude plugin list 2>/dev/null | grep -q '❯ lazy-llm@lazy-llm'; then
    claude plugin update lazy-llm@lazy-llm >/dev/null 2>&1 \
      || echo -e "    ${YELLOW}Warning: could not update the lazy-llm plugin.${NC}"
  else
    claude plugin install lazy-llm@lazy-llm >/dev/null 2>&1 \
      || echo -e "    ${YELLOW}Warning: could not install the lazy-llm plugin.${NC}"
  fi
  echo "    Plugin lazy-llm@lazy-llm installed (takes effect in new Claude sessions)."
  update_lazy_llm_project_installs || true
fi

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

