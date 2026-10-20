# Appended scenario: a relaunch rewrites every spawn-owned key exactly once,
# including OpenCode 2's opencode_version and Paseo's paseo_* keys, and keeps
# foreign durable keys.
test_relaunch_drops_stale_opencode_and_paseo_owned_keys() {
  local dir out rc m
  dir=$(new_case owned-union rl99)
  add_ship_task "$dir" rl99 claude
  {
    echo 'opencode_version=1.0.0-stale'
    echo 'paseo_terminal_id=term-stale'
    echo 'paseo_workspace_id=ws-stale'
    echo 'cmux_surface_id=surf-stale'
    echo 'pr=https://github.com/example/repo/pull/99'
    echo 'x_request=request-99'
  } >> "$dir/home/state/rl99.meta"
  echo "--- meta BEFORE relaunch ---"; cat "$dir/home/state/rl99.meta"
  out=$(run_control "$dir" rl99 relaunch --note "union key list check"); rc=$?
  echo "--- fm-control relaunch exit=$rc ---"; printf '%s\n' "$out" | tail -5
  m="$dir/home/state/rl99.meta"
  echo "--- meta AFTER relaunch ---"; cat "$m"
  expect_code 0 "$rc" "relaunch should succeed"
  ! grep -q '^opencode_version=' "$m" || fail "stale opencode_version survived relaunch"
  ! grep -q '^paseo_terminal_id=' "$m" || fail "stale paseo_terminal_id survived relaunch"
  ! grep -q '^paseo_workspace_id=' "$m" || fail "stale paseo_workspace_id survived relaunch"
  ! grep -q '^cmux_surface_id=' "$m" || fail "stale cmux_surface_id survived relaunch"
  [ "$(meta_field "$dir" rl99 pr)" = "https://github.com/example/repo/pull/99" ] || fail "pr lost"
  [ "$(meta_field "$dir" rl99 x_request)" = "request-99" ] || fail "x_request lost"
  [ "$(grep -c '^effort=' "$m")" = 1 ] || fail "effort duplicated"
  pass "relaunch drops stale opencode_version and paseo_* owned keys and keeps durable keys"
}
test_relaunch_drops_stale_opencode_and_paseo_owned_keys
test_relaunch_preserves_durable_task_metadata
