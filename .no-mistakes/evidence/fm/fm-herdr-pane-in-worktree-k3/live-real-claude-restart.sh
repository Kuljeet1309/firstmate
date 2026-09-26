#!/usr/bin/env bash
# Live real-Claude proof for the Herdr pane-in-worktree fix.
# Spawns a REAL Claude Code worker through bin/fm-spawn.sh into a private
# fm-lab-* Herdr session, restarts that session, relaunches through
# bin/fm-control.sh, restarts again, and records where Claude comes back.
# Usage: ROOT=<worktree> live-real-claude-restart.sh
set -u
ROOT=${ROOT:?}
H="$ROOT/bin/fm-herdr-lab.sh"
say() { printf '%s\n' "$*"; }
fail() { say "FAIL - $*"; exit 1; }
ok() { say "PASS - $*"; }

TMP_ROOT=$(mktemp -d "${TMPDIR:?}/fm-live-claude.XXXXXX"); TMP_ROOT=$(cd "$TMP_ROOT" && pwd -P)
git -C "$TMP_ROOT" init -q
export TREEHOUSE_ROOT="$TMP_ROOT/pool"
SES=$("$H" name live-claude) || exit 1
export HERDR_SESSION="$SES"
ID="lvclaude$$"
PROJ="$TMP_ROOT/proj"
HOME_FM="$TMP_ROOT/fm-home"
cleanup() {
  local wt
  wt=$(sed -n 's/^worktree=//p' "$HOME_FM/state/$ID.meta" 2>/dev/null | tail -1)
  [ -z "$wt" ] || (cd "$PROJ" && treehouse return --force "$wt") >/dev/null 2>&1
  "$H" teardown "$SES"; say "teardown exit=$?"
  rm -rf "/tmp/fm-$ID" /tmp/fm-"$ID"+*
  find "$TMP_ROOT" -type d -exec chmod u+rwx {} + 2>/dev/null; rm -rf "$TMP_ROOT"
}
trap cleanup EXIT
"$H" provision "$SES" >/dev/null || fail "provision"
lab() { "$H" run "$SES" "$@"; }
SESSION_FILE=$(lab session list --json | jq -r --arg s "$SES" '.sessions[]|select(.name==$s)|.session_dir')/session.json

mkdir -p "$PROJ"; git -C "$PROJ" init -q; echo '# proj' > "$PROJ/README.md"
git -C "$PROJ" add README.md; git -C "$PROJ" -c user.name=t -c user.email=t@e.invalid commit -qm init
git clone -q --bare "$PROJ" "$TMP_ROOT/proj.git"; git -C "$PROJ" remote add origin "file://$TMP_ROOT/proj.git"
PROJ_REAL=$(cd "$PROJ" && pwd -P)
mkdir -p "$HOME_FM/state" "$HOME_FM/config" "$HOME_FM/data/$ID"
echo off > "$HOME_FM/config/herdr-presentation-spaces"
cat > "$HOME_FM/data/$ID/brief.md" <<EOF
# Task
## Captain's intent
This is a harness restart test. Reply with the single word READY-$ID and then stop.

## Firstmate spec
Do not run any tools, commands, or edits. Only reply READY-$ID.
EOF

meta() { sed -n "s/^$1=//p" "$HOME_FM/state/$ID.meta" | tail -1; }
pane_json() { lab pane get "$1" 2>/dev/null; }
claude_pid() { lab pane process-info --pane "$1" 2>/dev/null | jq -r '.result.process_info.foreground_processes[]? | select(.name=="claude" or (.argv0//""|test("claude"))) | .pid' | head -1; }
agent_sess() { lab agent get "$1" 2>/dev/null | jq -r '.result.agent.agent_session.value // empty'; }
wait_for() { local n=$1; shift; for _ in $(seq 1 "$n"); do "$@" && return 0; sleep 1; done; return 1; }
screen() { lab pane read "$1" --source visible 2>/dev/null | jq -r '.result.read.text // .result.text // .' 2>/dev/null || lab pane read "$1" --source visible; }

say "== 1. fresh spawn of a real Claude worker (herdr backend, flat) =="
env -u HERDR_ENV -u HERDR_PANE_ID -u HERDR_SOCKET_PATH FM_SPAWN_NO_GUARD=1 FM_HOME="$HOME_FM" FM_ROOT_OVERRIDE="$ROOT" \
  "$ROOT/bin/fm-spawn.sh" "$ID" "$PROJ" --harness claude --model haiku --backend herdr --mode local-only --yolo off \
  > "$TMP_ROOT/spawn.out" 2>&1 || { cat "$TMP_ROOT/spawn.out"; fail "spawn"; }
WT=$(cd "$(meta worktree)" && pwd -P); P1=$(meta herdr_pane_id)
say "primary checkout: $PROJ_REAL"; say "task worktree:    $WT"; say "task pane:        $P1"
say "treehouse lease:  $( (cd "$PROJ" && treehouse status --json) | jq -c --arg id "$ID" '.[]|select(.lease_holder==$id)|{path,lease_holder}')"
say "herdr pane cwd:   $(pane_json "$P1" | jq -r .result.pane.cwd)"
[ "$(pane_json "$P1" | jq -r .result.pane.cwd)" = "$WT" ] || fail "pane not created in worktree"
wait_for 90 test -n "$(agent_sess "$P1")" || { screen "$P1"; fail "claude never reported a session"; }
S1=$(agent_sess "$P1"); say "claude session reported to herdr: $S1"
wait_for 90 bash -c "lab() { \"$H\" run \"$SES\" \"\$@\"; }; lab pane read $P1 --source recent 2>/dev/null | grep -q 'READY-$ID'" || say "(READY reply not seen yet)"
pid=$(claude_pid "$P1"); say "claude pid=$pid cwd=$(readlink /proc/$pid/cwd 2>/dev/null) cmd=$(tr '\0' ' ' < /proc/$pid/cmdline 2>/dev/null | cut -c1-120)"
ok "fresh real-Claude worker's pane is created in its leased worktree"
wait_for 90 test "$(jq -r --arg d "$WT" '[.workspaces[].tabs[].panes[]|select(.cwd==$d)|.agent_session.value]|join(",")' "$SESSION_FILE")" = "$S1" \
  || fail "herdr did not save pane at worktree with $S1: $(jq -c '[.workspaces[].tabs[].panes[]|{cwd,s:.agent_session.value}]' "$SESSION_FILE")"
say "herdr saved: $(jq -c '[.workspaces[].tabs[].panes[]|{cwd,agent_session:.agent_session.value}]' "$SESSION_FILE")"

say "== 2. herdr server restart =="
"$H" stop "$SES" >/dev/null || fail stop; "$H" provision "$SES" >/dev/null || fail reprovision
wait_for 60 test -n "$(claude_pid "$P1")" || fail "claude not restored in $P1"
pid=$(claude_pid "$P1"); cwd=$(readlink /proc/$pid/cwd); cmd=$(tr '\0' ' ' < /proc/$pid/cmdline)
say "restored claude pid=$pid cwd=$cwd"; say "restored claude cmd: $cmd"
[ "$cwd" = "$WT" ] || fail "restored claude runs in $cwd, not worktree"
case "$cmd" in *"--resume $S1"*) ;; *) fail "restored claude did not resume $S1";; esac
wait_for 60 bash -c "\"$H\" run \"$SES\" pane read $P1 --source recent 2>/dev/null | grep -q 'READY-$ID'" && say "restored screen shows the prior READY-$ID reply" || say "(prior reply not visible on restored screen)"
lab pane read "$P1" --source visible --format text > "$OUT_DIR/live-claude-restore1-screen.txt" 2>&1
ok "after a herdr restart the real Claude worker resumes its own conversation in the worktree (not $PROJ_REAL)"

say "== 3. fm-control relaunch, then restart =="
env -u HERDR_ENV -u HERDR_PANE_ID -u HERDR_SOCKET_PATH FM_SPAWN_NO_GUARD=1 FM_HOME="$HOME_FM" FM_ROOT_OVERRIDE="$ROOT" \
  "$ROOT/bin/fm-control.sh" "$ID" relaunch --harness claude --model haiku --note "live restart test relaunch" > "$TMP_ROOT/relaunch.out" 2>&1
rc=$?; cat "$TMP_ROOT/relaunch.out"; [ $rc = 0 ] || fail "fm-control relaunch rc=$rc"
P2=$(meta herdr_pane_id); say "replacement pane: $P2 (old $P1)"
[ "$P2" != "$P1" ] || fail "relaunch reused the pane"
say "old pane lookup: $(lab pane get "$P1" 2>&1 | jq -r '.error.code // "still-present"')"
say "replacement pane cwd: $(pane_json "$P2" | jq -r .result.pane.cwd)"
[ "$(pane_json "$P2" | jq -r .result.pane.cwd)" = "$WT" ] || fail "replacement pane not created in worktree"
wait_for 120 bash -c "s=\$(\"$H\" run \"$SES\" agent get $P2 2>/dev/null | jq -r '.result.agent.agent_session.value // empty'); [ -n \"\$s\" ] && [ \"\$s\" != '$S1' ]" || fail "replacement claude never reported a new session"
S2=$(agent_sess "$P2"); say "replacement claude session: $S2"
ok "fm-control relaunch replaces the pane with one created in the worktree"
wait_for 90 test "$(jq -r --arg d "$WT" '[.workspaces[].tabs[].panes[]|select(.cwd==$d)|.agent_session.value]|join(",")' "$SESSION_FILE")" = "$S2" \
  || fail "herdr saved $(jq -c '[.workspaces[].tabs[].panes[]|{cwd,s:.agent_session.value}]' "$SESSION_FILE")"
say "herdr saved: $(jq -c '[.workspaces[].tabs[].panes[]|{cwd,agent_session:.agent_session.value}]' "$SESSION_FILE")"
"$H" stop "$SES" >/dev/null || fail stop2; "$H" provision "$SES" >/dev/null || fail reprovision2
wait_for 60 test -n "$(claude_pid "$P2")" || fail "claude not restored in $P2"
pid=$(claude_pid "$P2"); cwd=$(readlink /proc/$pid/cwd); cmd=$(tr '\0' ' ' < /proc/$pid/cmdline)
say "restored claude pid=$pid cwd=$cwd"; say "restored claude cmd: $cmd"
[ "$cwd" = "$WT" ] || fail "restored relaunched claude in $cwd"
case "$cmd" in *"--resume $S2"*) ;; *) fail "did not resume replacement session $S2";; esac
case "$cmd" in *"$S1"*) fail "resumed pre-relaunch conversation";; esac
sleep 5; lab pane read "$P2" --source visible --format text > "$OUT_DIR/live-claude-restore2-screen.txt" 2>&1
ok "after relaunch + restart, Claude resumes the replacement conversation ($S2), not $S1, in the worktree"
