#!/bin/bash
# Small-payload CPU-only arms for Phase 5b-i (no --payload, so replies stay tiny, matching Phase 1's regime).
python3 ~/kit/control/make_mutex_yamls.py --image gvafram3/slowpoke:mutex-netpoke-9c993ce --suffix _cpu "$@"
