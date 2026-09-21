#!/usr/bin/env python3
"""Composite SVG of the live working row across scenarios.
composite_svg.py <out.svg> <title> <label>=<frames.ansi> ..."""
import sys
from analyze import read_frames, parse_line, find_chart, plain
from svg import text_rows, svg, label, LH, CW
out, title = sys.argv[1], sys.argv[2]
body = [label(10, 20, title)]
y = 34
width = 160
for spec in sys.argv[3:]:
    name, path = spec.rsplit("=", 1)
    frames = read_frames(path)
    pick = None
    for want in ("chart", "hull", "stock"):
        hits = []
        for ts, lines in frames:
            if want == "chart": i = find_chart(lines)
            elif want == "hull": i = next((k - 1 for k, l in enumerate(lines) if "╲▁▁▁╱" in plain(l)), None)
            else: i = next((k for k, l in enumerate(lines) if "… (" in plain(l)), None)
            if i is not None: hits.append((lines, i, want))
        if hits: pick = hits[len(hits) // 2]; break
    body.append(label(10, y + 14, name, 13, "#cde"))
    y += 20
    if pick is None:
        body.append(label(20, y + 14, "(no working row captured)", 12, "#f88")); y += 24; continue
    lines, i, kind = pick
    lo, hi = max(0, i - 2), min(len(lines), i + 4)
    body.append(f'<rect x="8" y="{y + (i - lo) * LH - 1}" width="{width * CW + 4:.0f}" height="{(1 if kind == "stock" else 2) * LH + 2}" fill="none" stroke="#e5c07b" stroke-dasharray="4 3"/>')
    body += text_rows(lines[lo:hi], 10, y)
    body.append(label(width * CW - 260, y + 12, f"working row drawn as: {dict(chart='CANDLES', hull='BOAT', stock='STOCK spinner')[kind]}", 12, "#e5c07b"))
    y += (hi - lo) * LH + 14
open(out, "w").write(svg(width * CW + 20, y + 10, body, title))
print("wrote", out)
