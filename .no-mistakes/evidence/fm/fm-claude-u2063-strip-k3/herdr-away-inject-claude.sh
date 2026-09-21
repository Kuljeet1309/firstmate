#!/usr/bin/env bash
# Evidence driver (not a repo test): the away-mode daemon's real inject_msg
# delivering an escalation into a real Claude Code pane hosted in an isolated,
# named, non-default Herdr lab session (bin/fm-herdr-lab.sh prepare/provision/
# run/teardown). Every Herdr call, including the daemon adapter's, is routed
# through the lab helper's run command by a PATH wrapper, exactly as
# tests/fm-herdr-submit-confirm-live-e2e.test.sh does.
#
# Proves, on the installed Claude Code: the daemon confirms delivery although
# Claude Code 2.1.277+ strips U+2063 and holds the first Enter, the model
# answers, and the transcript row classifies as away-supervisor through the
# canonical owner.
set -u
ROOT=${ROOT:?set ROOT to the worktree}
EV=${EV:?set EV to the evidence dir}
LAB_HELPER=$ROOT/bin/fm-herdr-lab.sh
# shellcheck source=/dev/null
. "$ROOT/tests/herdr-test-safety.sh"
herdr_forget_inherited_pane

fail() { printf 'not ok - %s\n' "$1"; exit 1; }
pass() { printf 'ok - %s\n' "$1"; }

ORIGINAL_PATH=$PATH
SESSION=$("$LAB_HELPER" name away-claude)
TMP=$(mktemp -d "${TMPDIR:-/tmp}/fm-away-herdr-claude.XXXXXX")
PROJECT=$TMP/project
FMH=$TMP/fmhome
FAKEBIN=$TMP/fakebin
mkdir -p "$PROJECT" "$FMH/state" "$FAKEBIN"
printf 'alpha\n' >"$PROJECT/notes.txt"
SESSION_ID=$(cat /proc/sys/kernel/random/uuid)
POLLER=

cleanup() {
  local rc=$?
  trap - EXIT
  [ -n "$POLLER" ] && kill "$POLLER" 2>/dev/null
  if ! PATH="$ORIGINAL_PATH" "$LAB_HELPER" teardown "$SESSION"; then
    echo "teardown of $SESSION FAILED"
    rc=1
  else
    echo "teardown of $SESSION ok (default-session tripwire unchanged)"
  fi
  rm -rf "$TMP"
  exit "$rc"
}
trap cleanup EXIT

cat >"$FAKEBIN/herdr" <<EOF
#!/usr/bin/env bash
set -u
args=("\$@")
n=\${#args[@]}
if [ "\$n" -ge 2 ] && [ "\${args[\$((n-2))]}" = --session ]; then
  [ "\${args[\$((n-1))]}" = "$SESSION" ] || { echo "wrapper refused foreign session" >&2; exit 97; }
  args=("\${args[@]:0:\$((n-2))}")
else
  echo "wrapper requires trailing --session $SESSION" >&2
  exit 98
fi
exec env PATH="$ORIGINAL_PATH" "$LAB_HELPER" run "$SESSION" "\${args[@]}"
EOF
chmod +x "$FAKEBIN/herdr"

"$LAB_HELPER" provision "$SESSION" || fail "could not provision the Herdr lab"
echo "lab session: $SESSION"
lab() { env PATH="$ORIGINAL_PATH" "$LAB_HELPER" run "$SESSION" "$@"; }
read_pane() { lab pane read "$PANE" --source visible 2>/dev/null || true; }

WS_JSON=$(lab workspace create --cwd "$PROJECT" --label fm-awaylive --no-focus) || fail "workspace create failed"
PANE=$(printf '%s' "$WS_JSON" | jq -er '.result.root_pane.pane_id') || fail "no pane id"
TARGET="$SESSION:$PANE"
VERSION=$(claude --version 2>/dev/null | head -1)
HERDR_VER=$(herdr --version 2>/dev/null | head -1)
unset_list=$(env | grep -E '^(CLAUDECODE|CLAUDE_CODE_[A-Z_]+|CLAUDE_CONFIG_DIR)=' | cut -d= -f1 | sort -u | sed 's/^/-u /' | tr '\n' ' ')
lab pane run "$PANE" "env $unset_list CLAUDE_CODE_ENABLE_PROMPT_SUGGESTION=false CLAUDE_CODE_SEND_FEEDBACK=0 claude --model haiku --dangerously-skip-permissions --session-id $SESSION_ID --settings '{\"feedbackDrafts\":\"off\"}'" >/dev/null \
  || fail "could not launch Claude Code in the lab pane"

# Answer the folder-trust dialog, then wait for a registered idle agent.
i=0
idle=0
while [ "$i" -lt 90 ]; do
  shot=$(read_pane)
  case "$shot" in
    *'Yes, I trust this folder'*)
      if printf '%s\n' "$shot" | grep -F '❯' | head -1 | grep -q 'Yes, I trust'; then
        lab pane send-keys "$PANE" enter >/dev/null
      else
        lab pane send-keys "$PANE" down >/dev/null
      fi
      sleep 1; i=$((i + 1)); continue ;;
  esac
  st=$(lab agent get "$PANE" 2>/dev/null | jq -r '.result.agent.agent_status // empty')
  case "$st" in idle|done) case "$shot" in *'❯'*) idle=1; break ;; esac ;; esac
  sleep 1
  i=$((i + 1))
done
[ "$idle" = 1 ] || { read_pane; fail "Claude Code ($VERSION) never reached an idle composer in the lab pane"; }
sleep 2

# Frame poller: records every distinct visible frame while the daemon delivers.
: >"$TMP/frames.txt"
(
  while :; do
    printf '=== %s\n' "$(date +%T.%N | cut -c1-12)" >>"$TMP/frames.txt"
    lab pane read "$PANE" --source visible 2>/dev/null | tail -8 >>"$TMP/frames.txt"
    sleep 0.15
  done
) &
POLLER=$!

start=$(date +%s.%N)
(
  export PATH="$FAKEBIN:$ORIGINAL_PATH" FM_HOME="$FMH" FM_SUPERVISOR_TARGET="$TARGET" FM_SUPERVISOR_BACKEND=herdr HERDR_SESSION="$SESSION" LOG="$TMP/daemon.log"
  # shellcheck source=/dev/null
  . "$ROOT/bin/fm-supervise-daemon.sh"
  afk_enter "$FMH/state"
  inject_msg 'Supervisor escalate (1 event(s)): AWAY_HERDR_PROBE escalation. Reply with exactly AWAY_HERDR_OK and nothing else.' "$FMH/state"
)
inject_rc=$?
end=$(date +%s.%N)
sleep 1
kill "$POLLER" 2>/dev/null; POLLER=
printf 'inject_msg rc=%s after %.2fs (FM_SUPERVISOR_BACKEND=herdr, target %s)\n' "$inject_rc" "$(echo "$end - $start" | bc)" "$TARGET"
echo '--- daemon log'
cat "$TMP/daemon.log" 2>/dev/null || echo '(empty: no deferral or failure logged)'
echo '--- hold hint frames seen during delivery'
grep -c 'invisible character' "$TMP/frames.txt" | sed 's/^/frames showing the strip hint: /'
grep -m1 -B1 -A1 'invisible character' "$TMP/frames.txt" || true
cp "$TMP/frames.txt" "$EV/herdr-away-inject-frames.txt"
[ "$inject_rc" = 0 ] || fail "the daemon did not confirm delivery into Claude Code ($VERSION) on $HERDR_VER"

transcript() { find "$HOME/.claude/projects" -name "$SESSION_ID.jsonl" 2>/dev/null | head -1; }
i=0
answered=''
while [ "$i" -lt 90 ]; do
  t=$(transcript)
  if [ -n "$t" ]; then
    answered=$(jq -r 'select(.type == "assistant") | .message.content[]? | select(.type == "text") | .text' "$t" | grep -F AWAY_HERDR_OK || true)
    [ -n "$answered" ] && break
  fi
  sleep 1
  i=$((i + 1))
done
echo '--- final visible pane'
read_pane | tail -14
[ -n "$answered" ] || fail "Claude Code never answered the delivered escalation"
row=$(jq -j 'select(.type == "user") | .message.content | if type == "string" then . else (map(select(.type == "text") | .text) | join("")) end | select(contains("AWAY_HERDR_PROBE"))' "$(transcript)")
echo '--- transcript user row (hex of first 20 bytes, then text)'
printf '%s' "$row" | head -c 20 | od -An -tx1
printf '%s\n' "$row"
kind=$(printf '%s' "$row" | "$ROOT/bin/fm-operational-input.sh" classify) || kind=none
echo "owner classify: $kind"
case "$row" in $'\xE2\x81\xA3'*) mark='with' ;; *) mark='without' ;; esac
[ "$kind" = away-supervisor ] || fail "the delivered row classified as $kind"
pass "Herdr ($HERDR_VER) lab $SESSION: the daemon's inject_msg confirmed delivery into Claude Code ($VERSION), the model answered AWAY_HERDR_OK, and the transcript row arrived $mark its U+2063 mark and classifies as away-supervisor"
