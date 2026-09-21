#!/usr/bin/env python3
"""Composite SVG: the live chart rows (with neighbours) at each captured pane width."""
import sys, html
from analyze import read_frames, parse_line, find_chart
from svg import text_rows, svg, label, LH, CW
E = sys.argv[1]; widths = [int(w) for w in sys.argv[2].split(",")]
body = [label(10, 20, "Calm candles scene live in Claude Code 2.1.278: one turn, pane resized mid-turn (tmux resize-window)")]
body.append(label(10, 38, "Dashed box = the two chart rows; the pane edge is the solid line. Rows never wrap and stay two rows at every width.", 12, "#789"))
y = 50
for w in widths:
    frames = read_frames(f"{E}/w{w}.ansi")
    hit = [(ts, l, find_chart(l, 1)) for ts, l in frames]
    hit = [h for h in hit if h[2] is not None]
    ts, lines, idx = hit[len(hit) // 2]
    lo, hi = max(0, idx - 2), min(len(lines), idx + 4)
    body.append(label(10, y + 14, f"pane {w} columns: {len(hit)}/{len(frames)} frames show the chart", 13, "#cde"))
    y += 22
    body.append(f'<rect x="10" y="{y}" width="{w * CW:.1f}" height="{(hi - lo) * LH}" fill="#101010" stroke="#555"/>')
    body.append(f'<rect x="8" y="{y + (idx - lo) * LH - 1}" width="{w * CW + 4:.1f}" height="{2 * LH + 2}" fill="none" stroke="#e5c07b" stroke-dasharray="4 3"/>')
    body += text_rows(lines[lo:hi], 10, y)
    y += (hi - lo) * LH + 16
open(f"{E}/narrow-resize.svg", "w").write(svg(160 * CW + 30, y + 10, body, "candles narrow resize"))
print("wrote", f"{E}/narrow-resize.svg")
