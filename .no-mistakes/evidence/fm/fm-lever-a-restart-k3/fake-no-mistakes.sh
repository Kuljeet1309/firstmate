#!/usr/bin/env bash
# Disposable stand-in for the shared daemon CLI, scripted per scenario.
D=${SCN_DIR:?}; S=${SCN:?}
echo "$(date +%s) no-mistakes $*" >> "$D/calls.log"
BR=fm/lever-a-probe; HEAD=$(git -C "$D/wt" rev-parse HEAD 2>/dev/null)
old_run() { # <step-failed-at> <error> <extra>
cat <<EOF
run:
  id: "01OLDRUN"
  branch: $BR
  status: failed
  head: "$HEAD"
  pr: "$PRFIELD"
  error: "$2"
  findings: none
outcome: failed
steps[9]{step,status,findings,duration_ms}:
$STEPS
$3
EOF
}
case "$1 ${2:-}" in
  "daemon status")
    if [ "$S" = refused ]; then echo "error: dial unix /home/u/.no-mistakes/daemon.sock: connect: connection refused" >&2; exit 1; fi
    echo "daemon: running (pid 41231, version 1.91.0, up 24s)";;
  "doctor "*) echo "ok";;
  "axi status")
    if [ "$S" = refused ]; then echo "error: daemon not reachable: dial unix /home/u/.no-mistakes/daemon.sock: connect: connection refused" >&2; exit 1; fi
    if [ "$S" = green ]; then
      PRFIELD="https://github.com/acme/demo/pull/42"
      STEPS="  intent,completed,0,0
  rebase,completed,0,0
  review,completed,0,0
  test,completed,0,0
  document,completed,0,0
  lint,completed,0,0
  push,completed,0,0
  pr,completed,0,0
  ci,failed,0,76127890"
      old_run ci "daemon shutting down" "ci_log_tail[2]:
  all CI checks passed - still monitoring until merged or closed
  daemon shutting down
branch_sync:
  state: in_sync
  next_action:
    code: none"
      exit 0
    fi
    PRFIELD=""
    STEPS="  intent,completed,0,0
  rebase,completed,0,0
  review,failed,0,912000"
    if [ -e "$D/fresh" ]; then
      cat <<EOF
run:
  id: "01FRESH"
  branch: $BR
  status: failed
  head: "$HEAD"
  error: "daemon crashed during execution"
outcome: failed
EOF
      exit 0
    fi
    if [ -e "$D/recovered" ]; then
      old_run review "$ERR" "branch_sync:
  state: in_sync
  next_action:
    code: start_run
    command: no-mistakes axi run"
    else
      old_run review "$ERR" "branch_sync:
  state: diverged_custody
  next_action:
    code: recover_custody
    command: no-mistakes axi sync --recover"
    fi;;
  "axi sync")
    touch "$D/recovered"; echo "recovered: branch custody restored to local $BR at ${HEAD:0:7}";;
  "axi run")
    if [ "$S" = again ]; then touch "$D/fresh"; echo "run 01FRESH started on $BR"; echo "error: run 01FRESH failed: daemon crashed during execution" >&2; exit 1; fi
    if [ "$S" = cut ] && [ ! -e "$D/recovered" ]; then echo "error: branch custody needs recovery: run no-mistakes axi sync --recover" >&2; exit 1; fi
    cat <<EOF
run:
  id: "01FRESH"
  branch: $BR
  status: completed
  pr: "https://github.com/acme/demo/pull/43"
outcome: checks-passed
help[1]:
  CI is green; the ci step keeps monitoring until merged or closed
EOF
    ;;
  *) echo "no-mistakes (fake): $*";;
esac
