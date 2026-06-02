#!/bin/bash

# One SSH session: ./run_with_monitor.sh  (prints live counters to your terminal)
if [[ -z "${SLOWPOKE_MONITOR_STARTED:-}" && -z "${SLOWPOKE_NO_MONITOR:-}" ]]; then
  export SLOWPOKE_MONITOR_STARTED=1
  exec "$(cd "${BASH_SOURCE%/*}" && pwd)/run_with_monitor.sh" bash "$0"
fi

export SLOWPOKE_TOP=${SLOWPOKE_TOP:-$(cd "${BASH_SOURCE%/*}/.." && pwd -P)}

kubectl delete deployments --all
kubectl delete services --all

cd $(dirname $0)
mkdir -p results
time bash boutique/run-boutique-medium.sh results/boutique_medium.log
time bash hotel/run-hotel-medium.sh results/hotel_medium.log
time bash social/run-social-medium.sh results/social_medium.log
time bash movie/run-movie-medium.sh results/movie_medium.log

outdir=$(realpath ./results)
draw_script=$(realpath ./draw.py)

echo "The results are stored in ${outdir}"
echo "To visualize the results, run: "
echo ""
echo "python3 ${draw_script} ${outdir}"
