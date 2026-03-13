#!/bin/bash
# install.sh — Install skills and agents for VS Code Copilot (macOS/Linux)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

SKILLS_DEST="$HOME/.copilot/skills"
if [[ "$OSTYPE" == "darwin"* ]]; then
    AGENTS_DEST="$HOME/Library/Application Support/Code/User/prompts"
else
    AGENTS_DEST="$HOME/.config/Code/User/prompts"
fi

if [[ "$1" != "--agents-only" ]]; then
    mkdir -p "$SKILLS_DEST"
    count=0
    for dir in "$SCRIPT_DIR"/skills/*/; do
        cp -r "$dir" "$SKILLS_DEST/"
        count=$((count + 1))
    done
    echo "Installed $count skills to $SKILLS_DEST"
fi

if [[ "$1" != "--skills-only" ]]; then
    mkdir -p "$AGENTS_DEST"
    count=0
    for f in "$SCRIPT_DIR"/agents/*.agent.md; do
        cp "$f" "$AGENTS_DEST/"
        count=$((count + 1))
    done
    echo "Installed $count agents to $AGENTS_DEST"
fi

echo "Done. Restart VS Code or open a new Copilot chat to use them."
