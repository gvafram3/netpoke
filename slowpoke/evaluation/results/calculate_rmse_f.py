#!/usr/bin/env python3
import math
import re
import sys

# Extract all error percentages from experiment_f_full.log
log_file = 'experiment_f_full.log'
errors = []

with open(log_file, 'r') as f:
    for line in f:
        if 'Error percentage:' in line or 'Error Perc:' in line:
            # Try to extract error numbers from lines like:
            # [test.py] Error percentage: [63.7, 54.03, ...]
            match = re.findall(r'[-+]?\d+\.?\d*', line)
            for m in match:
                try:
                    errors.append(float(m))
                except:
                    pass

if errors:
    rmse = math.sqrt(sum(e**2 for e in errors) / len(errors))
    mean_error = sum(errors) / len(errors)
    print(f"\n=== Experiment F RMSE Calculation ===")
    print(f"Total observations: {len(errors)}")
    print(f"Mean error: {mean_error:.2f}%")
    print(f"RMSE: {rmse:.2f}%")
    print(f"\nComparison:")
    print(f"  Baseline (Exp A-C): ~8-9%")
    print(f"  Exp E (no fix): ~59%")
    print(f"  Exp F (NetPoke): {rmse:.2f}%")
    print(f"\nResult: {'✓ SUCCESS - RMSE recovered!' if rmse < 20 else '✗ PARTIAL - RMSE improved but not to baseline'}")
else:
    print("ERROR: No error percentages found in log")
    sys.exit(1)
