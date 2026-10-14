#!/usr/bin/env bash
# Live driver: real OpenCode 1.18.x on a 300-col isolated tmux pane whose cwd is
# an absolute path outside $HOME. Compares base (24f3a6b) vs fix classifier and
# fm-send doorbell behavior, plus adversarial typed input.
set -u
ROOT=$1; E=$2
REAL_TMUX=$(command -v tmux)
LAB=$(mktemp -d /tmp/fm-lab.XXXXXX); LAB=$(cd "$LAB" && pwd -P)
SOCKET="fm-lab-abs-$$"; S=abs; T="$S:fm-w1"
cleanup() { "$REAL_TMUX" -L "$SOCKET" kill-server >/dev/null 2>&1; rm -rf -- "$LAB"; }
trap cleanup EXIT
mkdir -p "$LAB/shim" "$LAB/base"
printf '#!/bin/sh\nexec %s -L %s "$@"\n' "$REAL_TMUX" "$SOCKET" > "$LAB/shim/tmux"; chmod +x "$LAB/shim/tmux"
export PATH="$LAB/shim:$PATH"; unset TMUX NO_MISTAKES_GATE FM_GATE_REFUSE_BYPASS FM_ROOT_OVERRIDE FM_STATE_OVERRIDE FM_DATA_OVERRIDE FM_CONFIG_OVERRIDE FM_PROJECTS_OVERRIDE
git -C "$ROOT" archive 24f3a6b bin | tar -x -C "$LAB/base"
"$ROOT/bin/fm-lab-home.sh" create "$LAB/home" >/dev/null
WORK="$LAB/treehouse/worktree-pool-directory-long-name/slot-0123456789/project-under-test"
mkdir -p "$WORK"; git -C "$WORK" init -q
tmux new-session -d -s "$S" -n fm-w1 -x 300 -y 60 -c "$WORK"
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
H="$LAB/home"; printf 'window=%s\nkind=ship\nharness=opencode\nworktree=%s\nproject=%s\n' "$T" "$WORK" "$WORK" > "$H/state/w1.meta"
echo "== base fm-control exit:"; FM_HOME="$H" "$LAB/base/bin/fm-control.sh" w1 exit 2>&1 | tail -4; echo "rc=${PIPESTATUS[0]}"
sleep 2; echo "opencode alive after base exit: $(cap | grep -q 'Build ·' && echo yes || echo no)"
echo "== fix fm-control exit:"; FM_HOME="$H" "$ROOT/bin/fm-control.sh" w1 exit 2>&1 | tail -4; echo "rc=${PIPESTATUS[0]}"
sleep 3; cap > "$E/live-after-fix-fm-control-exit-screen.txt"
echo "opencode alive after fix exit: $(cap | grep -q 'Build ·' && echo yes || echo no)"
