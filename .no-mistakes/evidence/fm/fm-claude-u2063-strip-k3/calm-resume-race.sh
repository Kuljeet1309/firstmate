#!/usr/bin/env bash
# Evidence driver (not a repo test): repeat `claude --continue` with the Calm mod on
# and record, at fixed offsets after the restored transcript first shows, whether
# rows Calm hides (a tool row and a mark-less operational row) are drawn, and when
# the debug log reports the hooks module loaded.
set -u
ROOT=${ROOT:?}
RUNS=${RUNS:-6}
OPINPUT=$ROOT/bin/fm-operational-input.sh
LAB=$(mktemp -d "${TMPDIR:-/tmp}/fm-calm-resume.XXXXXX")
PROJECT=$LAB/project
FMH=$LAB/fmhome
SOCKET=fm-calm-resume-$$
SESSION=calm
mkdir -p "$PROJECT/.claude/skills" "$FMH/config"
ln -s "$ROOT/.claude/mods/firstmate-calm" "$PROJECT/.claude/skills/firstmate-calm"
printf 'alpha\nbeta\ngamma\n' >"$PROJECT/notes.txt"
printf 'on\n' >"$FMH/config/calm"
cleanup() { tmux -L "$SOCKET" kill-server 2>/dev/null; sleep 1; rm -rf "$LAB"; }
trap cleanup EXIT
screen() { tmux -L "$SOCKET" capture-pane -p -t "$SESSION" 2>/dev/null || true; }
enter() { tmux -L "$SOCKET" send-keys -t "$SESSION" Enter; }
unset_list=$(env | grep -E '^(CLAUDECODE|CLAUDE_CODE_[A-Z_]+|CLAUDE_CONFIG_DIR)=' | cut -d= -f1 | sort -u | sed 's/^/-u /' | tr '\n' ' ')
launch() {  # <debug-log> [args...]
  local log=$1
  shift
  tmux -L "$SOCKET" kill-session -t "$SESSION" 2>/dev/null
  tmux -L "$SOCKET" new-session -d -s "$SESSION" -x 160 -y 44 -c "$PROJECT" \
    "env $unset_list CLAUDE_CODE_ENABLE_FUNCTION_HOOKS=1 FM_HOME='$FMH' CLAUDE_CODE_ENABLE_PROMPT_SUGGESTION=false CLAUDE_CODE_SEND_FEEDBACK=0 claude --model haiku --dangerously-skip-permissions --settings '{\"feedbackDrafts\":\"off\"}' --debug-file '$log' $*; sleep 30"
}
wait_for() {  # <text> <limit>
  local i=0 shot
  while [ "$i" -lt "$2" ]; do
    shot=$(screen)
    case "$shot" in
      *'Yes, I trust this folder'*)
        if printf '%s\n' "$shot" | grep -F '❯' | head -1 | grep -q 'Yes, I trust'; then enter
        else tmux -L "$SOCKET" send-keys -t "$SESSION" Down; fi ;;
      *"$1"*) return 0 ;;
    esac
    sleep 0.1
    i=$((i + 1))
  done
  return 1
}

# Seed: an argv launch brief that makes one tool call, so the transcript holds a
# mark-less operational row and a tool row.
brief=$(printf 'SEED_PROBE: run this exact bash command with the Bash tool: cat notes.txt   Then reply with one short sentence naming the three words.' | "$OPINPUT" encode launch-brief)
printf '%s' "$brief" >"$LAB/brief"
launch "$LAB/seed.log" "\"\$(cat '$LAB/brief')\""
wait_for 'gamma' 900 || { screen; echo "seed never answered"; exit 1; }
sleep 3
tmux -L "$SOCKET" send-keys -t "$SESSION" -l '/exit'; sleep 0.5; enter; sleep 3

for run in $(seq 1 "$RUNS"); do
  log=$LAB/resume-$run.log
  : >"$log"
  t0=$(date +%s.%N)
  launch "$log" --continue
  wait_for 'gamma' 400 || { echo "run $run: resumed transcript never showed"; continue; }
  t_show=$(date +%s.%N)
  line="run $run:"
  for off in 0 0.5 1 2 4; do
    target=$(echo "$t_show + $off" | bc)
    now=$(date +%s.%N)
    d=$(echo "$target - $now" | bc)
    case "$d" in -*|0) ;; *) sleep "$d" ;; esac
    shot=$(screen)
    drawn=''
    case "$shot" in *'shell command'*|*'Bash('*) drawn="${drawn}tool," ;; esac
    case "$shot" in *SEED_PROBE*) drawn="${drawn}op," ;; esac
    line="$line  +${off}s:[${drawn:-hidden}]"
  done
  loaded=$(grep -m1 -E 'hooks module firstmate-calm(@[^ ]+)? loaded' "$log" | cut -c1-24)
  printf '%s  transcript shown after %.1fs; module-loaded log line: %s\n' "$line" "$(echo "$t_show - $t0" | bc)" "${loaded:-NONE}"
  tmux -L "$SOCKET" send-keys -t "$SESSION" -l '/exit'; sleep 0.5; enter; sleep 3
done
