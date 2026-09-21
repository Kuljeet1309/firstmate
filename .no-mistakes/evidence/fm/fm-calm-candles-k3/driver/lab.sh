#!/usr/bin/env bash
# Live driver for the Calm candles scene in a real Claude Code TUI under a private tmux
# socket, with an isolated project and FM_HOME under /tmp. Mirrors the repo's
# tests/fm-calm-claude-mod-live-e2e.test.sh launch contract.
set -u
WT=/home/user1kuljeet/.no-mistakes/worktrees/36a3c18ea163/01M31TJ7Q4WC0KR3ED9T90P05N
EVID=/home/user1kuljeet/.no-mistakes/evidence/01M31TJ7Q4WC0KR3ED9T90P05N
MOD=${MOD:-$WT/.claude/mods/firstmate-calm}
LAB=${LAB:-/tmp/fm-calm-candles-lab}
PROJECT="$LAB/project"
FM_HOME_DIR="$LAB/fmhome"
SOCKET=${SOCKET:-fm-calm-candles-lab}
SESSION=calm
COLS=${COLS:-160}
ROWS=${ROWS:-44}
PROMPT=${PROMPT:-'Run this exact bash command with the Bash tool: sleep 9; cat notes.txt   Then reply with one short sentence naming the three words.'}

lab_init() {
  rm -rf "$LAB"
  mkdir -p "$PROJECT/.claude/skills" "$FM_HOME_DIR/config"
  ln -s "$MOD" "$PROJECT/.claude/skills/firstmate-calm"
  printf 'alpha\nbeta\ngamma\n' >"$PROJECT/notes.txt"
  printf 'on\n' >"$FM_HOME_DIR/config/calm"
}

unset_inherited() {
  local name
  while IFS= read -r name; do printf -- '-u %s ' "$name"; done \
    < <(env | grep -E '^(CLAUDECODE|CLAUDE_CODE_[A-Z_]+|CLAUDE_CONFIG_DIR)=' | cut -d= -f1 | sort -u)
}

# launch <debug-log> <flag-env-assignment or ''> [claude args...]
launch() {
  local log=$1 flag_env=$2
  shift 2
  tmux -L "$SOCKET" kill-session -t "$SESSION" 2>/dev/null || true
  tmux -L "$SOCKET" new-session -d -s "$SESSION" -x "$COLS" -y "$ROWS" -c "$PROJECT" \
    "env $(unset_inherited) $flag_env FM_HOME='$FM_HOME_DIR' CLAUDE_CODE_ENABLE_PROMPT_SUGGESTION=false CLAUDE_CODE_SEND_FEEDBACK=0 claude --model haiku --dangerously-skip-permissions --settings '{\"feedbackDrafts\":\"off\"}' --debug-file '$log' $*; printf '\nCLAUDE_EXIT=%s\n' \"\$?\"; sleep 60"
}
screen() { tmux -L "$SOCKET" capture-pane -p -t "$SESSION" 2>/dev/null || true; }
screen_ansi() { tmux -L "$SOCKET" capture-pane -e -p -t "$SESSION" 2>/dev/null || true; }
send() { tmux -L "$SOCKET" send-keys -t "$SESSION" -l "$1"; sleep 1; }
enter() { tmux -L "$SOCKET" send-keys -t "$SESSION" Enter; }
dialog_open() { case "$1" in *'trust this folder'*|*'Enter to confirm'*) return 0 ;; esac; return 1; }
answer_trust_dialog() {
  local selected
  case "$1" in *'Yes, I trust this folder'*) : ;; *) return 0 ;; esac
  selected=$(printf '%s\n' "$1" | grep -F '❯' | head -1)
  case "$selected" in *'Yes, I trust this folder'*) enter ;; *) tmux -L "$SOCKET" send-keys -t "$SESSION" Down ;; esac
}
wait_screen() {  # <text> [iterations]
  local text=$1 limit=${2:-400} i=0 shot
  while [ "$i" -lt "$limit" ]; do
    shot=$(screen)
    case "$shot" in *'CLAUDE_EXIT='*) echo "claude exited" >&2; return 1 ;; esac
    if dialog_open "$shot"; then answer_trust_dialog "$shot"; else case "$shot" in *"$text"*) return 0 ;; esac; fi
    sleep 0.25; i=$((i + 1))
  done
  return 1
}
wait_idle() { wait_screen '❯' || return 1; sleep 1; if dialog_open "$(screen)"; then wait_screen '❯'; fi; }
# record <out-file> <seconds>: timestamped ANSI captures of the pane, ~every 50ms.
record() {
  local out=$1 secs=$2 end
  : >"$out"
  end=$(( $(date +%s%N) + $(python3 -c "print(int(float($secs) * 1e9))") ))
  while [ "$(date +%s%N)" -lt "$end" ]; do
    printf '@@FRAME %s\n' "$(date +%s%N)" >>"$out"
    screen_ansi >>"$out"
    sleep 0.05
  done
}
# wait_answer: wait for "gamma" in the settled answer and no working row.
wait_answer() {
  local i=0 shot
  while [ "$i" -lt 600 ]; do
    shot=$(screen)
    case "$shot" in *'gamma'*)
      if ! printf '%s\n' "$shot" | grep -Eq '… \(|esc to interrupt'; then
        if [ -z "$(printf '%s\n' "$shot" | perl -CSD -Mutf8 -ne 'print if /^[ ╷╻╵│╽╹╿┃]+$/ && (() = /[╷╻╵│╽╹╿┃]/g) >= 3')" ]; then
          case "$shot" in *'╲▁▁▁╱'*) ;; *) return 0 ;; esac
        fi
      fi
    ;; esac
    sleep 0.25; i=$((i + 1))
  done
  return 1
}
lab_stop() { tmux -L "$SOCKET" kill-server 2>/dev/null || true; }
