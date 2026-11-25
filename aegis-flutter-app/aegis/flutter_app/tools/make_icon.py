"""Genera el logo 3D de AEGIS (maestro 1024 px) y los iconos de Android. Requiere Pillow.
Uso:  python tools/make_icon.py   ->  assets/logo.png  y  android_icons/mipmap-*/ic_launcher*.png"""
import math, os
from PIL import Image, ImageChops, ImageDraw, ImageFilter

S = 2048  # se dibuja al doble y se reduce (bordes suaves)
K = S / 1024


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def vgrad(size, top, bottom):
    g = Image.new("RGB", (1, size[1]))
    for y in range(size[1]):
        g.putpixel((0, y), lerp(top, bottom, y / (size[1] - 1)))
    return g.resize(size)


def mask_of(draw_fn):
    m = Image.new("L", (S, S), 0)
    draw_fn(ImageDraw.Draw(m))
    return m


def shield_pts(cx, top, w, side_end, tip, inset=0.0):
    pts = []
    n = 120
    half = w / 2 - inset
    for i in range(n + 1):  # borde superior (arco suave)
        t = -1 + 2 * i / n
        pts.append((cx + t * half, top + inset + 46 * (t * t)))
    for i in range(n, -1, -1):  # borde inferior hasta la punta
        t = -1 + 2 * i / n
        y = side_end + (tip - side_end - inset) * (1 - abs(t) ** 1.75) ** 1.15
        pts.append((cx + t * half, y))
    return [(x * K, y * K) for x, y in pts]


def glow(img, mask, color, radius, strength=1.0):
    layer = Image.new("RGBA", (S, S), color + (0,))
    a = mask.filter(ImageFilter.GaussianBlur(radius * K)).point(lambda v: int(v * strength))
    layer.putalpha(a)
    return Image.alpha_composite(img, layer)


def build():
    # --- fondo: squircle con degradado profundo + resplandor
    bg = vgrad((S, S), (46, 24, 120), (8, 10, 36)).convert("RGBA")
    rg = Image.new("L", (S, S), 0)
    ImageDraw.Draw(rg).ellipse((S * 0.1, S * 0.05, S * 0.9, S * 0.75), fill=255)
    bg = glow(bg, rg, (120, 70, 255), 150, 0.55)
    img = bg

    # --- pulsera (anillo grafito) detrás del escudo
    ring = mask_of(lambda d: d.ellipse((130 * K, 330 * K, 894 * K, 930 * K), fill=255))
    ring = ImageChops.subtract(ring, mask_of(lambda d: d.ellipse((235 * K, 435 * K, 789 * K, 825 * K), fill=255)))
    band = vgrad((S, S), (96, 100, 120), (18, 20, 30)).convert("RGBA")
    shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    shadow.putalpha(ring.filter(ImageFilter.GaussianBlur(26 * K)).point(lambda v: int(v * 0.7)))
    img = Image.alpha_composite(img, ImageChops.offset(shadow, 0, int(24 * K)))
    band.putalpha(ring)
    img = Image.alpha_composite(img, band)
    hl = mask_of(lambda d: d.ellipse((150 * K, 345 * K, 874 * K, 915 * K), outline=255, width=int(10 * K)))
    hl = ImageChops.multiply(hl, mask_of(lambda d: d.rectangle((0, 0, S, 520 * K), fill=255)))
    h = Image.new("RGBA", (S, S), (255, 255, 255, 0))
    h.putalpha(hl.filter(ImageFilter.GaussianBlur(3 * K)).point(lambda v: int(v * 0.45)))
    img = Image.alpha_composite(img, h)

    # --- escudo 3D: sombra, canto, cara biselada, brillo
    outer = shield_pts(512, 190, 560, 520, 880)
    m_out = mask_of(lambda d: d.polygon(outer, fill=255))
    sh = Image.new("RGBA", (S, S), (0, 0, 20, 0))
    sh.putalpha(m_out.filter(ImageFilter.GaussianBlur(34 * K)).point(lambda v: int(v * 0.8)))
    img = Image.alpha_composite(img, ImageChops.offset(sh, 0, int(34 * K)))
    rim = vgrad((S, S), (190, 245, 255), (20, 70, 200)).convert("RGBA")
    rim.putalpha(m_out)
    img = Image.alpha_composite(img, rim)
    face_pts = shield_pts(512, 190, 560, 520, 880, inset=26)
    m_face = mask_of(lambda d: d.polygon(face_pts, fill=255))
    face = vgrad((S, S), (40, 140, 255), (10, 40, 150)).convert("RGBA")
    face.putalpha(m_face)
    img = Image.alpha_composite(img, face)
    inner_pts = shield_pts(512, 190, 560, 520, 880, inset=62)
    m_in = mask_of(lambda d: d.polygon(inner_pts, fill=255))
    deep = vgrad((S, S), (14, 22, 92), (30, 120, 235)).convert("RGBA")
    deep.putalpha(m_in)
    img = Image.alpha_composite(img, deep)

    # brillo especular (arriba-izquierda) recortado al escudo
    spec = mask_of(lambda d: d.ellipse((250 * K, 120 * K, 700 * K, 560 * K), fill=255)).filter(ImageFilter.GaussianBlur(60 * K))
    spec = ImageChops.multiply(spec, m_face).point(lambda v: int(v * 0.42))
    s_l = Image.new("RGBA", (S, S), (255, 255, 255, 0))
    s_l.putalpha(spec)
    img = Image.alpha_composite(img, s_l)

    # --- latido (ECG) con resplandor + LED
    ecg = [(310, 540), (410, 540), (450, 460), (505, 650), (560, 400), (600, 560), (640, 540), (715, 540)]
    pts = [(x * K, y * K) for x, y in ecg]
    m_line = mask_of(lambda d: d.line(pts, fill=255, width=int(30 * K), joint="curve"))
    img = glow(img, m_line, (255, 60, 110), 26, 1.0)
    line = Image.new("RGBA", (S, S), (255, 240, 245, 0))
    line.putalpha(m_line)
    img = Image.alpha_composite(img, line)
    core = mask_of(lambda d: d.line(pts, fill=255, width=int(14 * K), joint="curve"))
    c = Image.new("RGBA", (S, S), (255, 255, 255, 0))
    c.putalpha(core)
    img = Image.alpha_composite(img, c)
    led = mask_of(lambda d: d.ellipse((512 * K - 20 * K, 735 * K - 20 * K, 512 * K + 20 * K, 735 * K + 20 * K), fill=255))
    img = glow(img, led, (255, 40, 70), 22, 1.0)
    l2 = Image.new("RGBA", (S, S), (255, 70, 90, 0))
    l2.putalpha(led)
    img = Image.alpha_composite(img, l2)

    # --- recorte squircle
    sq = mask_of(lambda d: d.rounded_rectangle((0, 0, S - 1, S - 1), radius=int(230 * K), fill=255))
    img.putalpha(sq)
    return img.resize((1024, 1024), Image.LANCZOS)


if __name__ == "__main__":
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    master = build()
    os.makedirs(os.path.join(root, "assets"), exist_ok=True)
    master.resize((512, 512), Image.LANCZOS).save(os.path.join(root, "assets", "logo.png"))
    master.save(os.path.join(root, "assets", "logo_1024.png"))
    for name, px in {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}.items():
        d = os.path.join(root, "android_icons", f"mipmap-{name}")
        os.makedirs(d, exist_ok=True)
        ic = master.resize((px, px), Image.LANCZOS)
        ic.save(os.path.join(d, "ic_launcher.png"))
        circ = Image.new("L", (px * 4, px * 4), 0)
        ImageDraw.Draw(circ).ellipse((0, 0, px * 4 - 1, px * 4 - 1), fill=255)
        circ = circ.resize((px, px), Image.LANCZOS)
        r = ic.copy()
        r.putalpha(ImageChops.multiply(r.getchannel("A"), circ))
        r.save(os.path.join(d, "ic_launcher_round.png"))
    print("ok")
