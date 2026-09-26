#!/usr/bin/env bash
# Live proof with a REAL Claude Code worker in a throwaway fm-lab-* Herdr session:
#   1. fm-spawn creates the worker pane in its leased worktree (not the primary checkout)
#   2. a Herdr server restart resumes the real claude conversation in the worktree
#   3. fm-control.sh <id> relaunch replaces the pane in the worktree, and the next
#      restart resumes the replacement's conversation (not the old one) there
#   4. fm-teardown closes the pane and returns the durable lease
# Usage: live-claude-restart.sh <firstmate-root> <log>
set -u
ROOT=$1
LOG=$2
exec > >(tee "$LOG") 2>&1
HELPER="$ROOT/bin/fm-herdr-lab.sh"
S=$("$HELPER" name livewt) || exit 1
export HERDR_SESSION=$S
unset HERDR_ENV HERDR_PANE_ID HERDR_SOCKET_PATH
TMP=$(mktemp -d "$(cd /tmp && pwd -P)/fm-live-wt.XXXXXX")
git -C "$TMP" init -q
export TREEHOUSE_ROOT="$TMP/pool"
LAB="$TMP/labhome"
"$ROOT/bin/fm-lab-home.sh" create "$LAB" >/dev/null || exit 1
ID="livewt$$"
PROJ="$TMP/proj"
lab() { "$HELPER" run "$S" "$@"; }
say() { printf '\n### %s\n' "$*"; }
RC=0
check() { if eval "$2"; then echo "PASS: $1"; else echo "FAIL: $1"; RC=1; fi; }
cleanup() {
  say "cleanup"
  (cd "$PROJ" 2>/dev/null && treehouse status) 2>/dev/null
  "$HELPER" teardown "$S"
  rm -rf "/tmp/fm-$ID" /tmp/fm-"$ID"+* 2>/dev/null
  find "$TMP" -type d -exec chmod u+rwx {} + 2>/dev/null
  rm -rf "$TMP"
}
trap cleanup EXIT

"$HELPER" provision "$S" || exit 1
SESSION_FILE=$(lab session list --json | jq -r --arg s "$S" '.sessions[]|select(.name==$s)|.session_dir')/session.json

mkdir -p "$PROJ"; git -C "$PROJ" init -q -b main
echo '# proj' > "$PROJ/README.md"; git -C "$PROJ" add .
git -C "$PROJ" -c user.name=t -c user.email=t@e.invalid commit -qm init
git clone -q --bare "$PROJ" "$TMP/origin.git"; git -C "$PROJ" remote add origin "file://$TMP/origin.git"
PROJ_REAL=$(cd "$PROJ" && pwd -P)
mkdir -p "$LAB/data/$ID"
cat > "$LAB/data/$ID/brief.md" <<EOF
# Task
## Captain's intent
Live lab check of where a Herdr worker restarts. Reply with the single word READY and then stop.

## Firstmate spec
Do not run any tools, do not edit any files, and do not run any commands. Only reply READY.
EOF

pane_cwd() { lab pane get "$1" 2>/dev/null | jq -r '.result.pane.cwd // empty'; }
saved() { jq -r '.workspaces[].tabs[].panes[] | [.cwd, (.agent_session.value // "-")] | @tsv' "$SESSION_FILE" 2>/dev/null; }
fg_claude() {  # <pane> -> "pid<TAB>cwd<TAB>cmdline"
  local pid
  for pid in $(lab pane process-info --pane "$1" 2>/dev/null | jq -r '.result.process_info.foreground_processes[]?.pid'); do
    tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null | grep -q claude || continue
    printf '%s\t%s\t%s\n' "$pid" "$(readlink "/proc/$pid/cwd")" "$(tr '\0' ' ' < "/proc/$pid/cmdline")"
    return 0
  done
  return 1
}
wait_for() {  # <tries> <cmd>
  local i
  for i in $(seq 1 "$1"); do eval "$2" && return 0; sleep 2; done
  return 1
}
meta() { sed -n "s/^$1=//p" "$LAB/state/$ID.meta" | tail -1; }
screen() { lab pane read "$1" --source visible --format text 2>/dev/null | grep -v "^\s*$" | tail -${2:-15}; }

say "1. spawn a real claude worker (herdr backend, flat)"
env FM_SPAWN_NO_GUARD=1 FM_HOME="$LAB" "$ROOT/bin/fm-spawn.sh" "$ID" "$PROJ" --harness claude \
  --backend herdr --mode local-only --yolo off 2>&1 | tail -8
WT=$(meta worktree); PANE=$(meta herdr_pane_id); WT_REAL=$(cd "$WT" && pwd -P)
echo "primary checkout: $PROJ_REAL"; echo "task worktree:    $WT_REAL"; echo "pane: $PANE"
(cd "$PROJ" && treehouse status)
check "pane created in the leased worktree (herdr pane cwd)" '[ "$(pane_cwd "$PANE")" = "$WT_REAL" ]'
check "worktree is durably leased to the task" '(cd "$PROJ" && treehouse status) | grep -q "held by $ID"'
wait_for 60 'fg_claude "$PANE" >/dev/null' ; echo "claude process: $(fg_claude "$PANE")"
check "real claude runs in the worktree" '[ "$(fg_claude "$PANE" | cut -f2)" = "$WT_REAL" ]'
wait_for 60 'saved | grep -q "^$WT_REAL	[^-]"' ; echo "herdr saved panes:"; saved
SID1=$(saved | awk -F'\t' -v w="$WT_REAL" '$1==w{print $2}' | tail -1)
check "herdr saved the pane cwd as the worktree with claude session $SID1" '[ -n "$SID1" ] && [ "$SID1" != - ]'
check "herdr saved nothing in the primary checkout" '! saved | grep -q "^$PROJ_REAL	"'
echo "--- worker screen:"; screen "$PANE"

say "2. restart the lab herdr server"
"$HELPER" stop "$S" >/dev/null; "$HELPER" provision "$S" >/dev/null
wait_for 60 'fg_claude "$PANE" | grep -q -- "--resume"'; echo "restored claude process: $(fg_claude "$PANE")"
check "restored pane cwd is the worktree" '[ "$(pane_cwd "$PANE")" = "$WT_REAL" ]'
check "claude resumed its own conversation ($SID1) in the worktree" \
  '[ "$(fg_claude "$PANE" | cut -f2)" = "$WT_REAL" ] && fg_claude "$PANE" | cut -f3 | grep -q -- "--resume $SID1"'
sleep 8; echo "--- restored worker screen:"; screen "$PANE"

say "3. fm-control.sh relaunch"
env FM_HOME="$LAB" "$ROOT/bin/fm-control.sh" "$ID" relaunch --note "live lab relaunch check; reply READY only" 2>&1 | tail -8
NEW=$(meta herdr_pane_id); echo "old pane $PANE -> new pane $NEW"
check "relaunch replaced the pane" '[ -n "$NEW" ] && [ "$NEW" != "$PANE" ]'
check "old pane is gone" '[ "$(lab pane get "$PANE" 2>&1 | jq -r ".error.code // empty")" = pane_not_found ]'
check "replacement pane created in the worktree" '[ "$(pane_cwd "$NEW")" = "$WT_REAL" ]'
wait_for 60 'fg_claude "$NEW" >/dev/null'; echo "claude process: $(fg_claude "$NEW")"
wait_for 60 'saved | awk -F"\t" -v w="$WT_REAL" -v o="$SID1" "\$1==w && \$2!=\"-\" && \$2!=o{f=1} END{exit !f}"'
echo "herdr saved panes:"; saved
SID2=$(saved | awk -F'\t' -v w="$WT_REAL" '$1==w{print $2}' | tail -1)
check "herdr saved the replacement's new conversation ($SID2) in the worktree, and only it" \
  '[ -n "$SID2" ] && [ "$SID2" != "$SID1" ] && [ "$(saved | grep -c "^$WT_REAL	")" = 1 ]'
"$HELPER" stop "$S" >/dev/null; "$HELPER" provision "$S" >/dev/null
wait_for 60 'fg_claude "$NEW" | grep -q -- "--resume"'; echo "restored claude process: $(fg_claude "$NEW")"
check "after restart the replacement's conversation resumes in the worktree, not the old one" \
  '[ "$(fg_claude "$NEW" | cut -f2)" = "$WT_REAL" ] && fg_claude "$NEW" | cut -f3 | grep -q -- "--resume $SID2"'
sleep 8; echo "--- restored worker screen:"; screen "$NEW"

say "4. teardown"
env FM_HOME="$LAB" "$ROOT/bin/fm-teardown.sh" "$ID" --force 2>&1 | tail -6
check "task pane closed" '[ "$(lab pane get "$NEW" 2>&1 | jq -r ".error.code // empty")" = pane_not_found ]'
check "lease returned to the pool" '! (cd "$PROJ" && treehouse status) | grep -q "held by $ID"'
check "task record removed" '[ ! -e "$LAB/state/$ID.meta" ]'
echo; echo "RESULT rc=$RC"
exit $RC
