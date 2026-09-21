#!/usr/bin/env python3
"""Render one tmux `capture-pane -e` frame (SGR only) as an SVG terminal image."""
import html
import re
import sys

sys.path.insert(0, __file__.rsplit("/", 1)[0])
from importlib import import_module

a2h = import_module("ansi2html")

CW, LH, FS, PAD = 8.4, 17, 14, 14


def runs(line):
    st = {"fg": None, "bg": None, "bold": False, "dim": False, "italic": False, "inverse": False, "underline": False}
    col, pos, out = 0, 0, []
    for m in list(re.finditer(r"\x1b\[([0-9;:]*)m", line)) + [None]:
        end = m.start() if m else len(line)
        chunk = line[pos:end]
        if chunk:
            out.append((col, chunk, dict(st)))
            col += len(chunk)
        if m:
            a2h.apply(m.group(1), st)
            pos = m.end()
    return out, col


def main():
    title, src, dst = sys.argv[1], sys.argv[2], sys.argv[3]
    lines = open(src, encoding="utf-8", errors="replace").read().rstrip("\n").split("\n")
    parsed = [runs(l) for l in lines]
    cols = max([c for _, c in parsed] + [80])
    width = int(cols * CW + 2 * PAD)
    top = PAD + 26
    height = int(top + len(lines) * LH + PAD)
    body = []
    for row, (rs, _) in enumerate(parsed):
        y = top + row * LH
        for col, chunk, st in rs:
            fg, bg = st["fg"] or "#d4d4d4", st["bg"]
            if st["inverse"]:
                fg, bg = (st["bg"] or "#1e1e1e"), (st["fg"] or "#d4d4d4")
            if bg:
                body.append('<rect x="%.1f" y="%.1f" width="%.1f" height="%d" fill="%s"/>' % (PAD + col * CW, y, len(chunk) * CW, LH, bg))
            if chunk.strip():
                attrs = 'fill="%s"' % fg
                if st["bold"]:
                    attrs += ' font-weight="bold"'
                if st["dim"]:
                    attrs += ' opacity="0.6"'
                if st["italic"]:
                    attrs += ' font-style="italic"'
                # One text node per cell keeps box-drawing and block glyphs on the grid.
                for k, ch in enumerate(chunk):
                    if ch != " ":
                        body.append('<text x="%.1f" y="%.1f" %s>%s</text>' % (PAD + (col + k) * CW, y + 13, attrs, html.escape(ch)))
    svg = ('<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d">'
           '<rect width="100%%" height="100%%" rx="8" fill="#1e1e1e"/>'
           '<text x="%d" y="%d" fill="#9aa4b2" font-family="DejaVu Sans, sans-serif" font-size="13">%s</text>'
           '<g font-family="DejaVu Sans Mono, Menlo, Consolas, monospace" font-size="%d" xml:space="preserve">%s</g></svg>'
           % (width, height, width, height, PAD, PAD + 12, html.escape(title), FS, "".join(body)))
    open(dst, "w", encoding="utf-8").write(svg)


main()
