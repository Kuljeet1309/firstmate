#!/usr/bin/env bash
# run-scn.sh <scn> <err>: drive one real Claude worker through a daemon-cut scenario
set -u
LAB=/tmp/fm-lab.B9bNOK; SCN=$1; ERR=$2; D=$LAB/scn-$SCN; rm -rf "$D"; mkdir -p "$D/wt"
git -C "$D/wt" init -q -b main; git -C "$D/wt" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
git -C "$D/wt" checkout -q -b fm/lever-a-probe; echo hello > "$D/wt/README.md"; git -C "$D/wt" add .; git -C "$D/wt" -c user.email=t@t -c user.name=t commit -q -m "docs: add greeting"
STATUS=$LAB/state/lever-a-probe.status
sed -e "s#{TASK}#Add a one-line greeting to the README.#" \
    -e "s#{FIRSTMATE_SPEC}#Write the greeting in README.md.#" \
    -e "s#/tmp/fm-lab.B9bNOK/state/lever-a-probe.status#$D/status#g" \
    "$LAB/data/lever-a-probe/brief.md" > "$D/brief.md"
: > "$D/status"; : > "$D/calls.log"
PROMPT="You are the crewmate for this brief: $D/brief.md - read it in full first. Your worktree is $D/wt (already on branch fm/lever-a-probe with the greeting committed; skip Setup). Earlier you appended done, firstmate told you to run /no-mistakes, and you started \`no-mistakes axi run --intent 'Add a one-line greeting to the README.'\` backgrounded. That backgrounded drive call has just returned with: error: lost connection to daemon (EOF). Continue the task now, following the brief exactly. Use the no-mistakes and gh-axi CLIs directly (do not load the /no-mistakes skill). No drive call here takes more than a few seconds, so run them in the foreground. End your turn whenever the brief tells you to stop."
cd "$D/wt"
env -u CLAUDECODE -u CLAUDE_CODE_ENTRYPOINT -u CLAUDE_CODE_SSE_PORT -u CLAUDE_CODE_CHILD_SESSION -u CLAUDE_CODE_SESSION_ID -u CLAUDE_PID -u CLAUDE_CODE_MESSAGING_SOCKET -u CLAUDE_CODE_MESSAGING_TOKEN -u NO_MISTAKES_GATE \
  PATH="$LAB/fakebin:$PATH" SCN_DIR="$D" SCN="$SCN" ERR="$ERR" \
  timeout 900 claude -p "$PROMPT" --dangerously-skip-permissions --output-format text > "$D/transcript.txt" 2>&1
echo "exit=$?" >> "$D/transcript.txt"
