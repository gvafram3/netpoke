#!/bin/bash
export SLOWPOKE_TOP="${SLOWPOKE_TOP:-$HOME/slowpoke}"
if [[ ! -f "$SLOWPOKE_TOP/src/main.py" ]]; then
  echo "ERROR: SLOWPOKE_TOP=$SLOWPOKE_TOP is invalid (no src/main.py)" >&2
  exit 1
fi

outfile=$1
outdir=$(realpath $(dirname $outfile))
name=$(basename $outfile)
outfile=$outdir/$name
cd $(dirname $0)/..

target=moviereviews
thread=8
conn=1024
repetitions=1
num_req=20000
poker_batch_req=100
num_exp=10
DIR=movie/04-08-pokerpp
FILE=mix-$target-t$thread-c$conn-r$repetitions-req$num_req-n$num_exp-poker_batch_req$poker_batch_req.log
mkdir -p $DIR

bash "$SLOWPOKE_TOP/evaluation/safe_delete_workloads.sh"
python3 -u $SLOWPOKE_TOP/src/main.py -b movie -r mix -x $target --num_exp $num_exp -t $thread -c $conn --poker_batch_req $poker_batch_req --repetitions $repetitions --num_req $num_req >$outfile
