#!/usr/bin/env bash
# Live driver: real OpenCode 1.18.x on a 300-col isolated tmux pane whose cwd is
# an absolute path outside $HOME. Compares base (24f3a6b) vs fix classifier and
# fm-send doorbell behavior, plus adversarial typed input.
set -u
ROOT=$1; E=$2
REAL_TMUX=$(command -v tmux)
LAB=$(mktemp -d /tmp/fm-lab.XXXXXX); LAB=$(cd "$LAB" && pwd -P)
SOCKET="fm-lab-abs-$$"; S=abs; T="$S:oc"
cleanup() { "$REAL_TMUX" -L "$SOCKET" kill-server >/dev/null 2>&1; rm -rf -- "$LAB"; }
trap cleanup EXIT
mkdir -p "$LAB/shim" "$LAB/base"
printf '#!/bin/sh\nexec %s -L %s "$@"\n' "$REAL_TMUX" "$SOCKET" > "$LAB/shim/tmux"; chmod +x "$LAB/shim/tmux"
export PATH="$LAB/shim:$PATH"; unset TMUX NO_MISTAKES_GATE FM_GATE_REFUSE_BYPASS FM_ROOT_OVERRIDE FM_STATE_OVERRIDE FM_DATA_OVERRIDE FM_CONFIG_OVERRIDE FM_PROJECTS_OVERRIDE
git -C "$ROOT" archive 24f3a6b bin | tar -x -C "$LAB/base"
"$ROOT/bin/fm-lab-home.sh" create "$LAB/home" >/dev/null
WORK="$LAB/treehouse/worktree-pool-directory-long-name/slot-0123456789/project-under-test"
mkdir -p "$WORK"; git -C "$WORK" init -q
tmux new-session -d -s "$S" -n oc -x 300 -y 60 -c "$WORK"
tmux set-option -t "$S" window-size manual >/dev/null 2>&1; tmux resize-window -t "$T" -x 300 -y 60 >/dev/null 2>&1
cap() { tmux capture-pane -p -t "$T"; }
state() { bash -c '. "$1/bin/fm-composer-lib.sh"; . "$1/bin/fm-tmux-lib.sh"; fm_tmux_composer_state "$2"' _ "$1" "$T"; }
clear_input() { for _ in $(seq 1 40); do tmux send-keys -t "$T" BSpace; done; sleep 1; }
tmux send-keys -t "$T" -l opencode; tmux send-keys -t "$T" Enter
for _ in $(seq 1 120); do cap | grep -q 'Build' && break; sleep 0.5; done; sleep 3
tmux send-keys -t "$T" -l "Reply with exactly the word OK and nothing else."; tmux send-keys -t "$T" Enter
for _ in $(seq 1 60); do cap | grep -q 'esc interrupt' && break; sleep 0.5; done
echo "busy  fix=$(state "$ROOT")  base=$(state "$LAB/base")"; cap > "$E/live-busy-abs-cwd-screen.txt"
for _ in $(seq 1 240); do cap | grep -q 'esc interrupt' || break; sleep 0.5; done; sleep 2
echo "== cwd: $WORK"
cap > "$E/live-idle-abs-cwd-screen.txt"
echo "idle  fix=$(state "$ROOT")  base=$(state "$LAB/base")"
for txt in "hello world" "/tmp/some/abs/token" "/" "/exit"; do
  tmux send-keys -t "$T" -l "$txt"; sleep 1.5
  echo "typed '$txt'  fix=$(state "$ROOT")  base=$(state "$LAB/base")"
  [ "$txt" = "/tmp/some/abs/token" ] && cap > "$E/live-typed-abs-token-screen.txt"
  clear_input
done
tmux send-keys -t "$T" Escape; sleep 1
echo "after clear  fix=$(state "$ROOT")"
# fm-send end-to-end: base first (expect doorbell skipped), then fix (expect rung)
H="$LAB/home"; printf 'window=%s\nkind=ship\nharness=opencode\n' "$T" > "$H/state/w1.meta"
echo "== base fm-send:"; env -u NO_MISTAKES_GATE FM_HOME="$H" "$LAB/base/bin/fm-send.sh" w1 "probe from base" 2>&1 | tail -3; echo "rc=${PIPESTATUS[0]}"
sleep 2; cap | grep -c 'inbox' | sed 's/^/pane lines mentioning inbox after base send: /'
echo "== fix fm-send:"; env -u NO_MISTAKES_GATE FM_HOME="$H" "$ROOT/bin/fm-send.sh" w1 "probe from fix" 2>&1 | tail -3; echo "rc=${PIPESTATUS[0]}"
sleep 3; cap > "$E/live-after-fix-fm-send-screen.txt"
cap | grep -c 'inbox' | sed 's/^/pane lines mentioning inbox after fix send: /'
ls "$H/state/w1.inbox" 2>/dev/null | sed 's/^/inbox record: /'
