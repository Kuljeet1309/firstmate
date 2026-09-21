#!/usr/bin/env python3
"""Render timestamped ANSI tmux captures as SVG images.

svg.py <frames.ansi> <out-prefix> <title> [--context N] [--min M]
Writes <out-prefix>-screen.svg (full screen mid-working-period),
<out-prefix>-filmstrip.svg (first distinct chart frames with timestamps) and
<out-prefix>-replay.svg (animated replay of the chart rows at captured timing).
"""
import sys, html
from analyze import read_frames, parse_line, find_chart, xterm256, CANDLE

CW, LH, FS = 8.43, 17, 14
BG, FG = "#1b1b1b", "#d0d0d0"

def color(fg):
    if not fg: return FG
    if fg.startswith("5;"): return xterm256(fg[2:])
    r, g, b = fg[2:].split(";"); return f"rgb({r},{g},{b})"

def text_rows(lines, x0, y0, scale=1.0):
    out = []
    cw, lh, fs = CW * scale, LH * scale, FS * scale
    for i, line in enumerate(lines):
        cells = parse_line(line) if isinstance(line, str) else line
        y = y0 + (i + 1) * lh - lh * 0.25
        col, run, key, start = 0, "", None, 0
        def flush():
            if run.strip():
                fg, bold, dim = key
                attrs = f'fill="{color(fg)}"' + (' font-weight="bold"' if bold else '') + (' opacity="0.6"' if dim else '')
                out.append(f'<text x="{x0 + start * cw:.1f}" y="{y:.1f}" {attrs} font-size="{fs:.1f}" xml:space="preserve">{html.escape(run)}</text>')
        for ch, fg, bold, dim in cells:
            k = (fg, bold, dim)
            if k != key:
                flush(); run, key, start = "", k, col
            run += ch; col += 1
        flush()
    return out

def svg(width, height, body, title):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{width:.0f}" height="{height:.0f}" viewBox="0 0 {width:.0f} {height:.0f}" '
            f'font-family="DejaVu Sans Mono, Menlo, Consolas, monospace">\n<title>{html.escape(title)}</title>\n'
            f'<rect width="100%" height="100%" fill="{BG}"/>\n' + "\n".join(body) + "\n</svg>\n")

def label(x, y, s, size=13, fill="#9ab"):
    return f'<text x="{x}" y="{y}" fill="{fill}" font-size="{size}" font-family="system-ui, sans-serif">{html.escape(s)}</text>'

def main():
    a = sys.argv[1:]
    path, prefix, title = a[0], a[1], a[2]
    ctx = int(a[a.index("--context") + 1]) if "--context" in a else 3
    minimum = int(a[a.index("--min") + 1]) if "--min" in a else 3
    frames = read_frames(path)
    charts = [(ts, lines, find_chart(lines, minimum)) for ts, lines in frames]
    charts = [c for c in charts if c[2] is not None]
    cols = max(len(parse_line(l)) for _, lines, _ in charts for l in lines)
    ts0 = charts[0][0]
    # 1. full screen mid-working-period
    ts, lines, idx = charts[len(charts) // 2]
    body = [label(10, 20, title + f"  (t = {int((ts - ts0) * 1000)} ms into the capture; chart rows {idx + 1}-{idx + 2})")]
    body.append(f'<rect x="6" y="{30 + idx * LH - 2}" width="{cols * CW + 8:.0f}" height="{2 * LH + 4}" fill="none" stroke="#e5c07b" stroke-dasharray="4 3"/>')
    body += text_rows(lines, 10, 30)
    open(prefix + "-screen.svg", "w").write(svg(cols * CW + 20, 40 + len(lines) * LH, body, title))
    # distinct chart sequence
    seq = []
    for ts, lines, idx in charts:
        rows = lines[idx:idx + 2]
        key = tuple("".join(c[0] for c in parse_line(r)) for r in rows)
        if not seq or seq[-1][1] != key: seq.append((ts, key, lines, idx))
    # 2. filmstrip: zoomed chart rows (first 60 columns) of up to 6 distinct frames
    scale, span = 2.0, 60
    body = [label(10, 20, title + ": first distinct working-row frames, left 60 columns, zoomed 2x"),
            label(10, 38, "Each frame is the previous one moved one column left; candles alternate with one blank column.", 12, "#789")]
    y = 50
    t_first = seq[0][0]
    for ts, key, lines, idx in seq[:6]:
        body.append(label(10, y + 14, f"t = {int((ts - t_first) * 1000)} ms", 12))
        cells = [parse_line(r)[:span] for r in lines[idx:idx + 2]]
        body += text_rows(cells, 90, y, scale)
        y += 2 * LH * scale + 14
    open(prefix + "-filmstrip.svg", "w").write(svg(span * CW * scale + 110, y + 10, body, title))
    # 3. animated replay of the chart rows plus context lines, at captured timing
    total = (seq[-1][0] - seq[0][0]) + 1.0
    body = [label(10, 20, title + ": replay of the captured working row at captured timing (loops)")]
    for n, (ts, key, lines, idx) in enumerate(seq):
        lo, hi = max(0, idx - ctx), min(len(lines), idx + 2 + ctx)
        start = (ts - seq[0][0]) / total
        end = ((seq[n + 1][0] - seq[0][0]) / total) if n + 1 < len(seq) else 1.0
        if n == 0: anim = f'<animate attributeName="opacity" values="1;0" keyTimes="0;{end:.4f}" calcMode="discrete" dur="{total:.3f}s" repeatCount="indefinite"/>'
        elif n + 1 == len(seq): anim = f'<animate attributeName="opacity" values="0;1" keyTimes="0;{start:.4f}" calcMode="discrete" dur="{total:.3f}s" repeatCount="indefinite"/>'
        else: anim = f'<animate attributeName="opacity" values="0;1;0" keyTimes="0;{start:.4f};{end:.4f}" calcMode="discrete" dur="{total:.3f}s" repeatCount="indefinite"/>'
        body.append(f'<g opacity="{1 if n == 0 else 0}">{anim}')
        body += text_rows(lines[lo:hi], 10, 30)
        body.append(label(10, 30 + (hi - lo) * LH + 16, f"frame {n + 1}/{len(seq)}  t = {int((ts - seq[0][0]) * 1000)} ms", 12))
        body.append("</g>")
    open(prefix + "-replay.svg", "w").write(svg(cols * CW + 20, 30 + (2 + 2 * ctx) * LH + 30, body, title))
    print(f"wrote {prefix}-screen.svg {prefix}-filmstrip.svg {prefix}-replay.svg ({len(seq)} distinct frames)")

if __name__ == "__main__":
    main()
