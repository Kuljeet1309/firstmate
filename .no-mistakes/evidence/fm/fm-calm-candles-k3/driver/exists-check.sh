#!/usr/bin/env bash
# Live check of the $.fs.exists-first config read: the Calm mod, flag on, in a real
# Claude Code TUI, for a home with no config/calm-scene (boat) and a first-run home with
# neither config/calm nor config/calm-scene. Records the debug log's firstmate-calm
# WARN/ERROR lines and the working-row frames. exists-check.sh <no-scene|first-run>
. /home/user1kuljeet/.no-mistakes/evidence/01M31TJ7Q4WC0KR3ED9T90P05N/driver/lab.sh
LAB=/tmp/fm-calm-exists-lab; PROJECT="$LAB/project"; FM_HOME_DIR="$LAB/fmhome"; SOCKET=fm-calm-exists-lab
name=exists-$1; E=$EVID/$name; rm -rf "$E"; mkdir -p "$E"
trap 'lab_stop; rm -rf "$LAB"' EXIT
note() { printf '%s\n' "$*" | tee -a "$E/transcript.txt"; }
lab_init
[ "$1" = first-run ] && rm -f "$FM_HOME_DIR/config/calm"
note "mod: $(git -C "$WT" rev-parse --short HEAD) + uncommitted exists-first read; config dir: $(ls -A "$FM_HOME_DIR/config" | tr '\n' ' ')"
launch "$LAB/debug.log" CLAUDE_CODE_ENABLE_FUNCTION_HOOKS=1; wait_idle
send "$PROMPT"; enter
i=0
while [ "$i" -lt 200 ]; do
  case "$(screen)" in *'… ('*|*'╲▁▁▁╱'*) break ;; esac
  sleep 0.1; i=$((i + 1))
done
record "$E/frames.ansi" 3
screen >"$E/working-screen.txt"
if grep -q '╲▁▁▁╱' "$E/frames.ansi"; then note "working row: Calm boat hull drawn"; fi
if grep -q '… (' "$E/working-screen.txt"; then note "working row: stock spinner"; fi
if wait_answer; then note "settled: answer shown, working row gone"; else note "NOT SETTLED"; fi
screen >"$E/settled-screen.txt"
note "hooks module line: $(grep -Eo 'hooks module firstmate-calm[^ ]* loaded' "$LAB/debug.log" | head -1)"
grep -E '\[(WARN|ERROR)\].*firstmate-calm' "$LAB/debug.log" >"$E/debug-warn-error.txt" || true
grep -Ec "ENOENT.*$FM_HOME_DIR/config/calm" "$LAB/debug.log" | sed 's/^/ENOENT lines naming the Calm config files of the home: /' | tee -a "$E/transcript.txt"
note "firstmate-calm WARN/ERROR lines:"; cat "$E/debug-warn-error.txt" | tee -a "$E/transcript.txt"
send '/exit'; enter; sleep 2
