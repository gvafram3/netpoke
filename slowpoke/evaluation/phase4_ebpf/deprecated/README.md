# Deprecated — do not use for new measurements

`residual_io_sampler.py` here is the original Phase 4 residual-I/O instrument.
It polls pods via serial `kubectl exec`/`kubectl get` calls once per loop
(several round-trips per iteration), which is roughly 2-3 orders of magnitude
too slow to resolve individual SIGSTOP pause windows (POKER pauses fire tens
of times per second; this sampler's published results show it catching a
stopped process in only a few dozen samples over 40-50 minute runs).

Kept for reproducibility of the original Phase 4 run only. Do not use it to
validate NetPoke residual I/O — see `netpoke/docs/METHODOLOGY_CRITIQUE_AND_FIX_PLAN.md`
(finding F2) and the corrected instrument in `slowpoke/evaluation/phase6_netpoke/`.
