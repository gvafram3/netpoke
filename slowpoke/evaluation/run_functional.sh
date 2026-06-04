#!/bin/bash

export SLOWPOKE_TOP=${SLOWPOKE_TOP:-$(cd "${BASH_SOURCE%/*}/.." && pwd -P)}

cd $(dirname $0)
mkdir -p results
bash "$(dirname $0)/safe_delete_workloads.sh"
bash boutique/run-boutique-tiny.sh results/boutique_tiny.log