#!/usr/bin/env python3
"""
SilicIA – Apple Mac App Store screenshot generator
Produces slides at 2880×1800, in English and French.
"""

from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter, ImageFont

# ── Paths ─────────────────────────────────────────────────────────────────────
HERE     = Path(__file__).parent
FONT_DIR = Path.home() / "Library/Fonts"
OUT_DIR  = HERE / "AppStore"
OUT_DIR.mkdir(exist_ok=True)

W, H = 2880, 1800

# ── Fonts (SF Pro Display) ─────────────────────────────────────────────────────
def load_font(style: str, size: int) -> ImageFont.FreeTypeFont:
    candidates = {
        "black":    "SF-Pro-Display-Heavy.otf",
        "bold":     "SF-Pro-Display-Bold.otf",
        "semibold": "SF-Pro-Display-Semibold.otf",
        "medium":   "SF-Pro-Display-Medium.otf",
        "regular":  "SF-Pro-Display-Regular.otf",
        "light":    "SF-Pro-Display-Light.otf",
    }
    path = FONT_DIR / candidates.get(style, candidates["regular"])
    return ImageFont.truetype(str(path), size)

# ── Colour palettes (one per slide) ───────────────────────────────────────────
PALETTES = [
    # 1  Privacy  – deep indigo → violet
    dict(bg_top=(12, 8, 38),  bg_bot=(42, 14, 80),
         accent=(168, 85, 247), headline=(255, 255, 255), sub=(210, 190, 255)),
    # 2  Local LLM – charcoal → dark teal
    dict(bg_top=(6, 22, 30),  bg_bot=(8, 48, 52),
         accent=(52, 211, 199), headline=(255, 255, 255), sub=(160, 230, 225)),
    # 3  Web Search – midnight blue → cobalt
    dict(bg_top=(5, 12, 40),  bg_bot=(14, 30, 90),
         accent=(96, 165, 250), headline=(255, 255, 255), sub=(180, 210, 255)),
    # 4  PDF / Docs – warm dark brown → amber
    dict(bg_top=(24, 14, 6),  bg_bot=(52, 28, 6),
         accent=(251, 191, 36), headline=(255, 255, 255), sub=(255, 230, 160)),
    # 5  Multi-context – slate → emerald
    dict(bg_top=(8, 20, 22),  bg_bot=(10, 42, 36),
         accent=(52, 211, 153), headline=(255, 255, 255), sub=(160, 230, 200)),
]

# ── Slide content (EN + FR) ────────────────────────────────────────────────────
# screen_en / screen_fr: filenames in Screenshots/
SLIDES = [
    dict(
        key="01_privacy",
        palette=PALETTES[0],
        layout="right",
        screen_en="Web.context.EN.png",
        screen_fr="Web.context.FR.png",
        en=dict(tag="Privacy",
                title="Your AI.\nCompletely Private.",
                sub="All inference runs on your Mac.\nYour data never leaves your device."),
        fr=dict(tag="Confidentialité",
                title="Votre IA.\nTotalement Privée.",
                sub="Toutes les inférences s'exécutent sur votre Mac.\nVos données ne quittent jamais votre appareil."),
    ),
    dict(
        key="02_local_llm",
        palette=PALETTES[1],
        layout="left",
        screen_en="Web.search.context.EN.png",
        screen_fr="Web.Search.FR.png",
        en=dict(tag="On-Device AI",
                title="Local LLM.\nNo Cloud Required.",
                sub="Powered by Apple Silicon.\nFull control, zero subscriptions."),
        fr=dict(tag="IA sur l'appareil",
                title="LLM Local.\nSans le Cloud.",
                sub="Propulsé par Apple Silicon.\nContrôle total, zéro abonnement."),
    ),
    dict(
        key="03_web_search",
        palette=PALETTES[2],
        layout="right",
        screen_en="Web.Search.EN.png",
        screen_fr="Web.Search.FR.png",
        en=dict(tag="Web Intelligence",
                title="Real-Time\nWeb Context.",
                sub="Live search results synthesised by AI.\nCited sources, instant summaries."),
        fr=dict(tag="Intelligence Web",
                title="Contexte Web\nen Temps Réel.",
                sub="Résultats de recherche synthétisés par IA.\nSources citées, résumés instantanés."),
    ),
    dict(
        key="04_pdf",
        palette=PALETTES[3],
        layout="left",
        screen_en="PDF-context.EN.png",
        screen_fr="PDF-context.FR.png",
        en=dict(tag="Document Analysis",
                title="Chat With\nYour Documents.",
                sub="PDFs and images analysed on-device.\nPage-precise citations included."),
        fr=dict(tag="Analyse de documents",
                title="Discutez avec\nVos Documents.",
                sub="PDFs et images analysés sur l'appareil.\nCitations précises à la page."),
    ),
    dict(
        key="05_multicontext",
        palette=PALETTES[4],
        layout="right",
        screen_en="Web.search.context.EN.png",
        screen_fr="Web.context.FR.png",
        en=dict(tag="Multi-Context",
                title="Web + Docs.\nCombined.",
                sub="Blend web intelligence with your files.\nOne conversation, unlimited context."),
        fr=dict(tag="Multi-Contexte",
                title="Web + Docs.\nCombinés.",
                sub="Fusionnez l'intelligence web avec vos fichiers.\nUne conversation, un contexte illimité."),
    ),
]

# ── Helpers ───────────────────────────────────────────────────────────────────

def vertical_gradient(draw: ImageDraw.ImageDraw, w: int, h: int,
                      top: tuple, bot: tuple) -> None:
    for y in range(h):
        t = y / h
        r = int(top[0] + (bot[0] - top[0]) * t)
        g = int(top[1] + (bot[1] - top[1]) * t)
        b = int(top[2] + (bot[2] - top[2]) * t)
        draw.line([(0, y), (w, y)], fill=(r, g, b))


def radial_glow(img: Image.Image, cx: int, cy: int,
                colour: tuple, radius: int, alpha: int = 60) -> None:
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    for step in range(8, 0, -1):
        r = radius * step // 8
        a = int(alpha * (1 - step / 9))
        d.ellipse([cx - r, cy - r, cx + r, cy + r],
                  fill=(colour[0], colour[1], colour[2], a))
    blurred = layer.filter(ImageFilter.GaussianBlur(radius // 6))
    combined = Image.alpha_composite(img, blurred)
    img.paste(combined)


def pill_badge(img: Image.Image, text: str,
               x: int, y: int, font: ImageFont.FreeTypeFont,
               accent: tuple) -> int:
    """Paste a rounded pill badge onto img. Returns bottom-y."""
    pad_x, pad_y = 36, 16
    tmp_d = ImageDraw.Draw(img)
    bbox  = tmp_d.textbbox((0, 0), text, font=font)
    tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
    pw, ph = tw + pad_x * 2, th + pad_y * 2

    pill = Image.new("RGBA", (pw, ph), (0, 0, 0, 0))
    pd   = ImageDraw.Draw(pill)
    pd.rounded_rectangle([0, 0, pw - 1, ph - 1], radius=ph // 2,
                         fill=(accent[0], accent[1], accent[2], 45),
                         outline=(accent[0], accent[1], accent[2], 140),
                         width=3)
    pd.text((pad_x, pad_y), text, font=font, fill=(*accent[:3], 255))
    img.paste(pill, (x, y), pill)
    return y + ph


def draw_text_wrapped(draw: ImageDraw.ImageDraw, text: str,
                      x: int, y: int, max_width: int,
                      font: ImageFont.FreeTypeFont, colour: tuple,
                      line_spacing: float = 1.18) -> int:
    """Draws multi-line text (honours \\n). Returns bottom y."""
    cy = y
    for para in text.split("\n"):
        words = para.split()
        line  = ""
        for word in words:
            test = (line + " " + word).strip()
            bbox = draw.textbbox((0, 0), test, font=font)
            if bbox[2] - bbox[0] > max_width and line:
                draw.text((x, cy), line, font=font, fill=colour)
                lbbox = draw.textbbox((0, 0), line, font=font)
                cy += int((lbbox[3] - lbbox[1]) * line_spacing)
                line = word
            else:
                line = test
        if line:
            bbox = draw.textbbox((0, 0), line, font=font)
            draw.text((x, cy), line, font=font, fill=colour)
            cy += int((bbox[3] - bbox[1]) * line_spacing)
    return cy


def make_screen_mockup(screen_path: Path, target_h: int,
                       shadow_blur: int = 48) -> Image.Image:
    """Scale screenshot to target_h, add rounded corners + drop shadow."""
    src   = Image.open(screen_path).convert("RGBA")
    ratio = target_h / src.height
    new_w = int(src.width * ratio)
    src   = src.resize((new_w, target_h), Image.LANCZOS)

    radius = max(16, target_h // 80)
    mask   = Image.new("L", src.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [0, 0, src.width - 1, src.height - 1], radius=radius, fill=255)
    src.putalpha(mask)

    pad = shadow_blur
    shadow = Image.new("RGBA", (src.width + pad * 2, src.height + pad * 2), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle(
        [pad, pad, pad + src.width - 1, pad + src.height - 1],
        radius=radius, fill=(0, 0, 0, 90))
    shadow = shadow.filter(ImageFilter.GaussianBlur(shadow_blur))
    shadow.paste(src, (pad, pad), src)
    return shadow   # visible image sits at offset (pad, pad) within this canvas


# ── Main renderer ─────────────────────────────────────────────────────────────

def render_slide(slide: dict, lang: str) -> Image.Image:
    scale = H / 900  # all sizes derived from 900 px baseline

    pal   = slide["palette"]
    acc   = pal["accent"]
    hl    = pal["headline"]
    sub_c = pal["sub"]
    copy  = slide[lang]

    img  = Image.new("RGBA", (W, H))
    draw = ImageDraw.Draw(img)
    vertical_gradient(draw, W, H, pal["bg_top"], pal["bg_bot"])

    radial_glow(img, int(W * 0.15), int(H * 0.25), acc, int(H * 0.55), alpha=40)
    radial_glow(img, int(W * 0.85), int(H * 0.75), acc, int(H * 0.45), alpha=30)

    # ── Screenshot mockup ────────────────────────────────────────────────────
    screen_key = f"screen_{lang}"
    screen_h   = int(H * 0.88)
    shadow_blur = int(2 * scale)
    pad         = shadow_blur * 2          # shadow padding around visible image
    mockup      = make_screen_mockup(HERE / slide[screen_key], screen_h, shadow_blur)
    mw, mh      = mockup.size              # includes shadow padding

    margin      = int(W * 0.044)
    text_zone_w = int(W * 0.40)

    # Centre the *visible* image (not the shadow canvas) vertically
    vis_top_y   = (H - screen_h) // 2
    screen_y    = vis_top_y - pad          # shift up so visible content is centred

    if slide["layout"] == "right":
        screen_x = W - mw - margin + pad  # visible right edge ≈ W - margin
        text_x   = margin
    else:
        screen_x = margin - pad           # visible left edge ≈ margin
        text_x   = margin + pad + int(mw - pad * 2) + margin

    img.paste(mockup, (screen_x, screen_y), mockup)

    # ── Typography ────────────────────────────────────────────────────────────
    font_tag   = load_font("semibold", int(18 * scale))
    font_title = load_font("black",    int(72 * scale))
    font_sub   = load_font("light",    int(26 * scale))
    font_brand = load_font("medium",   int(20 * scale))

    draw2 = ImageDraw.Draw(img)

    # Align text block top with visible screenshot top
    cy = vis_top_y + int(20 * scale)

    # tag pill
    cy = pill_badge(img, f"  {copy['tag']}  ", text_x, cy, font_tag, acc)
    cy += int(32 * scale)

    # headline
    cy = draw_text_wrapped(draw2, copy["title"],
                           text_x, cy, text_zone_w,
                           font_title, hl, line_spacing=1.10)
    cy += int(30 * scale)

    # accent rule
    draw2.rectangle([text_x, cy,
                     text_x + int(56 * scale), cy + int(4 * scale)],
                    fill=acc)
    cy += int(26 * scale)

    # subtitle
    draw_text_wrapped(draw2, copy["sub"],
                      text_x, cy, text_zone_w,
                      font_sub, sub_c, line_spacing=1.65)

    # brand watermark
    bb  = draw2.textbbox((0, 0), "SilicIA", font=font_brand)
    bw  = bb[2] - bb[0]
    draw2.text((W - bw - margin, H - int(44 * scale)),
               "SilicIA", font=font_brand,
               fill=(*hl[:3], 80))

    return img.convert("RGB")


# ── Entry point ───────────────────────────────────────────────────────────────

def main():
    jobs  = [(s, lang) for s in SLIDES for lang in ("en", "fr")]
    total = len(jobs)
    for i, (slide, lang) in enumerate(jobs, 1):
        img   = render_slide(slide, lang)
        fname = f"{slide['key']}_{lang}_{W}x{H}.png"
        img.save(OUT_DIR / fname, "PNG", optimize=True)
        print(f"[{i:2d}/{total}] {fname}")
    print(f"\nDone – {total} slides in {OUT_DIR}")


if __name__ == "__main__":
    main()
