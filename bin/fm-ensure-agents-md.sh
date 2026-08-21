#!/usr/bin/env bash
# Ensure a project worktree follows the agent-memory file convention.
# AGENTS.md is the real project-intrinsic knowledge file; CLAUDE.md is a symlink
# to AGENTS.md so Claude Code reads the same file. Creates a minimal AGENTS.md
# skeleton when neither file exists, promotes a real CLAUDE.md file when it is
# the only file present (unless it is already a symlink to AGENTS.md), creates a
# CLAUDE.md -> AGENTS.md symlink when absent, leaves an already-correct symlink
# alone, and refuses to clobber distinct real files or wrong symlinks.
# Owns the canonical "## Maintaining this file" self-governance wording for
# project AGENTS.md files, injecting it idempotently into created skeletons,
# promoted CLAUDE.md files, and any existing AGENTS.md that still lacks it.
# A CLAUDE.md -> AGENTS.md symlink can dangle or mis-resolve on a
# case-insensitive filesystem (issue #389): a link at the literal AGENTS.md
# target can resolve to a lowercase agents.md or dangle when AGENTS.md is absent.
# This is the deliberate convention per explicit captain preference, a known and
# accepted tradeoff over the former real-file @AGENTS.md pointer.
# Refuses a case-variant real memory file such as a lowercase agents.md, so the
# AGENTS.md convention resolves to a real AGENTS.md on a case-sensitive
# filesystem (issue #389).
# This is a worktree utility for crewmates, not a supervision script, so it does
# not call fm-guard.sh.
# Usage: fm-ensure-agents-md.sh [repo-or-worktree-dir]
set -eu

usage() {
  echo "usage: fm-ensure-agents-md.sh [repo-or-worktree-dir]" >&2
}

case "${1:-}" in
  -h|--help)
    usage
    exit 0
    ;;
esac
[ "$#" -le 1 ] || { usage; exit 1; }

DIR=${1:-.}
[ -d "$DIR" ] || { echo "error: not a directory: $DIR" >&2; exit 1; }
DIR=$(cd "$DIR" && pwd -P)
cd "$DIR"

AGENTS=AGENTS.md
CLAUDE=CLAUDE.md

write_maintenance_section() {
  cat <<'EOF'
## Maintaining this file

Keep this file for knowledge useful to almost every future agent session in this project.
Do not repeat what the codebase already shows; point to the authoritative file or command instead.
Prefer rewriting or pruning existing entries over appending new ones.
When updating this file, preserve this bar for all agents and keep entries concise.
EOF
}

write_maintenance_section_with_eol() {
  local eol=$1 line
  while IFS= read -r line; do
    printf '%s%s' "$line" "$eol"
  done < <(write_maintenance_section)
}

# Idempotently append the canonical self-governance section to AGENTS.md when it
# is absent. Sets MAINT_INJECTED=1 when it appends and 0 when the section is
# already present, so callers can report whether the file changed.
MAINT_INJECTED=0
ensure_maintenance_section() {
  MAINT_INJECTED=0
  if grep -Fqx '## Maintaining this file' "$AGENTS" ||
    grep -Fqx $'## Maintaining this file\r' "$AGENTS"; then
    return 0
  fi
  local eol=$'\n' sep=''
  if LC_ALL=C grep -q $'\r$' "$AGENTS"; then
    eol=$'\r\n'
  fi
  if [ -s "$AGENTS" ]; then
    if [ -n "$(tail -c 1 "$AGENTS")" ]; then
      sep="${eol}${eol}"
    else
      sep=$eol
    fi
  fi
  {
    printf '%s' "$sep"
    write_maintenance_section_with_eol "$eol"
  } >> "$AGENTS"
  MAINT_INJECTED=1
}

write_skeleton() {
  cat > "$AGENTS" <<'EOF'
# Project agent memory

This file is the project's committed home for project-intrinsic agent knowledge: build, test, release, architecture, and sharp-edge notes that should travel with the code.

- Add durable project-specific notes here as they are discovered through real work.
EOF
  ensure_maintenance_section
}

# Canonical CLAUDE.md: a symlink to AGENTS.md. The literal AGENTS.md target is
# what Claude Code resolves, so an already-correct symlink is left alone.
is_correct_claude_symlink() {
  [ -L "$CLAUDE" ] || return 1
  target=$(readlink "$CLAUDE")
  case "$target" in
    "$AGENTS"|"./$AGENTS") return 0 ;;
  esac
  [ -e "$AGENTS" ] || return 1
  if command -v python3 >/dev/null 2>&1; then
    python3 - "$CLAUDE" "$AGENTS" <<'PY'
import os
import sys
sys.exit(0 if os.path.realpath(sys.argv[1]) == os.path.realpath(sys.argv[2]) else 1)
PY
    return $?
  fi
  return 1
}

# The former canonical real-file @AGENTS.md pointer that earlier versions of this
# script wrote. Its content is known and recoverable, so when it is the only
# CLAUDE.md form present it is safely replaced by the CLAUDE.md -> AGENTS.md
# symlink rather than treated as a distinct real-file conflict.
is_legacy_claude_pointer() {
  [ -f "$CLAUDE" ] && [ ! -L "$CLAUDE" ] || return 1
  cmp -s "$CLAUDE" - <<'EOF' || return 1
<!-- Points Claude at AGENTS.md via import; edit AGENTS.md, not this file. -->
@AGENTS.md
EOF
}

# Create the CLAUDE.md -> AGENTS.md symlink. Unlink any existing symlink or the
# legacy pointer first so a stale link cannot resolve to the wrong file; never
# follow a symlink when removing. Callers classify distinct real files as a
# conflict before invoking this, so this never overwrites unowned content.
install_claude_symlink() {
  if is_correct_claude_symlink; then
    return 0
  fi
  if [ -L "$CLAUDE" ] || [ -e "$CLAUDE" ]; then
    rm -f -- "$CLAUDE"
  fi
  ln -s "$AGENTS" "$CLAUDE"
}

# Refuse a case-variant real memory file (issue #389). On a case-insensitive
# filesystem an existing lowercase agents.md satisfies every [ -e AGENTS.md ]
# test below, so the script would emit a CLAUDE.md symlink whose literal
# AGENTS.md target resolves to the wrong file or dangles once the tree is
# checked out on a case-sensitive filesystem. Reading the real directory entries
# catches the mismatch on both filesystem kinds; surface it for manual
# reconciliation instead of writing the symlink against the wrong name.
for entry in *; do
  if [ ! -e "$entry" ] && [ ! -L "$entry" ]; then
    continue
  fi
  if [ "$entry" != "$AGENTS" ]; then
    case "$entry" in
      [Aa][Gg][Ee][Nn][Tt][Ss].[Mm][Dd])
        echo "conflict: memory file is named $entry in $DIR but the convention is AGENTS.md; rename it to AGENTS.md so CLAUDE.md's AGENTS.md target resolves portably" >&2
        exit 1
        ;;
    esac
  fi
done

if [ -L "$AGENTS" ]; then
  echo "conflict: AGENTS.md is a symlink in $DIR; expected AGENTS.md to be the real file" >&2
  exit 1
fi
if [ -e "$AGENTS" ] && [ ! -f "$AGENTS" ]; then
  echo "conflict: AGENTS.md exists in $DIR but is not a regular file" >&2
  exit 1
fi

if [ -e "$AGENTS" ]; then
  if [ -L "$CLAUDE" ]; then
    if is_correct_claude_symlink; then
      ensure_maintenance_section
      if [ "$MAINT_INJECTED" -eq 1 ]; then
        echo "updated: added ## Maintaining this file to AGENTS.md in $DIR"
      else
        echo "unchanged: AGENTS.md with CLAUDE.md -> AGENTS.md symlink in $DIR"
      fi
      exit 0
    fi
    echo "conflict: CLAUDE.md is a symlink in $DIR but does not point to AGENTS.md" >&2
    exit 1
  fi
  if [ ! -e "$CLAUDE" ]; then
    ensure_maintenance_section
    install_claude_symlink
    if [ "$MAINT_INJECTED" -eq 1 ]; then
      echo "updated: added ## Maintaining this file to AGENTS.md and created CLAUDE.md -> AGENTS.md symlink in $DIR"
    else
      echo "created: CLAUDE.md -> AGENTS.md symlink in $DIR"
    fi
    exit 0
  fi
  if [ -f "$CLAUDE" ]; then
    if is_legacy_claude_pointer; then
      ensure_maintenance_section
      install_claude_symlink
      if [ "$MAINT_INJECTED" -eq 1 ]; then
        echo "updated: added ## Maintaining this file to AGENTS.md and converted CLAUDE.md pointer to a CLAUDE.md -> AGENTS.md symlink in $DIR"
      else
        echo "updated: converted CLAUDE.md @AGENTS.md pointer to a CLAUDE.md -> AGENTS.md symlink in $DIR"
      fi
      exit 0
    fi
    echo "conflict: both AGENTS.md and CLAUDE.md are real files in $DIR; reconcile them manually" >&2
    exit 1
  fi
  echo "conflict: CLAUDE.md exists in $DIR but is not a regular file or symlink" >&2
  exit 1
fi

if [ -L "$CLAUDE" ]; then
  if is_correct_claude_symlink; then
    write_skeleton
    echo "created: AGENTS.md (CLAUDE.md already points to it) in $DIR"
    exit 0
  fi
  echo "conflict: CLAUDE.md is a symlink in $DIR but AGENTS.md is missing and the link does not point to AGENTS.md" >&2
  exit 1
fi

if [ -e "$CLAUDE" ]; then
  if [ -f "$CLAUDE" ]; then
    if is_legacy_claude_pointer; then
      write_skeleton
      install_claude_symlink
      echo "created: AGENTS.md and converted CLAUDE.md pointer to a CLAUDE.md -> AGENTS.md symlink in $DIR"
      exit 0
    fi
    mv "$CLAUDE" "$AGENTS"
    ensure_maintenance_section
    install_claude_symlink
    echo "promoted: moved CLAUDE.md to AGENTS.md and created CLAUDE.md -> AGENTS.md symlink in $DIR"
    exit 0
  fi
  echo "conflict: CLAUDE.md exists in $DIR but is not a regular file or symlink" >&2
  exit 1
fi

write_skeleton
install_claude_symlink
echo "created: AGENTS.md and CLAUDE.md -> AGENTS.md symlink in $DIR"
