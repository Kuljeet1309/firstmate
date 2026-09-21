#!/usr/bin/env bash
# Evidence driver (not a repo test): a real Claude Code TUI with the Calm mod on,
# under a private tmux socket, exercising what this change alters on screen:
#   1. The crew launch path: the argv prompt is the exact `launch-brief` envelope
#      bin/fm-spawn.sh passes. Claude Code 2.1.277+ strips its U+2063 and sends it at
#      once; the row must reach the transcript mark-less, classify as launch-brief,
#      and draw at zero height while the answer stays visible.
#   2. Captain near misses typed into the composer must stay visible:
#      unknown kind, text before the header, unknown version.
#   3. The exact mark-less current header typed by hand draws at zero height (the
#      accepted consequence of one canonical parser).
# Colored frames are saved with `capture-pane -e` for rendering.
set -u
ROOT=${ROOT:?set ROOT to the worktree}
EV=${EV:?set EV to the evidence dir}
OPINPUT=$ROOT/bin/fm-operational-input.sh
LAB=$(mktemp -d "${TMPDIR:-/tmp}/fm-calm-nearmiss.XXXXXX")
PROJECT=$LAB/project
FMH=$LAB/fmhome
SOCKET=fm-calm-nearmiss-$$
SESSION=calm
SESSION_ID=$(cat /proc/sys/kernel/random/uuid)
mkdir -p "$PROJECT/.claude/skills" "$FMH/config"
ln -s "$ROOT/.claude/mods/firstmate-calm" "$PROJECT/.claude/skills/firstmate-calm"
printf 'on\n' >"$FMH/config/calm"

fail() { printf 'not ok - %s\n' "$1"; exit 1; }
pass() { printf 'ok - %s\n' "$1"; }
cleanup() { tmux -L "$SOCKET" kill-server 2>/dev/null; sleep 1; rm -rf "$LAB"; }
trap cleanup EXIT

screen() { tmux -L "$SOCKET" capture-pane -p -t "$SESSION" 2>/dev/null || true; }
send() { tmux -L "$SOCKET" send-keys -t "$SESSION" -l "$1"; }
enter() { tmux -L "$SOCKET" send-keys -t "$SESSION" Enter; }
composer_text() {
  printf '%s\n' "$1" | awk 'index($0, "────────────────────") == 1 { seg++; next }
    { text[seg] = text[seg] $0 "\n" } END { if (seg > 0) printf "%s", text[seg - 1] }'
}
transcript() { find "$HOME/.claude/projects" -name "$SESSION_ID.jsonl" 2>/dev/null | head -1; }
assistant_said() {  # <token>
  local t
  t=$(transcript)
  [ -n "$t" ] || return 1
  jq -r 'select(.type == "assistant") | .message.content[]? | select(.type == "text") | .text' "$t" | grep -qF "$1"
}
user_row() {  # <token>
  jq -j --arg t "$1" 'select(.type == "user") | .message.content
    | if type == "string" then . else (map(select(.type == "text") | .text) | join("")) end
    | select(contains($t))' "$(transcript)"
}
wait_answer() {  # <token>
  local i=0
  while [ "$i" -lt 240 ]; do
    shot=$(screen)
    case "$shot" in
      *'Yes, I trust this folder'*)
        if printf '%s\n' "$shot" | grep -F '❯' | head -1 | grep -q 'Yes, I trust'; then enter
        else tmux -L "$SOCKET" send-keys -t "$SESSION" Down; fi ;;
    esac
    if assistant_said "$1"; then sleep 2; return 0; fi
    sleep 0.5
    i=$((i + 1))
  done
  screen
  fail "no answer $1"
}
submit() {  # <text>
  local head=${1:0:40} i=0
  send "$1"
  while [ "$i" -lt 40 ]; do
    case "$(composer_text "$(screen)")" in *"$head"*) break ;; esac
    sleep 0.1; i=$((i + 1))
  done
  enter
  i=0
  while [ "$i" -lt 20 ]; do
    sleep 0.5
    case "$(composer_text "$(screen)")" in *"$head"*) enter ;; *) return 0 ;; esac
    i=$((i + 1))
  done
  fail "never submitted: $head"
}

unset_list=$(env | grep -E '^(CLAUDECODE|CLAUDE_CODE_[A-Z_]+|CLAUDE_CONFIG_DIR)=' | cut -d= -f1 | sort -u | sed 's/^/-u /' | tr '\n' ' ')
brief=$(printf '# Task\nLAUNCH_BRIEF_PROBE: this is the crew launch brief. Reply with exactly LAUNCH_OK and nothing else.' | "$OPINPUT" encode launch-brief)
printf '%s' "$brief" >"$LAB/brief"
tmux -L "$SOCKET" new-session -d -s "$SESSION" -x 140 -y 40 -c "$PROJECT" \
  "env $unset_list CLAUDE_CODE_ENABLE_FUNCTION_HOOKS=1 FM_HOME='$FMH' CLAUDE_CODE_ENABLE_PROMPT_SUGGESTION=false CLAUDE_CODE_SEND_FEEDBACK=0 claude --model haiku --dangerously-skip-permissions --session-id $SESSION_ID --settings '{\"feedbackDrafts\":\"off\"}' \"\$(cat '$LAB/brief')\"; sleep 30"
echo "argv launch prompt first bytes: $(head -c 16 "$LAB/brief" | od -An -tx1 | tr -s ' ')"

# 1. argv launch brief: no Enter is ever sent for it.
wait_answer LAUNCH_OK
launch_row=$(user_row LAUNCH_BRIEF_PROBE)
printf 'launch transcript row first bytes: %s\n' "$(printf '%s' "$launch_row" | head -c 16 | od -An -tx1 | tr -s ' ')"
launch_kind=$(printf '%s' "$launch_row" | "$OPINPUT" classify) || launch_kind=none
echo "launch row owner classify: $launch_kind"
[ "$launch_kind" = launch-brief ] || fail "argv launch brief classified as $launch_kind"
shot=$(screen)
tmux -L "$SOCKET" capture-pane -e -p -t "$SESSION" >"$EV/calm-frame-1-launch-brief.ansi"
case "$shot" in *LAUNCH_BRIEF_PROBE*) printf '%s\n' "$shot"; fail "the launch-brief row drew while Calm was on" ;; esac
case "$shot" in *LAUNCH_OK*) : ;; *) printf '%s\n' "$shot"; fail "the launch answer is not visible" ;; esac
pass "argv launch-brief envelope: sent without any Enter, recorded mark-less, classifies launch-brief, row hidden under Calm, answer visible"

# 2. Captain near misses stay visible.
for spec in \
  'NEARMISS_A|FIRSTMATE_OP: v1 not-a-kind: captain-authored text NEARMISS_A. Reply with exactly ACK_A and nothing else.' \
  'NEARMISS_B|Quote: FIRSTMATE_OP: v1 away-supervisor: NEARMISS_B text before the header. Reply with exactly ACK_B and nothing else.' \
  'NEARMISS_C|FIRSTMATE_OP: v2 away-supervisor: NEARMISS_C later version. Reply with exactly ACK_C and nothing else.'; do
  token=${spec%%|*}
  text=${spec#*|}
  ack=ACK_${token#NEARMISS_}
  submit "$text"
  wait_answer "$ack"
  row=$(user_row "$token")
  kind=$(printf '%s' "$row" | "$OPINPUT" classify) || kind=none
  shot=$(screen)
  case "$shot" in
    *"$token"*) pass "captain near miss stays visible under Calm (owner classify: $kind): $text" ;;
    *) printf '%s\n' "$shot"; fail "captain near miss $token was hidden" ;;
  esac
done
tmux -L "$SOCKET" capture-pane -e -p -t "$SESSION" >"$EV/calm-frame-2-near-misses.ansi"

# 3. The exact mark-less header typed by hand is hidden.
submit 'FIRSTMATE_OP: v1 watcher: EXACT_D typed exact header. Reply with exactly ACK_D and nothing else.'
wait_answer ACK_D
kind=$(user_row EXACT_D | "$OPINPUT" classify) || kind=none
shot=$(screen)
tmux -L "$SOCKET" capture-pane -e -p -t "$SESSION" >"$EV/calm-frame-3-exact-header.ansi"
case "$shot" in
  *EXACT_D*) printf '%s\n' "$shot"; fail "the exact mark-less header row drew while Calm was on" ;;
  *ACK_D*) pass "typed exact mark-less header (owner classify: $kind) draws at zero height, answer ACK_D visible" ;;
  *) printf '%s\n' "$shot"; fail "ACK_D not visible" ;;
esac

# 4. /calm off restores every hidden row, including the argv launch brief.
submit '/calm'
i=0
while [ "$i" -lt 60 ]; do
  case "$(screen)" in *EXACT_D*) break ;; esac
  sleep 0.25; i=$((i + 1))
done
sleep 1
shot=$(tmux -L "$SOCKET" capture-pane -p -S -200 -t "$SESSION")
tmux -L "$SOCKET" capture-pane -e -p -t "$SESSION" >"$EV/calm-frame-4-calm-off.ansi"
case "$shot" in
  *LAUNCH_BRIEF_PROBE*EXACT_D*) pass "/calm off restores the hidden launch-brief and exact-header rows" ;;
  *) printf '%s\n' "$shot"; fail "/calm off did not restore the hidden rows" ;;
esac
submit '/calm'
sleep 2
echo "final preference: $(cat "$FMH/config/calm")"
