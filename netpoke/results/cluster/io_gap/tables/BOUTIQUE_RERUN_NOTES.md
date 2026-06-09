# Boutique product_catalog re-run (2026-06-09)

## What changed

| Version | L1 injection | L2 injection | L2 − L0 RMSE |
|---------|--------------|--------------|--------------|
| Shipping (superseded) | shipping:30ms | shipping:50ms | −6.12 pp |
| **Product catalog (final)** | productcatalog:30ms | productcatalog:50ms + currency:30ms | **−3.59 pp** |

Logs: `boutique_io_L1_medium.log`, `boutique_io_L2_medium.log` on netpoke-control.  
Archived shipping runs: `results/saved/boutique_shipping_inject_20260607/`

## Final boutique numbers

| Level | Baseline (req/s) | RMSE % |
|-------|------------------|--------|
| L0 | 1820.0 | 9.19 |
| L1 | 1715.6 | 6.93 |
| L2 | 1739.0 | 5.61 |

L2 `Error Perc:` (10 points):  
`[-11.89, -0.74, 5.00, 1.87, -4.15, -7.60, 1.50, 0.81, 2.61, 7.72]`

## Thesis use

- **Primary I/O-gap evidence:** social (+14.3 pp), hotel (+6.1 pp), movie (+2.8 pp).
- **Boutique:** Discuss injection placement and workload binding; optional Phase 4 eBPF on L2 to test whether residual I/O during pause exists even when RMSE does not rise.
