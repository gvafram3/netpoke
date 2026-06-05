#!/usr/bin/env python3
"""Per-benchmark plots: Predicted vs Groundtruth (authors' draw.py, Fig. 8 panels)."""
import os
import re
import ast
import sys
from pathlib import Path

import matplotlib.pyplot as plt
import requests


def get_public_ip():
    try:
        resp = requests.get('http://checkip.amazonaws.com', timeout=5)
        resp.raise_for_status()
        return resp.text.strip()
    except Exception:
        return None

def parse_results(filename):
    with open(filename, 'r') as f:
        text = f.read()

    # regex patterns for each field
    patterns = {
        'baseline':    r"Baseline throughput:\s*([0-9]+\.[0-9]+)",
        'groundtruth': r"Groundtruth:\s*(\[[^\]]+\])",
        'slowdown':    r"Slowdown:\s*(\[[^\]]+\])",
        'predicted':   r"Predicted:\s*(\[[^\]]+\])",
        'error_perc':  r"Error Perc:\s*(\[[^\]]+\])",
    }

    data = {}
    for key, pat in patterns.items():
        m = re.search(pat, text)
        if not m:
            raise ValueError(f"Could not find `{key}` in {filename}")
        s = m.group(1)
        # lists vs single floats
        if s.startswith('['):
            data[key] = ast.literal_eval(s)
        else:
            data[key] = float(s)
    return data

def is_complete_medium_log(path: Path) -> bool:
    if not path.name.endswith("_medium.log"):
        return False
    text = path.read_text(errors="replace")
    return "Error Perc:" in text and "Groundtruth:" in text


def output_dirs(result_path: Path) -> list[Path]:
    dirs: list[Path] = []
    if result_path.is_file():
        dirs.append(result_path.parent)
    else:
        dirs.append(result_path)
    www = Path('/var/www/html')
    if www.is_dir() and os.access(www, os.W_OK):
        dirs.append(www)
    return dirs


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: draw.py <results_dir_or_log>")
        sys.exit(1)
    result_dir = Path(sys.argv[1])
    if result_dir.is_file():
        candidates = [result_dir]
    else:
        candidates = sorted(result_dir.glob("*_medium.log"))
    ip = get_public_ip()
    saved = 0
    for logfile in candidates:
        if not is_complete_medium_log(logfile):
            print(f"Skip {logfile.name} (incomplete or not *_medium.log)")
            continue
        data = parse_results(logfile)

        groundtruth = data['groundtruth']
        predicted = data['predicted']

        x = [e * 10 for e in range(len(groundtruth))]

        plt.figure()
        plt.plot(x, list(reversed(groundtruth)), label='Groundtruth', marker='o')
        plt.plot(x, list(reversed(predicted)), label='Predicted', marker='s')
        y_max = max(max(groundtruth), max(predicted)) * 1.2
        plt.xlabel('Optimized processing time (%)')
        plt.ylabel('Throughput (req/s)')
        plt.ylim(0, y_max)
        plt.title(f'{logfile.stem}: Predicted vs. Groundtruth')
        plt.legend()
        plt.grid(True, linestyle=':', alpha=0.5)
        plt.tight_layout()
        figure_name = logfile.name.replace('.log', '.png')
        for out_dir in output_dirs(result_dir):
            out_path = out_dir / figure_name
            plt.savefig(out_path, dpi=150)
            print(f'Wrote {out_path}')
            if ip and out_dir == Path('/var/www/html'):
                print(f'  Browser: http://{ip}/{figure_name}')
        plt.close()
        saved += 1
    if saved == 0:
        print("No complete *_medium.log files to plot.")
        sys.exit(1)
