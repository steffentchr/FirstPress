"""Frames First Press Menu's Mac App Store screenshots, and draws the Mac layer
of the iPhone set's last screenshot.

    python3 AppStore/FirstPressMenu/frame.py AppStore/FirstPressMenu

The panel and the Settings window come from the real app, rendered by the
hook into Screenshots/raw/ at three pixels per point. Everything around
them is drawn here: the desktop, the menu bar, the frosted panel behind
the panel's content, and the notification cards. The sample world is
AppStore/FirstPress/demo.json, the same as the iPhone set's.

A notification card is data, so another kind than a new Track (a "Flip the
record" one, say) needs no new code: give it a title, a body and an image
or none, in demo.json.
"""
import html
import json
import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.abspath(sys.argv[1])
APPSTORE = os.path.dirname(HERE)
ROOT = os.path.dirname(APPSTORE)
IPHONE = os.path.join(APPSTORE, "FirstPress")
RAW = os.path.join(HERE, "Screenshots", "raw")
OUT = os.path.join(HERE, "Screenshots", "Mac")
DESIGN = os.path.join(ROOT, "Design")
RENDER_SCALE = 3  # pixels per point in the hook's renders

WORLD = json.load(open(os.path.join(IPHONE, "demo.json")))
DEMO = json.load(open(os.path.join(HERE, "demo.json")))
TMP = tempfile.mkdtemp(prefix="firstpress-menu-frame-")

UI_FONT = "System Font, Helvetica Neue"
CAPTION_FONT = "Helvetica Neue"
MENU_BAR = 28  # pt


def run(*args, data=None):
    return subprocess.run(args, check=True, capture_output=True, input=data).stdout


def svg_to_png(svg_path, png_path, width=None, height=None):
    size = (["-w", str(width)] if width else []) + (["-h", str(height)] if height else [])
    open(png_path, "wb").write(run("rsvg-convert", *size, svg_path))
    return png_path


def size_of(png):
    w, h = run("magick", "identify", "-format", "%w %h", png).decode().split()
    return int(w), int(h)


def esc(text):
    return html.escape(text, quote=True)


def fit(text, width_pt, size_pt, bold=False):
    """Cuts text to roughly fit a width, with an ellipsis, as macOS does."""
    per_char = size_pt * (0.58 if bold else 0.54)
    limit = int(width_pt / per_char)
    return text if len(text) <= limit else text[: max(limit - 1, 1)].rstrip() + "…"


# Shared artwork, rendered once.

def assets():
    a = {}
    wallpaper = os.path.join(TMP, "wallpaper.svg")
    open(wallpaper, "w").write(
        """<svg xmlns="http://www.w3.org/2000/svg" width="1600" height="1000">
  <defs>
    <linearGradient id="g" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#16213d"/><stop offset=".6" stop-color="#2b2350"/><stop offset="1" stop-color="#41264a"/></linearGradient>
    <filter id="b" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="120"/></filter>
  </defs>
  <rect width="1600" height="1000" fill="url(#g)"/>
  <circle cx="260" cy="880" r="380" fill="#e8743b" opacity=".55" filter="url(#b)"/>
  <circle cx="1380" cy="140" r="340" fill="#3a7cc4" opacity=".55" filter="url(#b)"/>
  <circle cx="900" cy="620" r="260" fill="#8a4fb8" opacity=".35" filter="url(#b)"/>
</svg>""")
    a["wallpaper"] = svg_to_png(wallpaper, os.path.join(TMP, "wallpaper.png"), 3200, 2000)
    a["frosted"] = os.path.join(TMP, "wallpaper-frosted.png")
    run("magick", a["wallpaper"], "-blur", "0x60", a["frosted"])
    # The menu-bar icon is a black template image; the menu bar over a dark
    # desktop shows it white, as macOS tints it.
    icon = svg_to_png(os.path.join(DESIGN, "MenuBarIconPlaying.svg"), os.path.join(TMP, "menubar-black.png"), 18 * 4, 18 * 4)
    a["menubar"] = os.path.join(TMP, "menubar.png")
    run("magick", icon, "-channel", "RGB", "-negate", "+channel", a["menubar"])
    a["appicon"] = svg_to_png(os.path.join(DESIGN, "MenuAppIcon.svg"), os.path.join(TMP, "appicon.png"), 256, 256)
    for name in os.listdir(os.path.join(IPHONE, "Covers")):
        if name.endswith(".svg"):
            a["cover:" + name[:-4]] = svg_to_png(os.path.join(IPHONE, "Covers", name), os.path.join(TMP, name[:-4] + ".png"), 400, 400)
    return a


A = assets()


def render(name):
    """One of the hook's renders, copied next to the SVGs: rsvg-convert
    loads images only from the SVG's own folder."""
    path = os.path.join(TMP, name + ".png")
    if not os.path.exists(path):
        shutil.copy(os.path.join(RAW, name + ".png"), path)
    return path


def card_for(spec):
    """A notification card's content: a new Track as the app posts it (the
    title, then the artist and the album, and the cover), or any card
    spelled out with a title, a body and an image or none."""
    if "newTrack" in spec:
        item = WORLD[spec["newTrack"]]
        body = " — ".join(x for x in (item.get("artist"), item.get("album")) if x)
        return {"title": item["title"], "body": body, "image": item.get("cover")}
    return {"title": spec["title"], "body": spec.get("body", ""), "image": spec.get("image")}


# The desktop, drawn in points and scaled.

class Desktop:
    """A Mac desktop of w x h points drawn at s pixels per point: wallpaper,
    a menu bar with First Press Menu's icon, and whatever is open."""

    def __init__(self, w, h, s, ident):
        self.w, self.h, self.s, self.id = w, h, s, ident
        self.defs, self.body = [], []
        clock_w = 104
        self.icon_x = w - 12 - clock_w - 16 - 24 - 16 - 18 - 16 - 18  # left edge of the icon, pt

    def px(self, v):
        return v * self.s

    def background(self):
        """The wallpaper."""
        # The wallpaper always covers a 1200 x 750 pt screen; smaller
        # desktops are crops of its top-right corner, where the menu bar's
        # icons are.
        ww, wh = self.px(1200), self.px(750)
        ox = -self.px(1200 - self.w)
        self.body.append(f'<image x="{ox}" y="0" width="{ww}" height="{wh}" preserveAspectRatio="xMidYMid slice" href="{A["wallpaper"]}"/>')
        self.wall = (ox, ww, wh)

    def frosted(self, x, y, w, h, r, tint, ident):
        """A Liquid-Glass-like pane: the desktop blurred behind it, a light
        tint and a hairline edge, over a soft shadow."""
        X, Y, W, H, R = (self.px(v) for v in (x, y, w, h, r))
        ox, ww, wh = self.wall
        self.defs.append(f'<clipPath id="{ident}"><rect x="{X}" y="{Y}" width="{W}" height="{H}" rx="{R}"/></clipPath>')
        self.defs.append(f'<filter id="{ident}-sh" x="-30%" y="-30%" width="160%" height="160%"><feGaussianBlur stdDeviation="{self.px(14)}"/></filter>')
        self.body.append(f'<rect x="{X}" y="{Y + self.px(8)}" width="{W}" height="{H}" rx="{R}" fill="#000" opacity=".38" filter="url(#{ident}-sh)"/>')
        self.body.append(f'<g clip-path="url(#{ident})"><image x="{ox}" y="0" width="{ww}" height="{wh}" preserveAspectRatio="xMidYMid slice" href="{A["frosted"]}"/></g>')
        self.body.append(f'<rect x="{X}" y="{Y}" width="{W}" height="{H}" rx="{R}" fill="#f6f6f8" opacity="{tint}"/>')
        self.body.append(f'<rect x="{X + .5}" y="{Y + .5}" width="{W - 1}" height="{H - 1}" rx="{R}" fill="none" stroke="#fff" stroke-opacity=".55" stroke-width="{max(self.s * .6, 1)}"/>')

    def menu_bar(self, open_icon=False):
        s, w = self.s, self.w
        self.body.append(f'<rect width="{self.px(w)}" height="{self.px(MENU_BAR)}" fill="#000" opacity=".22"/>')
        cy = MENU_BAR / 2
        text = f'font-family="{UI_FONT}" font-size="{self.px(13)}" font-weight="500" fill="#fff"'
        self.body.append(f'<text x="{self.px(w - 12)}" y="{self.px(cy + 4.5)}" text-anchor="end" {text}>Fri Oct 17  9:41</text>')
        # Battery, then Wi-Fi, drawn plainly.
        bx = w - 12 - 104 - 16 - 24
        self.body.append(
            f'<rect x="{self.px(bx)}" y="{self.px(cy - 5.5)}" width="{self.px(22)}" height="{self.px(11)}" rx="{self.px(3)}" fill="none" stroke="#fff" stroke-opacity=".6" stroke-width="{self.px(1)}"/>'
            f'<rect x="{self.px(bx + 2)}" y="{self.px(cy - 3.5)}" width="{self.px(18)}" height="{self.px(7)}" rx="{self.px(1.5)}" fill="#fff"/>'
            f'<rect x="{self.px(bx + 23)}" y="{self.px(cy - 2)}" width="{self.px(1.6)}" height="{self.px(4)}" rx="{self.px(.8)}" fill="#fff" opacity=".6"/>')
        wx = bx - 16 - 9  # Wi-Fi's centre
        arcs = "".join(
            f'<path d="M {self.px(wx - r)} {self.px(cy + 4 - r * .55)} A {self.px(r)} {self.px(r)} 0 0 1 {self.px(wx + r)} {self.px(cy + 4 - r * .55)}" fill="none" stroke="#fff" stroke-width="{self.px(1.8)}" stroke-linecap="round"/>'
            for r in (8, 5)) + f'<circle cx="{self.px(wx)}" cy="{self.px(cy + 3)}" r="{self.px(1.6)}" fill="#fff"/>'
        self.body.append(arcs)
        ix = self.icon_x
        if open_icon:
            self.body.append(f'<rect x="{self.px(ix - 6)}" y="{self.px(3)}" width="{self.px(30)}" height="{self.px(MENU_BAR - 6)}" rx="{self.px(6)}" fill="#fff" opacity=".24"/>')
        self.body.append(f'<image x="{self.px(ix)}" y="{self.px(cy - 9)}" width="{self.px(18)}" height="{self.px(18)}" href="{A["menubar"]}"/>')

    def panel(self, name):
        """The panel, dropped from the icon, as macOS places a menu-bar
        extra's window."""
        png = render(name)
        pw, ph = (v / RENDER_SCALE for v in size_of(png))
        x = min(self.icon_x + 9 - pw / 2, self.w - 8 - pw)
        y = MENU_BAR + 5
        self.frosted(x, y, pw, ph, 16, ".84", f"{self.id}-panel")
        self.body.append(f'<image x="{self.px(x)}" y="{self.px(y)}" width="{self.px(pw)}" height="{self.px(ph)}" href="{png}"/>')
        return x, y, pw, ph

    def window(self, name, y=110):
        """A titled window, centred, with the frame view's title bar."""
        png = render(name)
        ww, wh = (v / RENDER_SCALE for v in size_of(png))
        x = (self.w - ww) / 2
        X, Y, W, H, R = (self.px(v) for v in (x, y, ww, wh, 16))
        ident = f"{self.id}-{name}"
        self.defs.append(f'<clipPath id="{ident}"><rect x="{X}" y="{Y}" width="{W}" height="{H}" rx="{R}"/></clipPath>')
        self.defs.append(f'<filter id="{ident}-sh" x="-30%" y="-30%" width="160%" height="160%"><feGaussianBlur stdDeviation="{self.px(22)}"/></filter>')
        self.body.append(f'<rect x="{X}" y="{Y + self.px(14)}" width="{W}" height="{H}" rx="{R}" fill="#000" opacity=".5" filter="url(#{ident}-sh)"/>')
        self.body.append(f'<image x="{X}" y="{Y}" width="{W}" height="{H}" href="{png}" clip-path="url(#{ident})"/>')
        self.body.append(f'<rect x="{X}" y="{Y}" width="{W}" height="{H}" rx="{R}" fill="none" stroke="#000" stroke-opacity=".18" stroke-width="{max(self.s * .5, 1)}"/>')

    def notifications(self, specs):
        """Cards stacked from the top right, below the menu bar, in the
        style of a macOS notification: the app's icon, the title in bold,
        the body beneath, and the attached image, if any, on the right."""
        cw, ch, gap = 344, 66, 8
        x = self.w - 12 - cw
        for n, spec in enumerate(specs):
            card = card_for(spec)
            y = MENU_BAR + 8 + n * (ch + gap)
            self.frosted(x, y, cw, ch, 20, ".8", f"{self.id}-note{n}")
            self.body.append(f'<image x="{self.px(x + 10)}" y="{self.px(y + (ch - 40) / 2)}" width="{self.px(40)}" height="{self.px(40)}" href="{A["appicon"]}"/>')
            text_x = x + 58
            text_w = cw - 58 - 14 - (52 if card["image"] else 0)
            title = esc(fit(card["title"], text_w, 13, bold=True))
            body = esc(fit(card["body"], text_w, 13))
            self.body.append(f'<text x="{self.px(text_x)}" y="{self.px(y + 29)}" font-family="{UI_FONT}" font-size="{self.px(13)}" font-weight="700" fill="#1d1d1f">{title}</text>')
            self.body.append(f'<text x="{self.px(text_x)}" y="{self.px(y + 46)}" font-family="{UI_FONT}" font-size="{self.px(13)}" fill="#3c3c43" fill-opacity=".85">{body}</text>')
            if card["image"]:
                ix, iy, side = x + cw - 14 - 42, y + (ch - 42) / 2, 42
                ident = f"{self.id}-note{n}-img"
                self.defs.append(f'<clipPath id="{ident}"><rect x="{self.px(ix)}" y="{self.px(iy)}" width="{self.px(side)}" height="{self.px(side)}" rx="{self.px(7)}"/></clipPath>')
                self.body.append(f'<image x="{self.px(ix)}" y="{self.px(iy)}" width="{self.px(side)}" height="{self.px(side)}" href="{A["cover:" + card["image"]]}" clip-path="url(#{ident})"/>')

    def svg(self):
        """The desktop as a group in its own pixel space, clipped to it."""
        W, H = self.px(self.w), self.px(self.h)
        return (f'<defs><clipPath id="{self.id}-screen"><rect width="{W}" height="{H}"/></clipPath>{"".join(self.defs)}</defs>'
                f'<g clip-path="url(#{self.id}-screen)">{"".join(self.body)}</g>')


def desktop(w, h, s, ident, scene):
    d = Desktop(w, h, s, ident)
    d.background()
    has_panel = bool(scene.get("panel"))
    d.menu_bar(open_icon=has_panel)
    if scene.get("window"):
        d.window(scene["window"])
    if has_panel:
        d.panel(scene["panel"])
    d.notifications(scene.get("notifications", []))
    return d


def to_png(svg_text, path, alpha=False):
    svg_path = os.path.join(TMP, os.path.basename(path) + ".svg")
    open(svg_path, "w").write(svg_text)
    png = run("rsvg-convert", svg_path)
    args = ["magick", "-"] + ([] if alpha else ["-alpha", "remove", "-alpha", "off"]) + ["-define", "png:exclude-chunks=date,time", path]
    run(*args, data=png)


def caption_svg(lines, W, y, size, gap):
    tspans = "".join(f'<tspan x="{W // 2}" dy="{0 if i == 0 else gap}">{esc(l)}</tspan>' for i, l in enumerate(lines))
    return f'<text y="{y}" text-anchor="middle" font-family="{CAPTION_FONT}" font-weight="700" font-size="{size}" fill="#fff">{tspans}</text>'


BACKGROUND = '<linearGradient id="bg" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#f08a52"/><stop offset=".55" stop-color="#d4551f"/><stop offset="1" stop-color="#9a3410"/></linearGradient>'


def screen(d, x, y, bezel, radius):
    """A Mac's screen in a black bezel, the desktop inside it."""
    W, H = d.px(d.w), d.px(d.h)
    return (f'<filter id="{d.id}-bz" x="-20%" y="-20%" width="140%" height="140%"><feGaussianBlur stdDeviation="30"/></filter>'
            f'<rect x="{x - bezel}" y="{y - bezel + 30}" width="{W + 2 * bezel}" height="{H + 2 * bezel}" rx="{radius}" fill="#000" opacity=".45" filter="url(#{d.id}-bz)"/>'
            f'<rect x="{x - bezel}" y="{y - bezel}" width="{W + 2 * bezel}" height="{H + 2 * bezel}" rx="{radius}" fill="#0d0c0b"/>'
            f'<g transform="translate({x} {y})">{d.svg()}</g>')


def mac_screenshots():
    """2880 x 1800, the largest Mac size App Store Connect takes: the
    caption above, and below it a Mac screen of 2400 x 1500 pixels at
    2.2 pixels per point, so the panel reads at store-thumbnail size,
    running off the bottom edge as the iPhone set's phones nearly do."""
    os.makedirs(OUT, exist_ok=True)
    W, H = 2880, 1800
    for n, scene in enumerate(DEMO["screenshots"], 1):
        name = f"{n:02d}-{scene['scene']}"
        d = desktop(2400 / 2.2, 1500 / 2.2, 2.2, f"s{n}", scene)
        lines = scene["caption"].split("\n")
        svg = (f'<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="{W}" height="{H}">'
               f'<defs>{BACKGROUND}</defs><rect width="{W}" height="{H}" fill="url(#bg)"/>'
               + caption_svg(lines, W, 170 if len(lines) > 1 else 220, 96, 116)
               + screen(d, 240, 420, 28, 52) + '</svg>')
        to_png(svg, os.path.join(OUT, name + ".png"))
        print("framed", name)


def iphone_promo():
    """The Mac layer of the iPhone set's last screenshot, 1320 x 2868 and
    transparent: a crop of the Mac's screen with a new-Track notification,
    and the panel's Rooms view below it. The iPhone frame step puts the
    caption and the background around it."""
    promo = DEMO["promo"]
    W, H = 1320, 2868
    d = Desktop(590, 330, 2, "promo")
    d.background()
    d.menu_bar(open_icon=True)
    d.notifications(promo.get("notifications", []))
    x, y = (W - d.px(d.w)) // 2, 600
    png = render(promo["panel"])
    pw, ph = size_of(png)
    ps = 2.6 / RENDER_SCALE
    PW, PH = pw * ps, ph * ps
    PX, PY = (W - PW) / 2, y + d.px(d.h) - 40
    panel = (f'<defs><clipPath id="pp"><rect x="{PX}" y="{PY}" width="{PW}" height="{PH}" rx="{16 * 2.6}"/></clipPath>'
             f'<filter id="ps" x="-30%" y="-30%" width="160%" height="160%"><feGaussianBlur stdDeviation="40"/></filter></defs>'
             f'<rect x="{PX}" y="{PY + 30}" width="{PW}" height="{PH}" rx="{16 * 2.6}" fill="#000" opacity=".4" filter="url(#ps)"/>'
             f'<rect x="{PX}" y="{PY}" width="{PW}" height="{PH}" rx="{16 * 2.6}" fill="#f6f6f8" opacity=".94"/>'
             f'<image x="{PX}" y="{PY}" width="{PW}" height="{PH}" href="{png}" clip-path="url(#pp)"/>')
    svg = (f'<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="{W}" height="{H}">'
           + screen(d, x, y, 22, 48) + panel + '</svg>')
    # Named as the iPhone frame step names it: its place in the iPhone
    # set, then its scene.
    n, scene = next((n, x) for n, x in enumerate(WORLD["screenshots"], 1) if x.get("from") == "FirstPressMenu")
    path = os.path.join(IPHONE, "Screenshots", "raw", f"{n:02d}-{scene['scene']}.png")
    to_png(svg, path, alpha=True)
    print("drew", os.path.relpath(path, APPSTORE))


mac_screenshots()
iphone_promo()
