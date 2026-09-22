#!/usr/bin/env bash
# Live check: real fm-promote.sh, then its printed next: command run with the real fm-send.sh,
# in a throwaway FM_HOME against a private tmux server. Includes the claude-x / fm-claude-x collision.
set -u
REPO=${1:?repo}; cd "$REPO"
S=$(mktemp -d /tmp/fmpromote-live.XXXX); export TMUX_TMPDIR=$S/tmux; mkdir -p "$TMUX_TMPDIR"; unset TMUX
H=$S/home; mkdir -p "$H/state"
ids="fm-claude-u2063-strip-k3 claude-x fm-claude-x"
first=1
for id in $ids; do
  if [ $first = 1 ]; then tmux new-session -d -s firstmate -n "fm-$id" 'cat'; first=0; else tmux new-window -t firstmate -n "fm-$id" 'cat'; fi
  printf 'window=firstmate:fm-%s\nkind=scout\nworktree=/tmp/wt\nbackend=tmux\n' "$id" > "$H/state/$id.meta"
  FM_HOME=$H bin/fm-brief.sh "$id" fixture-project --scout >/dev/null 2>&1 || echo "brief fail $id"
  f=$H/data/$id/brief.md; c=$(cat "$f"); c=${c//'{TASK}'/Ship it.}; c=${c//'{FIRSTMATE_SPEC}'/Spec.}; printf '%s\n' "$c" > "$f"
done
echo "# commit: $(git rev-parse --short HEAD)"
echo "# sandbox FM_HOME=$H; private tmux (TMUX_TMPDIR); fm-send run with FM_GATE_REFUSE_BYPASS=1 (sandbox-fleet test hatch)"
echo "# tasks: $(cd "$H/state" && ls *.meta | tr '\n' ' ')"
echo
for id in fm-claude-u2063-strip-k3 claude-x; do
  echo "\$ bin/fm-promote.sh $id --mode no-mistakes --yolo off"
  out=$(FM_HOME=$H FM_STATE_OVERRIDE=$H/state bin/fm-promote.sh "$id" --mode no-mistakes --yolo off 2>&1); echo "rc=$?"
  printf '%s\n' "$out" | grep -E '^(promoted|wrote|next):'
  cmd=$(printf '%s\n' "$out" | sed -n 's/^next: //p')
  echo "--- running the printed next: command with the REAL bin/fm-send.sh"
  eval "FM_GATE_REFUSE_BYPASS=1 FM_STATE_OVERRIDE=$H/state $cmd" 2>&1 | tail -3; echo "rc=${PIPESTATUS[0]}"
  echo
done
echo "=== inbox state after delivery:"
for id in $ids fm-fm-claude-u2063-strip-k3 fm-fm-claude-x; do
  d=$H/state/$id.inbox
  if [ -e "$d" ]; then echo "$id.inbox: $(find "$d" -type f | wc -l) file(s); $(grep -rl 'no-mistakes' "$d" 2>/dev/null | wc -l) containing ship instructions"; else echo "$id.inbox: absent"; fi
done
echo "=== doorbell seen in each tmux pane:"
for id in $ids; do echo "fm-$id: $(tmux capture-pane -p -t "firstmate:fm-$id" | grep -v '^$' | tail -1)"; done
tmux kill-server; rm -rf "$S"
