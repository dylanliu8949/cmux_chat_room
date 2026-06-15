#!/usr/bin/env sh
# Symlink every skill in skills/ into each agent directory, so the skill lives in ONE place
# (skills/<name>/) but is discoverable by Claude Code, Codex, and Cursor alike.
# Idempotent: safe to re-run after adding/removing skills.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SKILLS="$ROOT/skills"

for agent in .claude .cursor .codex .agents; do
  dest="$ROOT/$agent/skills"
  mkdir -p "$dest"
  for d in "$SKILLS"/*/; do
    name="$(basename "$d")"
    # relative target so the link stays valid if the repo moves
    ln -sfn "../../skills/$name" "$dest/$name"
  done
done

echo "Installed skill symlinks into .claude/skills, .cursor/skills, .codex/skills, .agents/skills"
