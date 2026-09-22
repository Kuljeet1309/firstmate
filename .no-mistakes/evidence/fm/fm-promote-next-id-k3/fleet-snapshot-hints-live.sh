#!/usr/bin/env bash
# Live check: the real fm-fleet-snapshot.sh emits steer/watch hints; run each one with the real
# fm-send.sh / fm-peek.sh in a throwaway FM_HOME on a private tmux server, with steer-me and fm-steer-me both present.
set -u
REPO=${1:?repo}; cd "$REPO"
S=$(mktemp -d /tmp/fmsnap-live.XXXX); export TMUX_TMPDIR=$S/tmux; mkdir -p "$TMUX_TMPDIR"; unset TMUX
H=$S/home; mkdir -p "$H/state" "$H/projects/steer-me" "$H/projects/fm-steer-me"
tmux new-session -d -s firstmate -n fm-steer-me 'cat'; tmux new-window -t firstmate -n fm-fm-steer-me 'cat'
for id in steer-me fm-steer-me; do
  printf 'window=firstmate:fm-%s\nworktree=%s\nproject=alpha\nharness=codex\nkind=ship\nmode=ship\nbackend=tmux\n' "$id" "$H/projects/$id" > "$H/state/$id.meta"
done
echo "# commit: $(git rev-parse --short HEAD); tasks: steer-me, fm-steer-me"
echo "\$ bin/fm-fleet-snapshot.sh --json | jq '.tasks[] | {id, actions}'"
json=$(FM_HOME=$H FM_STATE_OVERRIDE=$H/state bin/fm-fleet-snapshot.sh --json 2>/dev/null)
printf '%s' "$json" | jq -c '.tasks[] | {id, watch: .actions.watch, steer: .actions.steer}'
echo
printf '%s' "$json" | jq -r '.tasks[] | [.id, .actions.steer] | @tsv' | while IFS=$'\t' read -r id cmd; do
  cmd=${cmd//"'<instruction>'"/"'steer for $id'"}
  echo "\$ $cmd"
  eval "FM_GATE_REFUSE_BYPASS=1 FM_HOME=$H FM_STATE_OVERRIDE=$H/state $cmd" >/dev/null 2>&1; echo "rc=$?"
done
echo "=== which inbox got which steer:"
for id in steer-me fm-steer-me fm-fm-steer-me; do
  d=$H/state/$id.inbox
  if [ -e "$d" ]; then echo "$id.inbox: $(grep -rhoa "steer for [a-z-]*" "$d" | sort -u | tr '\n' ' ')"; else echo "$id.inbox: absent"; fi
done
echo "=== watch hint for steer-me via real fm-peek.sh:"
cmd=$(printf '%s' "$json" | jq -r '.tasks[] | select(.id=="steer-me") | .actions.watch'); echo "\$ $cmd"
eval "FM_HOME=$H FM_STATE_OVERRIDE=$H/state $cmd" 2>&1 | grep -v '^$' | head -3
tmux kill-server; rm -rf "$S"
