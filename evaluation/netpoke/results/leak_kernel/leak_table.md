# Leak test summary

LEAK % = traffic leaving while the service is frozen ÷ traffic while running (0 % = perfect hold). PLUG DROPS must be 0.

| SCENARIO | HOLD | PAUSE ms | RUNS | PKTS/WINDOW running | PKTS/WINDOW frozen | LEAK % mean (min..max) | PLUG DROPS | READING |
|---|---|---|---|---|---|---|---|---|
| idle | off | 50 | 1 | 0.0 | 0.0 | n/a | - | CONTROL OK: nothing sent, nothing leaked |
| receiver | off | 50 | 1 | 14.6 | 1.0 | 6.9  (6.9 .. 6.9) | - | acknowledgements only (no data sent) |
| receiver | ON | 50 | 1 | 14.6 | 0.0 | 0.0  (0.0 .. 0.0) | 0 | HOLD WORKS |
| sender | off | 50 | 3 | 16.5 | 17.4 | 105.4  (98.6 .. 112.6) | - | GAP CONFIRMED: frozen service keeps sending |
| sender | ON | 50 | 3 | 17.0 | 0.0 | 0.0  (0.0 .. 0.0) | 0 | HOLD WORKS |
| sender | ON | 200 | 1 | 71.1 | 0.0 | 0.0  (0.0 .. 0.0) | 0 | HOLD WORKS |
| sender | ON | 1000 | 1 | 393.8 | 0.0 | 0.0  (0.0 .. 0.0) | 0 | HOLD WORKS |
