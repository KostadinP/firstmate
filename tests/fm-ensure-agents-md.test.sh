#!/usr/bin/env bash
# Behavior tests for bin/fm-ensure-agents-md.sh.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

TMP_ROOT=$(fm_test_tmproot fm-ensure-agents-md)

# Public contract: CLAUDE.md is a symlink to AGENTS.md.
assert_claude_symlink() {
  local dir=$1
  [ -L "$dir/CLAUDE.md" ] || fail "CLAUDE.md is not a symlink; expected CLAUDE.md -> AGENTS.md"
  case "$(readlink "$dir/CLAUDE.md")" in
    AGENTS.md|./AGENTS.md) ;;
    *) fail "CLAUDE.md symlink target is not AGENTS.md (got: $(readlink "$dir/CLAUDE.md"))" ;;
  esac
}

write_fixture_claude_symlink() {
  ln -s AGENTS.md "$1/CLAUDE.md"
}

test_created_agents_md_includes_self_governance() {
  local repo agents
  repo="$TMP_ROOT/new-project"
  mkdir -p "$repo"
  "$ROOT/bin/fm-ensure-agents-md.sh" "$repo" >/dev/null 2>&1 || fail "fm-ensure-agents-md.sh failed for empty project"
  agents="$repo/AGENTS.md"
  assert_present "$agents" "AGENTS.md was not created"
  assert_claude_symlink "$repo"
  assert_grep "## Maintaining this file" "$agents" "self-governance section heading missing"
  assert_grep "Keep this file for knowledge useful to almost every future agent session in this project." "$agents" \
    "self-governance section lost the future-session bar"
  assert_grep "Do not repeat what the codebase already shows; point to the authoritative file or command instead." "$agents" \
    "self-governance section lost pointer-over-copy guidance"
  assert_grep "Prefer rewriting or pruning existing entries over appending new ones." "$agents" \
    "self-governance section lost rewrite-or-prune guidance"
  assert_grep "When updating this file, preserve this bar for all agents and keep entries concise." "$agents" \
    "self-governance section lost all-agents maintenance guidance"
  pass "fm-ensure-agents-md.sh: created AGENTS.md includes self-governance section"
}

test_fresh_setup_writes_claude_symlink() {
  local repo out
  repo="$TMP_ROOT/fresh-symlink-project"
  mkdir -p "$repo"
  out=$("$ROOT/bin/fm-ensure-agents-md.sh" "$repo" 2>&1) \
    || fail "fm-ensure-agents-md.sh failed creating a fresh symlink"
  assert_contains "$out" "created:" "fresh setup did not report created"
  assert_claude_symlink "$repo"
  pass "fm-ensure-agents-md.sh: fresh setup writes a CLAUDE.md -> AGENTS.md symlink"
}

test_promoted_claude_md_includes_self_governance() {
  local repo agents count
  repo="$TMP_ROOT/claude-project"
  mkdir -p "$repo"
  cat > "$repo/CLAUDE.md" <<'EOF'
# Existing agent memory

Run tests with `make test`.
EOF
  "$ROOT/bin/fm-ensure-agents-md.sh" "$repo" >/dev/null 2>&1 || fail "fm-ensure-agents-md.sh failed for CLAUDE.md promotion"
  agents="$repo/AGENTS.md"
  assert_present "$agents" "AGENTS.md was not created during promotion"
  assert_claude_symlink "$repo"
  assert_grep "Run tests with \`make test\`." "$agents" \
    "promotion lost existing CLAUDE.md content"
  count=$(grep -Fc "## Maintaining this file" "$agents")
  [ "$count" -eq 1 ] || fail "promotion wrote $count self-governance sections"
  assert_grep "Keep this file for knowledge useful to almost every future agent session in this project." "$agents" \
    "promoted AGENTS.md missing self-governance wording"
  pass "fm-ensure-agents-md.sh: promoted CLAUDE.md includes self-governance section"
}

test_promoted_claude_md_without_trailing_newline_keeps_blank_separator() {
  local repo agents before
  repo="$TMP_ROOT/no-trailing-newline-project"
  mkdir -p "$repo"
  printf '# Existing agent memory\n\nRun tests with make test.' > "$repo/CLAUDE.md"
  "$ROOT/bin/fm-ensure-agents-md.sh" "$repo" >/dev/null 2>&1 || fail "fm-ensure-agents-md.sh failed for newline-less CLAUDE.md promotion"
  agents="$repo/AGENTS.md"
  assert_grep "Run tests with make test." "$agents" \
    "newline-less promotion lost or mangled the last content line"
  assert_grep "## Maintaining this file" "$agents" \
    "newline-less promotion did not append the self-governance section"
  before=$(grep -B1 -Fx '## Maintaining this file' "$agents" | head -n 1)
  [ -z "$before" ] || fail "self-governance heading not preceded by a blank line (got: $before)"
  assert_claude_symlink "$repo"
  pass "fm-ensure-agents-md.sh: newline-less promotion keeps a blank separator line"
}

test_existing_agents_md_with_symlink_gains_self_governance() {
  local repo agents out count
  repo="$TMP_ROOT/existing-symlinked-project"
  mkdir -p "$repo"
  printf '# Existing agent memory\n\nBuild with make.\n' > "$repo/AGENTS.md"
  ln -s AGENTS.md "$repo/CLAUDE.md"
  agents="$repo/AGENTS.md"
  out=$("$ROOT/bin/fm-ensure-agents-md.sh" "$repo" 2>&1) \
    || fail "fm-ensure-agents-md.sh failed for existing AGENTS.md with symlink"
  assert_contains "$out" "updated:" "injection into existing AGENTS.md did not report an update"
  assert_grep "Build with make." "$agents" "injection dropped existing AGENTS.md content"
  assert_grep "## Maintaining this file" "$agents" "existing AGENTS.md did not gain the self-governance section"
  count=$(grep -Fc "## Maintaining this file" "$agents")
  [ "$count" -eq 1 ] || fail "injection wrote $count self-governance sections"
  assert_claude_symlink "$repo"
  # Re-run must be a byte-exact no-op reporting unchanged, leaving the symlink.
  cp "$agents" "$repo/.after-first"
  out=$("$ROOT/bin/fm-ensure-agents-md.sh" "$repo" 2>&1) \
    || fail "fm-ensure-agents-md.sh failed on idempotent re-run"
  assert_contains "$out" "unchanged:" "idempotent re-run did not report unchanged"
  diff "$repo/.after-first" "$agents" >/dev/null \
    || fail "idempotent re-run modified AGENTS.md"
  assert_claude_symlink "$repo"
  pass "fm-ensure-agents-md.sh: existing symlinked AGENTS.md gains the section idempotently"
}

test_correct_symlink_left_alone_without_clobbering_agents() {
  local repo agents out
  repo="$TMP_ROOT/symlink-kept-project"
  mkdir -p "$repo"
  printf '# Unique agent memory\n\nDo not clobber this payload.\n\n## Maintaining this file\n\nKeep this file for knowledge useful to almost every future agent session in this project.\nDo not repeat what the codebase already shows; point to the authoritative file or command instead.\nPrefer rewriting or pruning existing entries over appending new ones.\nWhen updating this file, preserve this bar for all agents and keep entries concise.\n' > "$repo/AGENTS.md"
  ln -s AGENTS.md "$repo/CLAUDE.md"
  agents="$repo/AGENTS.md"
  cp "$agents" "$repo/.before"
  out=$("$ROOT/bin/fm-ensure-agents-md.sh" "$repo" 2>&1) \
    || fail "fm-ensure-agents-md.sh failed keeping a correct CLAUDE.md symlink"
  assert_contains "$out" "unchanged:" "correct symlink was not reported unchanged"
  assert_claude_symlink "$repo"
  cmp -s "$repo/.before" "$agents" \
    || fail "correct-symlink handling clobbered AGENTS.md"
  assert_grep "Do not clobber this payload." "$agents" \
    "correct-symlink handling lost unique AGENTS.md content"
  cp "$agents" "$repo/.after-first"
  out=$("$ROOT/bin/fm-ensure-agents-md.sh" "$repo" 2>&1) \
    || fail "fm-ensure-agents-md.sh failed on post-keep re-run"
  assert_contains "$out" "unchanged:" "post-keep re-run did not report unchanged"
  cmp -s "$repo/.after-first" "$agents" \
    || fail "post-keep re-run modified AGENTS.md"
  assert_claude_symlink "$repo"
  pass "fm-ensure-agents-md.sh: correct symlink is left alone without clobbering AGENTS.md"
}

test_legacy_pointer_migrates_to_symlink_without_clobbering_agents() {
  local repo agents out
  repo="$TMP_ROOT/legacy-pointer-project"
  mkdir -p "$repo"
  printf '# Existing agent memory\n\nDo not clobber this payload.\n\n## Maintaining this file\n\nKeep this file for knowledge useful to almost every future agent session in this project.\nDo not repeat what the codebase already shows; point to the authoritative file or command instead.\nPrefer rewriting or pruning existing entries over appending new ones.\nWhen updating this file, preserve this bar for all agents and keep entries concise.\n' > "$repo/AGENTS.md"
  cat > "$repo/CLAUDE.md" <<'EOF'
<!-- Points Claude at AGENTS.md via import; edit AGENTS.md, not this file. -->
@AGENTS.md
EOF
  agents="$repo/AGENTS.md"
  cp "$agents" "$repo/.before"
  out=$("$ROOT/bin/fm-ensure-agents-md.sh" "$repo" 2>&1) \
    || fail "fm-ensure-agents-md.sh failed migrating a legacy real-file pointer"
  assert_contains "$out" "updated:" "legacy-pointer migration did not report an update"
  assert_claude_symlink "$repo"
  cmp -s "$repo/.before" "$agents" \
    || fail "legacy-pointer migration clobbered AGENTS.md"
  assert_grep "Do not clobber this payload." "$agents" \
    "legacy-pointer migration lost unique AGENTS.md content"
  out=$("$ROOT/bin/fm-ensure-agents-md.sh" "$repo" 2>&1) \
    || fail "fm-ensure-agents-md.sh failed on post-migration re-run"
  assert_contains "$out" "unchanged:" "post-migration re-run did not report unchanged"
  assert_claude_symlink "$repo"
  pass "fm-ensure-agents-md.sh: legacy real-file pointer migrates to symlink without clobbering AGENTS.md"
}

test_existing_agents_md_without_claude_gains_section_and_symlink() {
  local repo agents out count
  repo="$TMP_ROOT/existing-bare-project"
  mkdir -p "$repo"
  printf '# Existing agent memory\n\nDeploy with kubectl.\n' > "$repo/AGENTS.md"
  agents="$repo/AGENTS.md"
  out=$("$ROOT/bin/fm-ensure-agents-md.sh" "$repo" 2>&1) \
    || fail "fm-ensure-agents-md.sh failed for existing AGENTS.md without CLAUDE.md"
  assert_contains "$out" "updated:" "injection without CLAUDE.md did not report an update"
  assert_claude_symlink "$repo"
  assert_grep "Deploy with kubectl." "$agents" "injection dropped existing AGENTS.md content"
  count=$(grep -Fc "## Maintaining this file" "$agents")
  [ "$count" -eq 1 ] || fail "injection wrote $count self-governance sections"
  pass "fm-ensure-agents-md.sh: existing AGENTS.md without CLAUDE.md gains section and symlink"
}

test_existing_agents_md_with_section_reports_unchanged() {
  local repo agents out
  repo="$TMP_ROOT/fully-formed-project"
  mkdir -p "$repo"
  # Build a fully-formed project (AGENTS.md with the section + symlink).
  "$ROOT/bin/fm-ensure-agents-md.sh" "$repo" >/dev/null 2>&1 \
    || fail "fm-ensure-agents-md.sh failed building the fully-formed fixture"
  agents="$repo/AGENTS.md"
  assert_claude_symlink "$repo"
  cp "$agents" "$repo/.before"
  out=$("$ROOT/bin/fm-ensure-agents-md.sh" "$repo" 2>&1) \
    || fail "fm-ensure-agents-md.sh failed on already-formed project"
  assert_contains "$out" "unchanged:" "already-formed project was not reported unchanged"
  diff "$repo/.before" "$agents" >/dev/null \
    || fail "already-formed AGENTS.md was modified"
  assert_claude_symlink "$repo"
  pass "fm-ensure-agents-md.sh: AGENTS.md that already has the section stays unchanged"
}

test_existing_crlf_agents_md_with_section_stays_unchanged() {
  local repo agents out count
  repo="$TMP_ROOT/crlf-formed-project"
  mkdir -p "$repo"
  printf '%s\r\n' \
    '# Existing agent memory' \
    '' \
    '## Maintaining this file' \
    '' \
    'Keep this file for knowledge useful to almost every future agent session in this project.' \
    'Do not repeat what the codebase already shows; point to the authoritative file or command instead.' \
    'Prefer rewriting or pruning existing entries over appending new ones.' \
    'When updating this file, preserve this bar for all agents and keep entries concise.' > "$repo/AGENTS.md"
  write_fixture_claude_symlink "$repo"
  agents="$repo/AGENTS.md"
  cp "$agents" "$repo/.before"
  out=$("$ROOT/bin/fm-ensure-agents-md.sh" "$repo" 2>&1) \
    || fail "fm-ensure-agents-md.sh failed on CRLF AGENTS.md with the section"
  assert_contains "$out" "unchanged:" "complete CRLF AGENTS.md was not reported unchanged"
  cmp -s "$repo/.before" "$agents" \
    || fail "complete CRLF AGENTS.md was modified"
  assert_claude_symlink "$repo"
  count=$(LC_ALL=C grep -a -c '## Maintaining this file' "$agents")
  [ "$count" -eq 1 ] || fail "complete CRLF AGENTS.md has $count self-governance sections"
  pass "fm-ensure-agents-md.sh: CRLF AGENTS.md with the section stays unchanged"
}

test_existing_crlf_agents_md_without_section_preserves_crlf() {
  local repo agents out
  repo="$TMP_ROOT/crlf-injected-project"
  mkdir -p "$repo"
  printf '%s\r\n' \
    '# Existing agent memory' \
    '' \
    'Run tests with make test.' > "$repo/AGENTS.md"
  ln -s AGENTS.md "$repo/CLAUDE.md"
  agents="$repo/AGENTS.md"
  out=$("$ROOT/bin/fm-ensure-agents-md.sh" "$repo" 2>&1) \
    || fail "fm-ensure-agents-md.sh failed injecting into CRLF AGENTS.md"
  assert_contains "$out" "updated:" "CRLF AGENTS.md injection did not report an update"
  printf '%s\r\n' \
    '# Existing agent memory' \
    '' \
    'Run tests with make test.' \
    '' \
    '## Maintaining this file' \
    '' \
    'Keep this file for knowledge useful to almost every future agent session in this project.' \
    'Do not repeat what the codebase already shows; point to the authoritative file or command instead.' \
    'Prefer rewriting or pruning existing entries over appending new ones.' \
    'When updating this file, preserve this bar for all agents and keep entries concise.' > "$repo/.expected"
  cmp -s "$repo/.expected" "$agents" \
    || fail "CRLF AGENTS.md injection did not preserve CRLF line endings"
  assert_claude_symlink "$repo"
  cp "$agents" "$repo/.after-first"
  "$ROOT/bin/fm-ensure-agents-md.sh" "$repo" >/dev/null 2>&1 \
    || fail "fm-ensure-agents-md.sh failed on idempotent CRLF re-run"
  cmp -s "$repo/.after-first" "$agents" \
    || fail "idempotent CRLF re-run modified AGENTS.md"
  assert_claude_symlink "$repo"
  pass "fm-ensure-agents-md.sh: CRLF injection preserves line endings idempotently"
}

test_correct_symlink_is_accepted_when_agents_present() {
  local repo out
  repo="$TMP_ROOT/with-symlink-project"
  mkdir -p "$repo"
  printf '# Existing agent memory\n\n## Maintaining this file\n\nKeep this file for knowledge useful to almost every future agent session in this project.\nDo not repeat what the codebase already shows; point to the authoritative file or command instead.\nPrefer rewriting or pruning existing entries over appending new ones.\nWhen updating this file, preserve this bar for all agents and keep entries concise.\n' > "$repo/AGENTS.md"
  write_fixture_claude_symlink "$repo"
  out=$("$ROOT/bin/fm-ensure-agents-md.sh" "$repo" 2>&1) \
    || fail "fm-ensure-agents-md.sh refused a correct CLAUDE.md symlink"
  assert_contains "$out" "unchanged:" "correct symlink plus AGENTS.md was not reported unchanged"
  assert_claude_symlink "$repo"
  pass "fm-ensure-agents-md.sh: correct CLAUDE.md symlink is not a conflict"
}

test_distinct_real_files_are_refused() {
  local repo out rc
  repo="$TMP_ROOT/distinct-real-files-project"
  mkdir -p "$repo"
  printf '# Agents memory\n' > "$repo/AGENTS.md"
  printf '# Claude memory\n' > "$repo/CLAUDE.md"
  cp "$repo/AGENTS.md" "$repo/.agents-before"
  cp "$repo/CLAUDE.md" "$repo/.claude-before"
  out=$("$ROOT/bin/fm-ensure-agents-md.sh" "$repo" 2>&1)
  rc=$?
  [ "$rc" -ne 0 ] || fail "expected a non-zero exit for distinct real AGENTS.md and CLAUDE.md"
  assert_contains "$out" "conflict:" "distinct real files did not report a conflict"
  cmp -s "$repo/.agents-before" "$repo/AGENTS.md" \
    || fail "distinct-real-files refusal modified AGENTS.md"
  cmp -s "$repo/.claude-before" "$repo/CLAUDE.md" \
    || fail "distinct-real-files refusal modified CLAUDE.md"
  [ ! -L "$repo/CLAUDE.md" ] || fail "distinct-real-files refusal turned CLAUDE.md into a symlink"
  pass "fm-ensure-agents-md.sh: refuses distinct real AGENTS.md and CLAUDE.md"
}

test_agents_md_symlink_is_refused() {
  local repo out rc
  repo="$TMP_ROOT/agents-symlink-project"
  mkdir -p "$repo"
  printf '# payload\n' > "$repo/payload.md"
  ln -s payload.md "$repo/AGENTS.md"
  out=$("$ROOT/bin/fm-ensure-agents-md.sh" "$repo" 2>&1)
  rc=$?
  [ "$rc" -ne 0 ] || fail "expected a non-zero exit when AGENTS.md is a symlink"
  assert_contains "$out" "conflict:" "AGENTS.md symlink did not report a conflict"
  [ -L "$repo/AGENTS.md" ] || fail "AGENTS.md symlink refusal disturbed the symlink"
  assert_absent "$repo/CLAUDE.md" "AGENTS.md symlink refusal created CLAUDE.md"
  pass "fm-ensure-agents-md.sh: refuses AGENTS.md when it is a symlink"
}

test_wrong_target_symlink_is_refused() {
  local repo out rc
  repo="$TMP_ROOT/wrong-target-project"
  mkdir -p "$repo"
  printf '# Agents memory\n' > "$repo/AGENTS.md"
  printf '# other\n' > "$repo/OTHER.md"
  ln -s OTHER.md "$repo/CLAUDE.md"
  cp "$repo/AGENTS.md" "$repo/.agents-before"
  out=$("$ROOT/bin/fm-ensure-agents-md.sh" "$repo" 2>&1)
  rc=$?
  [ "$rc" -ne 0 ] || fail "expected a non-zero exit for a CLAUDE.md symlink that does not point to AGENTS.md"
  assert_contains "$out" "conflict:" "wrong-target CLAUDE.md symlink did not report a conflict"
  [ -L "$repo/CLAUDE.md" ] || fail "wrong-target refusal removed the CLAUDE.md symlink"
  [ "$(readlink "$repo/CLAUDE.md")" = "OTHER.md" ] || fail "wrong-target refusal retargeted CLAUDE.md"
  cmp -s "$repo/.agents-before" "$repo/AGENTS.md" \
    || fail "wrong-target refusal modified AGENTS.md"
  pass "fm-ensure-agents-md.sh: refuses a CLAUDE.md symlink that does not point to AGENTS.md"
}

test_non_regular_claude_md_is_refused() {
  local repo out rc
  repo="$TMP_ROOT/non-regular-claude-project"
  mkdir -p "$repo" "$repo/CLAUDE.md"
  printf '# Agents memory\n' > "$repo/AGENTS.md"
  out=$("$ROOT/bin/fm-ensure-agents-md.sh" "$repo" 2>&1)
  rc=$?
  [ "$rc" -ne 0 ] || fail "expected a non-zero exit when CLAUDE.md is a directory"
  assert_contains "$out" "conflict:" "non-regular CLAUDE.md did not report a conflict"
  [ -d "$repo/CLAUDE.md" ] || fail "non-regular CLAUDE.md refusal disturbed the directory"
  pass "fm-ensure-agents-md.sh: refuses a non-regular CLAUDE.md"
}

test_lowercase_agents_md_refuses_case_fragile_symlink() {
  local repo out rc
  repo="$TMP_ROOT/lowercase-project"
  mkdir -p "$repo"
  printf '# project memory\n' > "$repo/agents.md"
  out=$("$ROOT/bin/fm-ensure-agents-md.sh" "$repo" 2>&1)
  rc=$?
  [ "$rc" -ne 0 ] || fail "expected a non-zero exit for a lowercase agents.md"
  assert_contains "$out" "conflict:" "lowercase agents.md did not report a conflict"
  assert_contains "$out" "agents.md" "conflict message did not name the offending file"
  assert_absent "$repo/CLAUDE.md" "a case-fragile CLAUDE.md symlink was created for lowercase agents.md"
  [ ! -L "$repo/CLAUDE.md" ] || fail "a case-fragile CLAUDE.md symlink was created for lowercase agents.md"
  assert_present "$repo/agents.md" "the real lowercase agents.md was disturbed"
  pass "fm-ensure-agents-md.sh: refuses a case-variant lowercase agents.md (issue #389)"
}

test_created_agents_md_includes_self_governance
test_fresh_setup_writes_claude_symlink
test_promoted_claude_md_includes_self_governance
test_promoted_claude_md_without_trailing_newline_keeps_blank_separator
test_existing_agents_md_with_symlink_gains_self_governance
test_correct_symlink_left_alone_without_clobbering_agents
test_legacy_pointer_migrates_to_symlink_without_clobbering_agents
test_existing_agents_md_without_claude_gains_section_and_symlink
test_existing_agents_md_with_section_reports_unchanged
test_existing_crlf_agents_md_with_section_stays_unchanged
test_existing_crlf_agents_md_without_section_preserves_crlf
test_correct_symlink_is_accepted_when_agents_present
test_distinct_real_files_are_refused
test_agents_md_symlink_is_refused
test_wrong_target_symlink_is_refused
test_non_regular_claude_md_is_refused
test_lowercase_agents_md_refuses_case_fragile_symlink
