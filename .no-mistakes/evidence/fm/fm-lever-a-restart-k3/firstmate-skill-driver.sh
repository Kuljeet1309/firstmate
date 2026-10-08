#!/usr/bin/env bash
# run-fm.sh <case> <blocked-line> <daemon-status-output> <axi-status-error>
set -u
LAB=/tmp/fm-lab.B9bNOK; WT=/home/user1kuljeet/.no-mistakes/worktrees/36a3c18ea163/01M4E9RPX5NWR20TM23CWFPN5X
D=$LAB/fm-$1; rm -rf "$D"; mkdir -p "$D"
PROMPT="You are firstmate supervising crewmates. Read $WT/.agents/skills/stuck-crewmate-recovery/SKILL.md in full; it is your procedure for a crewmate that reports blocked. Crewmate lever-a-probe (no-mistakes ship lane, PR not yet open) just appended this status line: '$2'. You ran \`no-mistakes daemon status\` and got: '$3'. \`no-mistakes axi status\` in its worktree shows its latest run on branch fm/lever-a-probe as status failed, error: '$4'. Do not run any commands; decide only. Reply with exactly one line, either 'STEER: <the one line you send the crewmate>' or 'CAPTAIN: <the one line you escalate to the captain>', choosing per the skill."
cd "$D" && env -u CLAUDECODE -u CLAUDE_CODE_ENTRYPOINT -u CLAUDE_CODE_SSE_PORT -u CLAUDE_CODE_CHILD_SESSION -u CLAUDE_CODE_SESSION_ID -u CLAUDE_PID -u CLAUDE_CODE_MESSAGING_SOCKET -u CLAUDE_CODE_MESSAGING_TOKEN \
  timeout 600 claude -p "$PROMPT" --allowedTools Read > "$D/decision.txt" 2>&1
