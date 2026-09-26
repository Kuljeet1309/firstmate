#!/usr/bin/env bash
# Adversarial: a Herdr spawn that fails AFTER its launch was sent into the pane
# (an agent process keeps running there) must roll its record back WITHOUT
# returning the durable lease, and must name the kept lease.
# A stub `claude` (sleep) stands in for the launched agent; the backlog commit
# after launch is made to fail so the spawn rolls its record back.
# Usage: live-abort-live-agent.sh <firstmate-root> <log>
set -u
ROOT=$1
LOG=$2
exec > >(tee "$LOG") 2>&1
HELPER="$ROOT/bin/fm-herdr-lab.sh"
S=$("$HELPER" name abortlive) || exit 1
export HERDR_SESSION=$S
unset HERDR_ENV HERDR_PANE_ID HERDR_SOCKET_PATH
TMP=$(mktemp -d "$(cd /tmp && pwd -P)/fm-live-abort.XXXXXX")
git -C "$TMP" init -q
export TREEHOUSE_ROOT="$TMP/pool"
LAB="$TMP/labhome"
"$ROOT/bin/fm-lab-home.sh" create "$LAB" >/dev/null || exit 1
mkdir -p "$TMP/fakebin"
printf '#!/usr/bin/env bash\nexec sleep 900\n' > "$TMP/fakebin/claude"; chmod +x "$TMP/fakebin/claude"
export PATH="$TMP/fakebin:$PATH"
ID="abortlive$$"
PROJ="$TMP/proj"
lab() { "$HELPER" run "$S" "$@"; }
RC=0
check() { if eval "$2"; then echo "PASS: $1"; else echo "FAIL: $1"; RC=1; fi; }
cleanup() {
  echo "### cleanup"
  (cd "$PROJ" && treehouse return --force "$WT") >/dev/null 2>&1
  "$HELPER" teardown "$S"
  rm -rf /tmp/fm-"$ID" /tmp/fm-"$ID"+* 2>/dev/null
  find "$TMP" -type d -exec chmod u+rwx {} + 2>/dev/null
  rm -rf "$TMP"
}
trap cleanup EXIT
"$HELPER" provision "$S" || exit 1
mkdir -p "$PROJ"; git -C "$PROJ" init -q -b main
echo '# proj' > "$PROJ/README.md"; git -C "$PROJ" add .
git -C "$PROJ" -c user.name=t -c user.email=t@e.invalid commit -qm init
git clone -q --bare "$PROJ" "$TMP/origin.git"; git -C "$PROJ" remote add origin "file://$TMP/origin.git"
mkdir -p "$LAB/data/$ID"
printf "# Task\n## Captain's intent\nHung agent check.\n\n## Firstmate spec\nNothing.\n" > "$LAB/data/$ID/brief.md"
# A real markdown backlog holding the task Queued, and - for the spawn process
# only - a tasks-axi whose `start` (the post-launch move to In flight) fails.
FM_HOME="$LAB" "$ROOT/bin/fm-tasks-axi.sh" add "$ID" "hung agent check" --kind ship >/dev/null || { echo "could not add backlog item"; exit 1; }
REAL_AXI=$(command -v tasks-axi)
mkdir -p "$TMP/axibin"
printf '#!/usr/bin/env bash\nfor a in "$@"; do [ "$a" = start ] && { echo "injected start failure" >&2; exit 1; }; done\nexec %q "$@"\n' "$REAL_AXI" > "$TMP/axibin/tasks-axi"
chmod +x "$TMP/axibin/tasks-axi"
echo "backlog before spawn:"; grep -n "$ID" "$LAB/data/backlog.md"

echo "### spawn whose post-launch backlog commit fails while its agent runs"
START=$(date +%s)
env PATH="$TMP/axibin:$PATH" FM_SPAWN_NO_GUARD=1 FM_HOME="$LAB" "$ROOT/bin/fm-spawn.sh" "$ID" "$PROJ" --harness claude \
  --backend herdr --mode local-only --yolo off > "$TMP/out" 2> "$TMP/err"
echo "fm-spawn exit=$? after $(( $(date +%s) - START ))s"
tail -8 "$TMP/err"
WT=$(sed -n "s/.*Leased worktree at \([^ ]*\)\. Run.*/\1/p" "$TMP/err" | head -1)
echo "pane process:"; lab pane list 2>/dev/null | jq -r ".result.panes[]?.pane_id" | while read -r p; do lab pane process-info --pane "$p" 2>/dev/null | jq -c "{pane:\"$p\", fg:[.result.process_info.foreground_processes[]?.name]}"; done
echo "pool:"; (cd "$PROJ" && treehouse status) 2>/dev/null
echo "lab tabs:"; lab tab list 2>/dev/null | jq -c '.result.tabs[]? | {label,tab_id}'
check "spawn failed" 'grep -q "could not be moved to In flight" "$TMP/err"'
check "task record rolled back" '[ ! -e "$LAB/state/$ID.meta" ]'
check "slot stays leased to the task while its agent may still run" '(cd "$PROJ" && treehouse status) 2>/dev/null | grep -q "held by $ID"'
check "warning names the kept lease and how to release it" 'grep -q "left Treehouse slot .* leased" "$TMP/err" && grep -q "treehouse return --if-lease-holder $ID" "$TMP/err"'
echo "RESULT rc=$RC"
exit $RC
