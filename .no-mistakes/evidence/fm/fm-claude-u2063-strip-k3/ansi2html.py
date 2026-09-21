#!/usr/bin/env python3
"""Render tmux `capture-pane -e` frames (SGR only) as one HTML page of terminal panels."""
import html
import re
import sys

BASIC = ["#000000", "#cd3131", "#0dbc79", "#e5e510", "#2472c8", "#bc3fbc", "#11a8cd", "#e5e5e5"]
BRIGHT = ["#666666", "#f14c4c", "#23d18b", "#f5f543", "#3b8eea", "#d670d6", "#29b8db", "#ffffff"]


def xterm256(n):
    if n < 8:
        return BASIC[n]
    if n < 16:
        return BRIGHT[n - 8]
    if n < 232:
        n -= 16
        steps = [0, 95, 135, 175, 215, 255]
        return "#%02x%02x%02x" % (steps[n // 36], steps[(n // 6) % 6], steps[n % 6])
    v = 8 + (n - 232) * 10
    return "#%02x%02x%02x" % (v, v, v)


def render(text):
    out = []
    state = {"fg": None, "bg": None, "bold": False, "dim": False, "italic": False, "inverse": False, "underline": False}
    pos = 0
    for m in re.finditer(r"\x1b\[([0-9;:]*)m", text):
        out.append(span(text[pos:m.start()], state))
        apply(m.group(1), state)
        pos = m.end()
    out.append(span(text[pos:], state))
    return "".join(out)


def apply(params, st):
    codes = [int(p) if p else 0 for p in re.split(r"[;:]", params)] if params else [0]
    i = 0
    while i < len(codes):
        c = codes[i]
        if c == 0:
            st.update(fg=None, bg=None, bold=False, dim=False, italic=False, inverse=False, underline=False)
        elif c == 1:
            st["bold"] = True
        elif c == 2:
            st["dim"] = True
        elif c == 3:
            st["italic"] = True
        elif c == 4:
            st["underline"] = True
        elif c == 7:
            st["inverse"] = True
        elif c == 22:
            st["bold"] = st["dim"] = False
        elif c == 23:
            st["italic"] = False
        elif c == 24:
            st["underline"] = False
        elif c == 27:
            st["inverse"] = False
        elif 30 <= c <= 37:
            st["fg"] = BASIC[c - 30]
        elif 90 <= c <= 97:
            st["fg"] = BRIGHT[c - 90]
        elif 40 <= c <= 47:
            st["bg"] = BASIC[c - 40]
        elif 100 <= c <= 107:
            st["bg"] = BRIGHT[c - 100]
        elif c == 39:
            st["fg"] = None
        elif c == 49:
            st["bg"] = None
        elif c in (38, 48) and i + 1 < len(codes):
            key = "fg" if c == 38 else "bg"
            if codes[i + 1] == 5 and i + 2 < len(codes):
                st[key] = xterm256(codes[i + 2])
                i += 2
            elif codes[i + 1] == 2 and i + 4 < len(codes):
                st[key] = "#%02x%02x%02x" % tuple(codes[i + 2:i + 5])
                i += 4
        i += 1


def span(chunk, st):
    if not chunk:
        return ""
    fg, bg = st["fg"], st["bg"]
    if st["inverse"]:
        fg, bg = (bg or "#1e1e1e"), (fg or "#d4d4d4")
    css = []
    if fg:
        css.append("color:%s" % fg)
    if bg:
        css.append("background:%s" % bg)
    if st["bold"]:
        css.append("font-weight:bold")
    if st["dim"]:
        css.append("opacity:.6")
    if st["italic"]:
        css.append("font-style:italic")
    if st["underline"]:
        css.append("text-decoration:underline")
    body = html.escape(chunk)
    return '<span style="%s">%s</span>' % (";".join(css), body) if css else body


def main():
    title = sys.argv[1]
    panels = []
    for arg in sys.argv[2:]:
        label, path = arg.split("=", 1)
        with open(path, encoding="utf-8", errors="replace") as fh:
            raw = fh.read()
        panels.append('<section><h2>%s</h2><pre class="term">%s</pre></section>' % (html.escape(label), render(raw)))
    print("""<!doctype html><html><head><meta charset="utf-8"><title>%s</title><style>
body{margin:0;padding:24px;background:#0f1115;color:#e6e6e6;font-family:system-ui,sans-serif}
h1{font-size:18px;margin:0 0 16px}
h2{font-size:14px;font-weight:600;margin:0 0 8px;color:#c9d1d9}
section{margin:0 0 24px;min-width:0}
.term{margin:0;padding:12px 14px;background:#1e1e1e;color:#d4d4d4;border-radius:6px;
font:13px/1.25 'DejaVu Sans Mono','Cascadia Mono',Menlo,Consolas,monospace;white-space:pre;overflow-x:auto;
width:max-content;max-width:100%%;box-sizing:border-box}
</style></head><body><h1>%s</h1>%s</body></html>""" % (html.escape(title), html.escape(title), "".join(panels)))


if __name__ == "__main__":
    main()
