"""White Rabbit cursor set: cyan line-art with a soft glow (red for "forbidden").

Closed shapes are filled with a near-black green so they stay visible on light
pages; open line work (beams, arrows, crosshair) stays unfilled.

Every cursor is drawn on a 32x32 grid and rendered at each size in SIZES.
Run: python3 gen.py <output-cursors-dir>
"""
import math, os, struct, subprocess, sys
import numpy as np
from PIL import Image

CYAN, RED = "#5ef0ee", "#e8645a"
FILL = "#06120a"  # near-black with a hint of green
SIZES = [24, 32, 48, 64, 96]
OUT = sys.argv[1]
W = 2.0  # main line width

def S(d, w=W, c=CYAN, join="round", tf="", fill="none"):
    t = f' transform="{tf}"' if tf else ""
    return (f'<path d="{d}" fill="{fill}" stroke="{c}" stroke-width="{w}" '
            f'stroke-linejoin="{join}" stroke-linecap="round" stroke-miterlimit="4"{t}/>')
def F(d, c=CYAN, tf=""):
    t = f' transform="{tf}"' if tf else ""
    return f'<path d="{d}" fill="{c}"{t}/>'
def G(body, tf):
    return f'<g transform="{tf}">{body}</g>'
def arc(cx, cy, r, a0, a1):
    """Arc from a0 to a1 degrees, clockwise from 12 o'clock."""
    def pt(a):
        a = math.radians(a); return cx + r*math.sin(a), cy - r*math.cos(a)
    (x0, y0), (x1, y1) = pt(a0), pt(a1)
    big = 1 if (a1 - a0) % 360 > 180 else 0
    return f"M{x0:.2f},{y0:.2f} A{r},{r} 0 {big},1 {x1:.2f},{y1:.2f}"

# Pieces
ARROW = "M3.6,3.6 L23.2,14.4 L14.4,23.2 Z"
def pointer(): return S(ARROW, 2.2, fill=FILL)
HAND = ("M8.5,2.5 L11.5,2.5 L11.5,9.5 L21,9.5 L26,14.5 L26,26.5 L7,26.5 "
        "L4,22.5 L4,16 L8.5,16 Z")
def hand(): return S(HAND, join="miter", fill=FILL)
def head(tf):  # open chevron arrowhead pointing up, tip at origin
    return S("M-3.6,3.6 L0,0 L3.6,3.6", 1.9, tf=tf)
def line_arrow(x0, y0, x1, y1, both=True):
    ang = math.degrees(math.atan2(x1 - x0, -(y1 - y0)))
    out = S(f"M{x0},{y0} L{x1},{y1}", 1.7) + head(f"translate({x1},{y1}) rotate({ang})")
    if both:
        out += head(f"translate({x0},{y0}) rotate({ang+180})")
    return out
def qmark(x, y, s=1.0):  # angular question mark, top-left at (x,y)
    return G(S("M0,2 L0,0 L4.6,0 L4.6,4.4 L2.3,6 L2.3,8", 1.6, join="miter")
             + F("M1.4,9.8 h1.8 v1.8 h-1.8 Z"), f"translate({x},{y}) scale({s})")

def ibeam(tf=""):
    body = (S("M16,8.5 L16,23.5", 1.2)
            + F("M14.9,3.5 h2.2 v5.5 h-2.2 Z M14.9,23 h2.2 v5.5 h-2.2 Z")
            + S("M15.2,4 h1.6 M15.2,28 h1.6", 1.6))
    return G(body, tf) if tf else body

def move(r=10.5):
    out = line_arrow(16, 3.5, 16, 28.5) + line_arrow(3.5, 16, 28.5, 16)
    for q in range(4):
        out += S(arc(16, 16, r, q*90 + 22, q*90 + 68), 1.9)
    return out

def resize_edge(rot):  # arrow running up into an edge bar, rotated about the centre
    return G(S("M8,3.5 L24,3.5", 2.2) + line_arrow(16, 27, 16, 7.5, both=False),
             f"rotate({rot},16,16)")
def resize_corner(rot):  # arrow into a top-left L bracket
    return G(S("M3.5,15 L3.5,3.5 L15,3.5", 2.2, join="miter")
             + line_arrow(25, 25, 8, 8, both=False), f"rotate({rot},16,16)")
def split(rot):
    return G(S("M16,4 L16,28", 2.2) + line_arrow(12.5, 16, 3.5, 16, both=False)
             + line_arrow(19.5, 16, 28.5, 16, both=False), f"rotate({rot},16,16)")
def lens(sign):
    out = S(arc(13, 13, 8, 0, 359.9) + " Z", 2.0, fill=FILL) + S("M18.8,18.8 L27.5,27.5", 2.6)
    out += S("M9.5,13 L16.5,13", 1.8)
    if sign == "+":
        out += S("M13,9.5 L13,16.5", 1.8)
    return out

# Badges sit top-right; with the hand they clear the raised finger.
SHIELD = G(S("M0,0 L6,0 L6,5.2 L3,8.4 L0,5.2 Z", 1.6, join="miter", fill=FILL), "translate(22.5,1.5)")
STACK = G(S("M1,0 h4 v3.6 h-4 Z M0,5.4 h6 v5 h-6 Z", 1.6, join="miter", fill=FILL), "translate(22.5,1.2)")
def small(el):  # shrink a full-size cursor drawing towards its top-left
    return G(el, "translate(1,1) scale(0.78)")
HAND_SMALL = G(hand(), "translate(-1,4) scale(0.85)")  # makes room for a badge

CURSORS = {
    "default":       ((3, 3), pointer()),
    "pointer":       ((10, 2), hand()),
    "grab":          ((16, 14), S("M7,16 L7,6 L11,6 L11,4 L15,4 L15,5 L19,5 L19,8 L23,8 L23,12 "
                                  "L26,15 L26,26.5 L7,26.5 L4,22.5 L4,16 Z", join="miter", fill=FILL)
                      + S("M11,6 L11,12 M15,5 L15,12 M19,8 L19,12", 1.4)),
    "grabbing":      ((16, 16), S("M7,16 L7,10 L23,10 L26,13 L26,26.5 L7,26.5 L4,22.5 L4,16 Z", join="miter", fill=FILL)
                      + S("M11,10 L11,14 M15,10 L15,14 M19,10 L19,14", 1.4)),
    "text":          ((16, 16), ibeam()),
    "vertical-text": ((16, 16), ibeam("rotate(90,16,16)")),
    "crosshair":     ((16, 16), S("M16,4 L16,28 M4,16 L28,16", 2.2)),
    "cell":          ((16, 16), S("M16,5 L16,27 M5,16 L27,16", 2.2) + S("M12,12 h8 v8 h-8 Z", 1.6, join="miter", fill=FILL)),
    "X_cursor":      ((16, 16), S("M7,7 L25,25 M25,7 L7,25", 2.4)),
    "all-resize":    ((16, 16), move()),
    "all-scroll":    ((16, 16), head("translate(16,4)") + head("translate(16,28) rotate(180)")
                      + head("translate(4,16) rotate(-90)") + head("translate(28,16) rotate(90)")
                      + S(arc(16, 16, 3, 0, 359.9) + " Z", 1.8, fill=FILL)),
    "ns-resize":     ((16, 16), line_arrow(16, 3.5, 16, 28.5)),
    "ew-resize":     ((16, 16), line_arrow(3.5, 16, 28.5, 16)),
    "nwse-resize":   ((16, 16), line_arrow(6, 6, 26, 26)),
    "nesw-resize":   ((16, 16), line_arrow(26, 6, 6, 26)),
    "n-resize":      ((16, 3.5), resize_edge(0)),
    "e-resize":      ((28.5, 16), resize_edge(90)),
    "s-resize":      ((16, 28.5), resize_edge(180)),
    "w-resize":      ((3.5, 16), resize_edge(270)),
    "nw-resize":     ((3.5, 3.5), resize_corner(0)),
    "ne-resize":     ((28.5, 3.5), resize_corner(90)),
    "se-resize":     ((28.5, 28.5), resize_corner(180)),
    "sw-resize":     ((3.5, 28.5), resize_corner(270)),
    "col-resize":    ((16, 16), split(0)),
    "row-resize":    ((16, 16), split(90)),
    "not-allowed":   ((16, 16), S(arc(16, 16, 10, 0, 359.9) + " Z", 2.8, RED, fill=FILL)
                      + S("M11.4,11.4 L20.6,20.6 M20.6,11.4 L11.4,20.6", 2.6, RED)),
    "help":          ((3.4, 9.4), G(pointer(), "translate(0,6) scale(0.92)") + qmark(23, 1.5)),
    "alias":         ((8.4, 5.5), HAND_SMALL + SHIELD),
    "copy":          ((8.4, 5.5), HAND_SMALL + STACK),
    "no-drop":       ((3, 3), small(pointer()) + S(arc(24.5, 24.5, 5, 0, 359.9) + " Z", 1.8, RED, fill=FILL)
                      + S("M22.3,22.3 L26.7,26.7 M26.7,22.3 L22.3,26.7", 1.6, RED)),
    "context-menu":  ((3, 3), small(pointer()) + S("M18,17 h10.5 v11 h-10.5 Z", 1.6, join="miter", fill=FILL)
                      + S("M20.5,20.5 h5.5 M20.5,23 h5.5 M20.5,25.5 h5.5", 1.2)),
    "zoom-in":       ((13, 13), lens("+")),
    "zoom-out":      ((13, 13), lens("-")),
}
FRAMES = 12
def spinner(cx, cy, r, w, i):
    a = i * 360 / FRAMES
    return "".join(S(arc(cx, cy, r, a + k*120, a + k*120 + 75), w) for k in range(3))
ANIMATED = {
    "wait":     ((16, 16), lambda i: spinner(16, 16, 10, 2.4, i)),
    "progress": ((3, 3), lambda i: small(pointer()) + spinner(24, 24, 5, 1.8, i)),
}

def svg(body):
    glow = body.replace(f'fill="{FILL}"', 'fill="none"')  # glow from the lines only
    return ('<svg xmlns="http://www.w3.org/2000/svg" width="32" height="32" viewBox="0 0 32 32">'
            '<defs><filter id="g" x="-30%" y="-30%" width="160%" height="160%">'
            '<feGaussianBlur stdDeviation="1.0"/></filter></defs>'
            f'<g opacity="0.45" filter="url(#g)">{glow}</g>{body}</svg>')

def render(text, size, tag):
    src, png = f"tmp/{tag}.svg", f"tmp/{tag}-{size}.png"
    open(src, "w").write(text)
    subprocess.run(["magick", "-background", "none", "-density", str(96*size/32), src,
                    "-resize", f"{size}x{size}!", png], check=True)
    return png

def argb(png):
    a = np.asarray(Image.open(png).convert("RGBA")).astype(np.float64)
    al = a[..., 3:4] / 255
    pm = np.concatenate([a[..., :3]*al, a[..., 3:4]], -1).round().astype(np.uint32)
    return ((pm[..., 3] << 24) | (pm[..., 0] << 16) | (pm[..., 1] << 8) | pm[..., 2]).astype("<u4").tobytes()

def write_xcursor(path, hot, frames, delay=0):
    imgs = [(s, round(hot[0]*s/32), round(hot[1]*s/32), f[s]) for s in SIZES for f in frames]
    toc, chunks, pos = b"", b"", 16 + 12*len(imgs)
    for s, xh, yh, px in imgs:
        toc += struct.pack("<III", 0xfffd0002, s, pos)
        c = struct.pack("<IIIIIIIII", 36, 0xfffd0002, s, 1, s, s, xh, yh, delay) + px
        chunks += c; pos += len(c)
    open(path, "wb").write(b"Xcur" + struct.pack("<III", 16, 0x10000, len(imgs)) + toc + chunks)

os.makedirs("tmp", exist_ok=True); os.makedirs(OUT, exist_ok=True)
for name, (hot, body) in CURSORS.items():
    write_xcursor(f"{OUT}/{name}", hot, [{s: argb(render(svg(body), s, name)) for s in SIZES}])
for name, (hot, fn) in ANIMATED.items():
    frames = [{s: argb(render(svg(fn(i)), s, f"{name}{i}")) for s in SIZES} for i in range(FRAMES)]
    write_xcursor(f"{OUT}/{name}", hot, frames, delay=60)

ALIASES = {
    "default": "left_ptr arrow top_left_arrow move dnd-move dnd-none",
    "pointer": "hand2 hand pointing_hand",
    "grab": "hand1 openhand",
    "grabbing": "closedhand dnd-grabbing",
    "text": "xterm ibeam",
    "crosshair": "cross cross_reverse diamond_cross tcross",
    "cell": "plus",
    "X_cursor": "pirate",
    "ns-resize": "sb_v_double_arrow size_ver v_double_arrow",
    "ew-resize": "sb_h_double_arrow size_hor h_double_arrow",
    "nwse-resize": "bd_double_arrow size_fdiag",
    "nesw-resize": "fd_double_arrow size_bdiag",
    "n-resize": "top_side", "s-resize": "bottom_side", "e-resize": "right_side", "w-resize": "left_side",
    "nw-resize": "top_left_corner", "ne-resize": "top_right_corner",
    "se-resize": "bottom_right_corner", "sw-resize": "bottom_left_corner",
    "col-resize": "split_h size_hor_split", "row-resize": "split_v size_ver_split",
    "all-resize": "fleur size_all",
    "not-allowed": "forbidden crossed_circle circle",
    "no-drop": "dnd-no-drop",
    "help": "question_arrow whats_this left_ptr_help dnd-ask",
    "copy": "dnd-copy", "alias": "dnd-link link",
    "wait": "watch", "progress": "left_ptr_watch half-busy",
}
for target, names in ALIASES.items():
    for n in names.split():
        p = f"{OUT}/{n}"
        if os.path.lexists(p): os.remove(p)
        os.symlink(target, p)

# Contact sheet of the 48px renders on a dark checkerboard.
names = list(CURSORS) + ["wait0", "progress0"]
cols = 9; rows = math.ceil(len(names)/cols)
sheet = Image.new("RGBA", (cols*64, rows*64))
for i in range(cols*rows):
    x, y = (i % cols)*64, (i//cols)*64
    sheet.paste((26, 32, 28, 255) if (i + i//cols) % 2 else (16, 20, 18, 255), (x, y, x+64, y+64))
for i, n in enumerate(names):
    sheet.alpha_composite(Image.open(f"tmp/{n}-48.png"), ((i % cols)*64 + 8, (i//cols)*64 + 8))
sheet.resize((cols*128, rows*128), Image.NEAREST).save("sheet.png")
