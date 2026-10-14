#!/usr/bin/env bash
# Live driver: OpenCode 1.18.x on 300-col tmux pane in absolute cwd outside $HOME.
set -u
ROOT=$1; BASEBIN=$2; EV=$3
REAL_TMUX=$(command -v tmux); SOCKET="fm-tst-abs-$$"; T="oc:oc"
LAB=$(mktemp -d /tmp/fm-tst-abs.XXXXXX); LAB=$(cd "$LAB" && pwd -P)
cleanup(){ "$REAL_TMUX" -L "$SOCKET" kill-server >/dev/null 2>&1; rm -rf -- "$LAB"; }
trap cleanup EXIT
WORK="$LAB/fleet-treehouse/a-rather-long-worktree-pool-directory/slot-0123456789/project-under-test"
mkdir -p "$WORK"; git -C "$WORK" init -q
t(){ "$REAL_TMUX" -L "$SOCKET" "$@"; }
verdict(){ # <bindir>
  ( tmux(){ "$REAL_TMUX" -L "$SOCKET" "$@"; }; . "$1/fm-tmux-lib.sh"; fm_tmux_composer_state "$T" )
}
cap(){ t capture-pane -p -t "$T" -S 0 -E - 2>/dev/null; }
waitf(){ local i=0; while [ $i -lt $2 ]; do cap | grep -Eq "$1" && return 0; sleep 0.5; i=$((i+1)); done; return 1; }
report(){ # <label>
  local n f b; n=$(verdict "$ROOT/bin"); b=$(verdict "$BASEBIN")
  printf '%-48s fixed=%-8s base=%s\n' "$1" "$n" "$b"
  f="$EV/pane-$(echo "$1" | tr -c 'a-zA-Z0-9\n' '-').txt"; cap > "$f"
}
t new-session -d -s oc -n oc -x 300 -y 60 -c "$WORK"
t set-option -t oc window-size manual >/dev/null 2>&1; t resize-window -t "$T" -x 300 -y 60 >/dev/null 2>&1
echo "cwd=$WORK  (HOME=$HOME)"; echo "opencode $(opencode --version)"
t send-keys -t "$T" -l opencode; t send-keys -t "$T" Enter
waitf 'Build' 120 || { cap; echo FAIL no composer; exit 1; }
sleep 3
t send-keys -t "$T" -l "Reply with exactly the word OK and nothing else."; t send-keys -t "$T" Enter
waitf "esc interrupt" 60
report "S2 busy mid-turn, abs rail"
i=0; while cap | grep -q "esc interrupt" && [ $i -lt 240 ]; do sleep 0.5; i=$((i+1)); done; sleep 2
cap | grep -En '┃ +/[^[:space:]]+ *$' | head -3 | sed 's/^/rail-row: /'
report "S1 idle, empty composer, abs rail"
type_check(){ # <text> <label>
  t send-keys -t "$T" -l "$1"; sleep 1.5; report "$2"
  t send-keys -t "$T" C-u; sleep 0.3
  # clear any leftover chars
  local k; for k in $(seq 1 40); do t send-keys -t "$T" BSpace; done; sleep 1
}
type_check "hello world" "S3 typed text + abs rail"
type_check "/" "S4 lone slash typed"
t send-keys -t "$T" Escape; sleep 1
type_check "/exit" "S5 /exit typed at left edge"
t send-keys -t "$T" Escape; sleep 1
type_check "/tmp/some/path" "S6 abs path token typed at left edge"
t send-keys -t "$T" Escape; sleep 1
report "S1b idle again after clearing"
