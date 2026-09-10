#!/usr/bin/env bash
# Creates an isolated Git worktree for safe agent evaluation.
set -euo pipefail

BRANCH_NAME="agent-eval-$(date +%s)"
WORKTREE_PATH=".worktrees/${BRANCH_NAME}"

echo "Provisioning isolated worktree at ${WORKTREE_PATH}..."
git worktree add -b "${BRANCH_NAME}" "${WORKTREE_PATH}" HEAD

# Symlink Godot engine caches to prevent expensive asset re-indexing
if [[ -d ".godot" ]]; then
    mkdir -p "${WORKTREE_PATH}/.godot"
    ln -sf "$(pwd)/.godot/imported" "${WORKTREE_PATH}/.godot/imported" 2>/dev/null || true
    ln -sf "$(pwd)/.godot/global_script_class_cache.cfg" "${WORKTREE_PATH}/.godot/global_script_class_cache.cfg" 2>/dev/null || true
fi

echo "Worktree ready. Launching Antigravity CLI..."
cd "${WORKTREE_PATH}"

agy --mode=accept-edits "$@" || true

# Teardown: Remove the ephemeral worktree cleanly
cd ../..
echo "Tearing down ephemeral worktree..."
git worktree remove --force "${WORKTREE_PATH}" 2>/dev/null || true
git branch -D "${BRANCH_NAME}" 2>/dev/null || true
git worktree prune --verbose