#!/usr/bin/env python3
"""Analyze timestamped ANSI tmux captures of the Calm working row.

Usage: analyze.py <frames.ansi> <cols> [--palette dark|light] [--html out.html] [--title T]
Prints a JSON report: chart geometry, spacing, colors, scroll direction and pace.
"""
import html, json, re, statistics, sys

CANDLE = set("╷╻╵│╽╹╿┃")
SGR = re.compile(r"\x1b\[([0-9;]*)m")
PALETTES = {"dark": {"71", "204"}, "light": {"29", "125"}}
TRUE = {"dark": {"95;175;95", "255;95;135"}, "light": {"0;135;95", "175;0;95"}}
XTERM16 = ["#000", "#c33", "#3a3", "#cc3", "#35c", "#c3c", "#3cc", "#ccc",
           "#666", "#f55", "#5f5", "#ff5", "#57f", "#f5f", "#5ff", "#fff"]

def xterm256(n):
    n = int(n)
    if n < 16: return XTERM16[n]
    if n < 232:
        n -= 16; steps = [0, 95, 135, 175, 215, 255]
        return "#%02x%02x%02x" % (steps[n // 36], steps[(n // 6) % 6], steps[n % 6])
    v = 8 + (n - 232) * 10
    return "#%02x%02x%02x" % (v, v, v)

def parse_line(line):
    """Return list of (char, fg) cells; fg is a key like '5;71' or '2;r;g;b' or None."""
    cells, fg, bold, dim, pos = [], None, False, False, 0
    for m in SGR.finditer(line):
        for ch in line[pos:m.start()]:
            cells.append((ch, fg, bold, dim))
        pos = m.end()
        params = m.group(1).split(";") if m.group(1) else ["0"]
        i = 0
        while i < len(params):
            p = params[i]
            if p in ("0", ""): fg, bold, dim = None, False, False
            elif p == "1": bold = True
            elif p == "2": dim = True
            elif p == "22": bold = dim = False
            elif p == "39": fg = None
            elif p == "38" and i + 1 < len(params):
                if params[i + 1] == "5": fg = "5;" + params[i + 2]; i += 2
                elif params[i + 1] == "2": fg = "2;" + ";".join(params[i + 2:i + 5]); i += 4
            elif p.isdigit() and 30 <= int(p) <= 37: fg = "5;" + str(int(p) - 30)
            elif p.isdigit() and 90 <= int(p) <= 97: fg = "5;" + str(int(p) - 82)
            i += 1
    for ch in line[pos:]:
        cells.append((ch, fg, bold, dim))
    return cells

def read_frames(path):
    frames, cur, ts = [], None, None
    for raw in open(path, encoding="utf-8", errors="replace"):
        raw = raw.rstrip("\n")
        if raw.startswith("@@FRAME "):
            if cur is not None: frames.append((ts, cur))
            ts, cur = int(raw.split()[1]) / 1e9, []
        elif cur is not None:
            cur.append(raw)
    if cur is not None: frames.append((ts, cur))
    return frames

def plain(line): return SGR.sub("", line)

def is_candle_line(text, minimum=3):
    body = text.rstrip()
    return bool(body) and all(c == " " or c in CANDLE for c in body) and sum(c in CANDLE for c in body) >= minimum

def find_chart(lines, minimum=3):
    for i in range(len(lines) - 1):
        a, b = plain(lines[i]), plain(lines[i + 1])
        if is_candle_line(a, 1) and is_candle_line(b, 1) and (sum(c in CANDLE for c in a + b) >= minimum):
            return i
    return None

def main():
    args = sys.argv[1:]
    path, cols = args[0], int(args[1])
    palette = args[args.index("--palette") + 1] if "--palette" in args else "dark"
    out_html = args[args.index("--html") + 1] if "--html" in args else None
    title = args[args.index("--title") + 1] if "--title" in args else path
    minimum = int(args[args.index("--min") + 1]) if "--min" in args else 3
    frames = read_frames(path)
    report = {"frames": len(frames), "chart_frames": 0, "problems": []}
    charts = []  # (ts, [row0 cells], [row1 cells], line index, frame lines)
    for ts, lines in frames:
        idx = find_chart(lines, minimum)
        if idx is None: continue
        # a third candle-only line above or below would mean more than two rows or wrapping
        extra = [j for j in (idx - 1, idx + 2) if 0 <= j < len(lines) and is_candle_line(plain(lines[j]), 1)]
        if extra: report["problems"].append(f"frame {ts:.3f}: candle glyphs on a third adjacent line {extra}")
        rows = [parse_line(lines[idx]), parse_line(lines[idx + 1])]
        for r in rows:
            if len(r) > cols: report["problems"].append(f"frame {ts:.3f}: row wider than terminal ({len(r)} > {cols})")
        charts.append((ts, rows, idx, lines))
    report["chart_frames"] = len(charts)
    if not charts:
        print(json.dumps(report, indent=1)); return
    # geometry from glyph columns
    left = min(min((c for r in rows for c, cell in enumerate(r) if cell[0] in CANDLE), default=10**9) for _, rows, _, _ in charts)
    right = max(max((c for r in rows for c, cell in enumerate(r) if cell[0] in CANDLE), default=-1) for _, rows, _, _ in charts)
    report["glyph_column_span"] = [left, right]
    allowed_fg = {"5;" + x for x in PALETTES[palette]} | {"2;" + x for x in TRUE[palette]}
    seen_fg, parity_ok, color_ok, counts, one_color = set(), 0, 0, [], 0
    def glyph_string(rows):
        return tuple("".join(cell[0] for cell in r[left - 1 if left > 0 else 0: right + 2]).ljust(right + 3 - max(left - 1, 0)) for r in rows)
    for ts, rows, idx, _ in charts:
        width = max(len(r) for r in rows)
        glyph_cols = sorted({c for r in rows for c, cell in enumerate(r) if cell[0] in CANDLE})
        counts.append(len(glyph_cols))
        parities = {c % 2 for c in glyph_cols}
        gaps_ok = all(b - a == 2 for a, b in zip(glyph_cols, glyph_cols[1:]))
        if len(parities) == 1 and gaps_ok: parity_ok += 1
        else: report["problems"].append(f"frame {ts:.3f}: glyph columns not one-candle-one-gap: {glyph_cols[:12]}...")
        ok = True
        for c in glyph_cols:
            fgs = {r[c][1] for r in rows if c < len(r) and r[c][0] in CANDLE}
            seen_fg |= fgs
            if not fgs <= allowed_fg: ok = False
            if len(fgs) == 1: one_color += 1
        color_ok += ok
    report["frames_with_one_candle_one_gap"] = parity_ok
    report["frames_with_only_theme_green_red"] = color_ok
    report["glyph_columns_per_frame"] = [min(counts), max(counts)]
    report["colors_seen"] = sorted(x for x in seen_fg if x)
    report["candles_single_colored"] = one_color == sum(counts)
    # scroll: transitions between distinct consecutive charts
    seq = []
    for ts, rows, _, _ in charts:
        g = tuple("".join(cell[0] for cell in r) for r in rows)
        if not seq or seq[-1][1] != g: seq.append((ts, g))
    shifts, times = [], []
    for (t0, g0), (t1, g1) in zip(seq, seq[1:]):
        a0 = [s[left:right + 1].ljust(right + 1 - left) for s in g0]
        a1 = [s[left:right + 1].ljust(right + 1 - left) for s in g1]
        kind = "other"
        if all(x[1:] == y[:-1] for x, y in zip(a0, a1)): kind = "left1"
        elif all(x[:-1] == y[1:] for x, y in zip(a0, a1)): kind = "right1"
        shifts.append(kind); times.append(t1 - t0)
    report["distinct_charts"] = len(seq)
    report["transitions"] = {k: shifts.count(k) for k in set(shifts)}
    if len(times) >= 2:
        inner = times[1:]  # first interval is truncated by the start of recording
        report["interval_ms"] = {"median": round(statistics.median(inner) * 1000), "min": round(min(inner) * 1000),
                                 "max": round(max(inner) * 1000), "n": len(inner)}
    report["sample_chart"] = ["".join(c[0] for c in r).rstrip() for r in charts[len(charts) // 2][1]]
    print(json.dumps(report, indent=1, ensure_ascii=False))
    if out_html: write_html(out_html, title, charts, seq, frames, cols)

def cell_html(cells):
    out, run, key = [], "", None
    def flush():
        if not run: return
        fg, bold, dim = key
        style = []
        if fg:
            if fg.startswith("5;"): style.append("color:" + xterm256(fg[2:]))
            else: r, g, b = fg[2:].split(";"); style.append(f"color:rgb({r},{g},{b})")
        if bold: style.append("font-weight:bold")
        if dim: style.append("opacity:.6")
        out.append(f'<span style="{";".join(style)}">{html.escape(run)}</span>' if style else html.escape(run))
    for ch, fg, bold, dim in cells:
        k = (fg, bold, dim)
        if k != key: flush(); run, key = "", k
        run += ch
    flush()
    return "".join(out)

def write_html(path, title, charts, seq, frames, cols):
    # full-screen frame at the middle of the working period, then a replay of the chart rows
    mid = charts[len(charts) // 2]
    screen = "\n".join(cell_html(parse_line(l)) for l in mid[3])
    chart_by_ts = {ts: rows for ts, rows, _, _ in charts}
    replay = []
    for ts, g in seq:
        rows = next(r for t, r, _, _ in charts if tuple("".join(c[0] for c in x) for x in r) == g)
        replay.append({"t": ts, "html": "\n".join(cell_html(r) for r in rows)})
    t0 = replay[0]["t"]
    for r in replay: r["t"] = round((r["t"] - t0) * 1000)
    strip = "\n".join(f'<div class="lbl">t = {r["t"]} ms</div><pre class="chart">{r["html"]}</pre>' for r in replay[:6])
    doc = f"""<!doctype html><meta charset="utf-8"><title>{html.escape(title)}</title>
<style>body{{background:#1e1e1e;color:#ddd;font-family:system-ui;margin:16px}}
pre{{font-family:'DejaVu Sans Mono',monospace;font-size:13px;line-height:1.15;margin:0;background:#111;padding:8px;border:1px solid #333;white-space:pre}}
h1{{font-size:16px}} .lbl{{font:12px monospace;color:#999;margin-top:6px}} .chart{{font-size:22px;line-height:1.0}}
#replay{{font-size:22px;line-height:1.0}}</style>
<h1>{html.escape(title)}</h1>
<div class="lbl">Live replay of the captured working row at its captured timestamps:</div>
<pre id="replay"></pre><div class="lbl" id="clock"></div>
<div class="lbl">Full Claude Code screen (tmux capture-pane -e) mid-turn:</div>
<pre>{screen}</pre>
<div class="lbl">First six distinct chart frames (each a one-column left scroll):</div>
{strip}
<script>const R={json.dumps(replay)};let i=0;function step(){{const r=R[i];document.getElementById('replay').innerHTML=r.html;
document.getElementById('clock').textContent='t = '+r.t+' ms (frame '+(i+1)+'/'+R.length+')';const n=(i+1)%R.length;
const d=n===0?1200:R[n].t-r.t;i=n;setTimeout(step,d);}}step();</script>"""
    open(path, "w", encoding="utf-8").write(doc)

if __name__ == "__main__":
    main()
