#!/usr/bin/env bash
# Scenario runner: scenarios.sh <name>. Each writes into $EVID/<name>/.
. /home/user1kuljeet/.no-mistakes/evidence/01M31TJ7Q4WC0KR3ED9T90P05N/driver/lab.sh
A=/home/user1kuljeet/.no-mistakes/evidence/01M31TJ7Q4WC0KR3ED9T90P05N/driver/analyze.py
name=$1; E=$EVID/$name; rm -rf "$E"; mkdir -p "$E"
trap lab_stop EXIT
note() { printf '%s\n' "$*" | tee -a "$E/transcript.txt"; }
turn_and_record() {  # <secs> : send the prompt, wait for the working row, record
  send "$PROMPT"; enter
  local i=0
  while [ "$i" -lt 200 ]; do
    case "$(screen)" in *'… ('*|*'╲▁▁▁╱'*|*'┃'*|*'╽'*|*'╿'*|*'╻'*|*'╹'*) break ;; esac
    sleep 0.1; i=$((i + 1))
  done
  record "$E/frames.ansi" "$1"
  screen >"$E/working-screen.txt"
  screen_ansi >"$E/working-screen.ansi"
}
settle() {
  if wait_answer; then note "settled: answer shown, no working row, no candles, no boat"; else note "NOT SETTLED"; fi
  screen >"$E/settled-screen.txt"
}
debug_errors() { grep -E '\[(WARN|ERROR)\].*firstmate-calm' "$LAB/debug.log" >"$E/debug-warn-error.txt" || true; }
case "$name" in
  candles-dark)
    lab_init; printf 'candles\n' >"$FM_HOME_DIR/config/calm-scene"
    launch "$LAB/debug.log" CLAUDE_CODE_ENABLE_FUNCTION_HOOKS=1; wait_idle
    turn_and_record 7; settle; debug_errors
    python3 "$A" "$E/frames.ansi" "$COLS" --palette dark --html "$E/candles-dark.html" --title "Calm candles scene, Claude Code $(claude --version), dark theme, ${COLS}x${ROWS}" >"$E/analysis.json"
    ;;
  candles-light)
    lab_init; printf 'candles\n' >"$FM_HOME_DIR/config/calm-scene"
    launch "$LAB/debug.log" CLAUDE_CODE_ENABLE_FUNCTION_HOOKS=1 --settings "'{\"theme\":\"light\",\"feedbackDrafts\":\"off\"}'"; wait_idle
    turn_and_record 4; settle; debug_errors
    python3 "$A" "$E/frames.ansi" "$COLS" --palette light --html "$E/candles-light.html" --title "Calm candles scene, light theme" >"$E/analysis.json"
    ;;
  boat-default)
    lab_init
    launch "$LAB/debug.log" CLAUDE_CODE_ENABLE_FUNCTION_HOOKS=1; wait_idle
    turn_and_record 7; settle; debug_errors
    ;;
  scene-value)  # SCENE_VALUE env holds the file content (printf %b)
    lab_init; printf '%b' "$SCENE_VALUE" >"$FM_HOME_DIR/config/calm-scene"
    note "config/calm-scene bytes: $(od -c "$FM_HOME_DIR/config/calm-scene" | head -2 | tr -s ' ' | tr '\n' ' ')"
    launch "$LAB/debug.log" CLAUDE_CODE_ENABLE_FUNCTION_HOOKS=1; wait_idle
    turn_and_record 3; settle
    if grep -q '╲▁▁▁╱' "$E/frames.ansi"; then note "boat hull drawn"; fi
    python3 "$A" "$E/frames.ansi" "$COLS" --palette dark >"$E/analysis.json"
    ;;
  flag)  # FLAG env: '' (unset) or a value
    lab_init; printf 'candles\n' >"$FM_HOME_DIR/config/calm-scene"
    fe=''; [ -n "${FLAG:-}" ] && fe="CLAUDE_CODE_ENABLE_FUNCTION_HOOKS=$FLAG"
    note "flag env: '${fe:-<unset>}', preference on, scene candles"
    launch "$LAB/debug.log" "$fe"; wait_idle
    turn_and_record 3; settle
    grep -Eo 'hooks module[s]? [a-z@ -]{0,60}' "$LAB/debug.log" | sort -u >"$E/debug-hooks.txt" || true
    python3 "$A" "$E/frames.ansi" "$COLS" --palette dark >"$E/analysis.json"
    ;;
esac
send '/exit'; enter; sleep 2
