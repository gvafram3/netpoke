#!/bin/bash
# Run the authors' mutex experiment for one arm.
#   run_arm.sh LABEL YAMLDIR REP [extra main.py args]
#   run_arm.sh phase1_orig yamls-orig 1                 # authors' image, authors' yamls (reproduction)
#   run_arm.sh phase2_freeze yamls-freeze 1             # SIGSTOP only, patched image
#   run_arm.sh phase2_hold   yamls-hold   1             # SIGSTOP + hold
# Env: NUM_EXP (default 10 optimisation levels), THREADS (8), CONNS (512), NUM_REQ (20000), MUTEX=1 for --mutex_lock
set -uo pipefail
export FORCE_REDEPLOY=1   # every experiment must redeploy: new settings only reach the pods at deploy time
LABEL="${1:?label}"; YDIR="${2:?yamls dir name}"; REP="${3:?rep number}"; shift 3
EVAL="$HOME/slowpoke/evaluation/mutex"
[ -d "$EVAL/yamls-orig" ] || cp -r "$EVAL/yamls" "$EVAL/yamls-orig"      # the authors' originals, saved once
[ -d "$EVAL/$YDIR" ] || { echo "no $EVAL/$YDIR (run make_mutex_yamls.py first)"; exit 1; }
restore(){ rm -rf "$EVAL/yamls"; cp -r "$EVAL/yamls-orig" "$EVAL/yamls"; }
trap restore EXIT
rm -rf "$EVAL/yamls"; cp -r "$EVAL/$YDIR" "$EVAL/yamls"
mkdir -p "$HOME/results"; OUT="$HOME/results/${LABEL}_rep${REP}.log"
EXTRA=""; [ "${MUTEX:-0}" = 1 ] && EXTRA="--mutex_lock"
echo "[run_arm] $LABEL rep$REP  yamls=$YDIR  -> $OUT   ($(date))"
cd "$HOME/slowpoke/evaluation" || exit 1
kubectl delete -f mutex/yamls --ignore-not-found >/dev/null 2>&1
python3 ../src/main.py -b mutex -x service1 -r mix -t "${THREADS:-8}" -c "${CONNS:-512}" \
   --num_exp "${NUM_EXP:-10}" --repetitions 1 --num_req "${NUM_REQ:-20000}" --poker_batch_req 100 $EXTRA "$@" > "$OUT" 2>&1
RC=$?
kubectl delete -f mutex/yamls --ignore-not-found >/dev/null 2>&1
grep -E "Error percentage" "$OUT" | tail -1
echo "[run_arm] exit=$RC  log=$OUT"
