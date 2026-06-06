# NetPoke

NetPoke extends SlowPoke (Xie et al., 2026, NSDI) so that its throughput
predictions remain accurate for I/O-bound microservices, not only compute-bound
ones. SlowPoke slows non-target services by suspending their processes with
`SIGSTOP`, which stops the CPU but not the kernel's network activity; for
I/O-bound services the slowdown is therefore incomplete and predictions degrade.
NetPoke makes the pause complete by holding a service's network egress for the
same window in which its process is paused (mechanism "A", the perfect pause).

- **Student:** Afram Visca Gyebi
- **Supervisor:** Dr. (Mrs.) Rose-Mary Mensah Gyening
- **Programme:** MPhil Computer Science, Kwame Nkrumah University of Science and
  Technology, Kumasi, Ghana
- **Base paper:** `../slowpoke_nsdi_2026.pdf`

## Contents

- `thesis/chapter1.md` — Chapter 1 (Introduction), rewritten, APA, British
  spelling, consistent with mechanism A. Four objectives, four research
  questions.
- `design/poker-io-pause.md` — design for the synchronised network pause inside
  POKER (the core contribution).
- `infra/gcp/` — scripts and runbook to build the multi-node measurement cluster
  on Google Cloud, reusing SlowPoke's own setup scripts.
- `INSTRUCTIONS.md` — **thesis artifact reproduction** (like SlowPoke `INSTRUCTIONS.md`)
- `docs/thesis-evaluation-roadmap.md` — master plan: baseline, I/O gap (all 4 apps),
  eBPF, NetPoke, Fig. 8/9, synthetic benchmarks, download instructions
- **Defense branch:** `netpoke26-thesis`

## Current decisions (canonical)

- Mechanism: **A**, perfect pause via egress hold (`sch_plug`), integrated into
  POKER and synchronised with each `SIGSTOP`/`SIGCONT`. Throttle and static-delay
  variants are kept only as comparison baselines.
- Cluster: 8 GCP VMs (1 control + 1 load-generator + 6 service workers), torn
  down between experiment batches to stay within budget.
- Referencing: APA 7th. Spelling: British.

## Important corrections to earlier notes

- The numbers from earlier sessions (for example a 59% RMSE and an
  8,709-bytes-to-13-bytes residual) are treated as **unverified** and will be
  re-measured from scratch on the new cluster before any are cited.
- SlowPoke's **functional test is not an accuracy test**; the artifact's own
  example shows roughly -76% error on it because it runs a trivially small number
  of requests. Earlier "24-57% functional test error" observations therefore
  carry no conclusion. Accuracy claims come only from the full reproducible runs.
