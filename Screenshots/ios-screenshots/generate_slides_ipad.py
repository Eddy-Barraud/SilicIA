#!/usr/bin/env python3
"""
SilicIA – Apple iOS App Store screenshot generator
Produces slides at 1284×2778 (iPhone 6.7" portrait), EN + FR.
"""

from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter, ImageFont

# ── Paths ─────────────────────────────────────────────────────────────────────
HERE     = Path(__file__).parent
FONT_DIR = Path.home() / "Library/Fonts"
OUT_DIR  = HERE / "AppStoreIPAD"
OUT_DIR.mkdir(exist_ok=True)

W, H  = 2064, 2752
SCALE = W / 750   # baseline width 750 px (logical iPhone points)

# ── Fonts ─────────────────────────────────────────────────────────────────────
def load_font(style: str, size: int) -> ImageFont.FreeTypeFont:
    candidates = {
        "black":    "SF-Pro-Display-Heavy.otf",
        "bold":     "SF-Pro-Display-Bold.otf",
        "semibold": "SF-Pro-Display-Semibold.otf",
        "medium":   "SF-Pro-Display-Medium.otf",
        "regular":  "SF-Pro-Display-Regular.otf",
        "light":    "SF-Pro-Display-Light.otf",
    }
    return ImageFont.truetype(str(FONT_DIR / candidates[style]), size)

# ── Colour palettes ───────────────────────────────────────────────────────────
PALETTES = [
    dict(bg_top=(12, 8, 38),  bg_bot=(42, 14, 80),
         accent=(168, 85, 247), headline=(255,255,255), sub=(210,190,255)),
    dict(bg_top=(6, 22, 30),  bg_bot=(8, 48, 52),
         accent=(52, 211, 199), headline=(255,255,255), sub=(160,230,225)),
    dict(bg_top=(5, 12, 40),  bg_bot=(14, 30, 90),
         accent=(96, 165, 250), headline=(255,255,255), sub=(180,210,255)),
    dict(bg_top=(24, 14, 6),  bg_bot=(52, 28, 6),
         accent=(251, 191, 36), headline=(255,255,255), sub=(255,230,160)),
    dict(bg_top=(8, 20, 22),  bg_bot=(10, 42, 36),
         accent=(52, 211, 153), headline=(255,255,255), sub=(160,230,200)),
]

# ── Slide definitions ─────────────────────────────────────────────────────────
SLIDES = [
    dict(
        key="01_privacy", palette=PALETTES[0],
        screen_en="Web.context.EN.PNG",
        screen_fr="Web.context.FR.PNG",
        en=dict(tag="Privacy",
                title="Your AI.\nCompletely Private.",
                sub="All inference runs on your iPhone.\nYour data never leaves your device."),
        fr=dict(tag="Confidentialité",
                title="Votre IA.\nTotalement Privée.",
                sub="Toutes les inférences s'exécutent sur votre iPhone.\nVos données ne quittent jamais votre appareil."),
    ),
    dict(
        key="02_local_llm", palette=PALETTES[1],
        screen_en="Web.Search.EN.PNG",
        screen_fr="Web.Search.FR.PNG",
        en=dict(tag="On-Device AI",
                title="Local LLM.\nNo Cloud Required.",
                sub="Powered by Apple Silicon.\nFull control, zero subscriptions."),
        fr=dict(tag="IA sur l'appareil",
                title="LLM Local.\nSans le Cloud.",
                sub="Propulsé par Apple Silicon.\nContrôle total, zéro abonnement."),
    ),
    dict(
        key="03_web_search", palette=PALETTES[2],
        screen_en="Web.Search.EN.PNG",
        screen_fr="Web.Search.FR.PNG",
        en=dict(tag="Web Intelligence",
                title="Real-Time\nWeb Context.",
                sub="Live search results synthesised by AI.\nCited sources, instant summaries."),
        fr=dict(tag="Intelligence Web",
                title="Contexte Web\nen Temps Réel.",
                sub="Résultats de recherche synthétisés par IA.\nSources citées, résumés instantanés."),
    ),
    dict(
        key="04_pdf", palette=PALETTES[3],
        screen_en="PDF-context.EN.PNG",
        screen_fr="PDF-context.FR.PNG",
        en=dict(tag="Document Analysis",
                title="Chat With\nYour Documents.",
                sub="PDFs and images analysed on-device.\nPage-precise citations included."),
        fr=dict(tag="Analyse de documents",
                title="Discutez avec\nVos Documents.",
                sub="PDFs et images analysés sur l'appareil.\nCitations précises à la page."),
    ),
    dict(
        key="05_multicontext", palette=PALETTES[4],
        screen_en="PDF-context.EN.PNG",
        screen_fr="Web.context.FR.PNG",
        en=dict(tag="Multi-Context",
                title="Web + Docs.\nCombined.",
                sub="Blend web intelligence with your files.\nOne conversation, unlimited context."),
        fr=dict(tag="Multi-Contexte",
                title="Web + Docs.\nCombinés.",
                sub="Fusionnez l'intelligence web avec vos fichiers.\nUne conversation, un contexte illimité."),
    ),
]

# ── Helpers ───────────────────────────────────────────────────────────────────

def vertical_gradient(draw, w, h, top, bot):
    for y in range(h):
        t = y / h
        draw.line([(0,y),(w,y)], fill=(
            int(top[0]+(bot[0]-top[0])*t),
            int(top[1]+(bot[1]-top[1])*t),
            int(top[2]+(bot[2]-top[2])*t),
        ))


def radial_glow(img, cx, cy, colour, radius, alpha=50):
    layer = Image.new("RGBA", img.size, (0,0,0,0))
    d = ImageDraw.Draw(layer)
    for step in range(8, 0, -1):
        r = radius * step // 8
        a = int(alpha * (1 - step/9))
        d.ellipse([cx-r, cy-r, cx+r, cy+r],
                  fill=(colour[0], colour[1], colour[2], a))
    img.paste(Image.alpha_composite(img,
              layer.filter(ImageFilter.GaussianBlur(radius//6))))


def pill_badge(img, text, x, y, font, accent):
    pad_x, pad_y = int(30*SCALE), int(13*SCALE)
    bbox = ImageDraw.Draw(img).textbbox((0,0), text, font=font)
    tw, th = bbox[2]-bbox[0], bbox[3]-bbox[1]
    pw, ph = tw+pad_x*2, th+pad_y*2
    pill = Image.new("RGBA", (pw, ph), (0,0,0,0))
    pd = ImageDraw.Draw(pill)
    pd.rounded_rectangle([0,0,pw-1,ph-1], radius=ph//2,
                         fill=(*accent[:3], 45),
                         outline=(*accent[:3], 140),
                         width=max(2, int(2*SCALE)))
    pd.text((pad_x, pad_y), text, font=font, fill=(*accent[:3], 255))
    img.paste(pill, (x, y), pill)
    return y + ph


def draw_text_wrapped(draw, text, x, y, max_width, font, colour, line_spacing=1.12):
    cy = y
    for para in text.split("\n"):
        words, line = para.split(), ""
        for word in words:
            test = (line + " " + word).strip()
            bbox = draw.textbbox((0,0), test, font=font)
            if bbox[2]-bbox[0] > max_width and line:
                b = draw.textbbox((0,0), line, font=font)
                draw.text((x, cy), line, font=font, fill=colour)
                cy += int((b[3]-b[1]) * line_spacing)
                line = word
            else:
                line = test
        if line:
            b = draw.textbbox((0,0), line, font=font)
            draw.text((x, cy), line, font=font, fill=colour)
            cy += int((b[3]-b[1]) * line_spacing)
    return cy


def make_phone_mockup(screen_path: Path, target_w: int) -> Image.Image:
    """
    Fit screenshot to target_w, wrap in a phone bezel, add drop shadow.
    Returns RGBA; visible phone starts at (pad, pad).
    """
    src = Image.open(screen_path).convert("RGBA")
    ratio = target_w / src.width
    src = src.resize((target_w, int(src.height * ratio)), Image.LANCZOS)
    sw, sh = src.size

    bezel    = int(16 * SCALE)
    corner_r = int(56 * SCALE)
    inner_r  = max(8, corner_r - bezel)

    pw, ph = sw + bezel*2, sh + bezel*2
    phone = Image.new("RGBA", (pw, ph), (0,0,0,0))
    pd = ImageDraw.Draw(phone)
    pd.rounded_rectangle([0,0,pw-1,ph-1], radius=corner_r,
                         fill=(18, 18, 22, 255))
    pd.rounded_rectangle([bezel, bezel, pw-1-bezel, ph-1-bezel],
                         radius=inner_r, fill=(0,0,0,0))
    phone.paste(src, (bezel, bezel), src)

    shadow_blur = int(18 * SCALE)
    pad = shadow_blur * 2
    canvas = Image.new("RGBA", (pw+pad*2, ph+pad*2), (0,0,0,0))
    ImageDraw.Draw(canvas).rounded_rectangle(
        [pad, pad, pad+pw-1, pad+ph-1],
        radius=corner_r, fill=(0,0,0,110))
    canvas = canvas.filter(ImageFilter.GaussianBlur(shadow_blur))
    canvas.paste(phone, (pad, pad), phone)
    return canvas   # visible phone at (pad, pad)


# ── Renderer ──────────────────────────────────────────────────────────────────

def render_slide(slide: dict, lang: str) -> Image.Image:
    pal   = slide["palette"]
    acc   = pal["accent"]
    hl    = pal["headline"]
    sub_c = pal["sub"]
    copy  = slide[lang]

    img  = Image.new("RGBA", (W, H))
    draw = ImageDraw.Draw(img)
    vertical_gradient(draw, W, H, pal["bg_top"], pal["bg_bot"])

    # Glow – top-left and bottom-right
    radial_glow(img, int(W*0.15), int(H*0.12), acc, int(W*0.80), alpha=35)
    radial_glow(img, int(W*0.85), int(H*0.88), acc, int(W*0.65), alpha=25)

    # ── Phone mockup (portrait, centred horizontally) ─────────────────────────
    phone_w    = int(W * 0.80)          # phone takes 80 % of slide width
    mockup     = make_phone_mockup(HERE / slide[f"screen_{lang}"], phone_w)
    mw, mh     = mockup.size
    shadow_pad = int(18 * SCALE) * 2    # matches make_phone_mockup pad
    vis_w      = mw - shadow_pad * 2
    vis_h      = mh - shadow_pad * 2

    # Text block occupies upper ~38 % of the slide
    text_area_h = int(H * 0.38)
    # Phone sits below, centred
    phone_top   = text_area_h + int(30 * SCALE)
    phone_x     = (W - mw) // 2
    phone_y     = phone_top - shadow_pad

    img.paste(mockup, (phone_x, phone_y), mockup)

    # ── Typography ────────────────────────────────────────────────────────────
    margin      = int(W * 0.08)
    text_zone_w = W - margin * 2

    font_tag   = load_font("semibold", int(17 * SCALE))
    font_title = load_font("black",    int(68 * SCALE))
    font_sub   = load_font("light",    int(24 * SCALE))
    font_brand = load_font("medium",   int(16 * SCALE))

    draw2 = ImageDraw.Draw(img)

    # Vertically centre the text block within text_area_h
    # Estimate block height first (pill + gap + title lines + rule + sub)
    pill_h  = int((17*SCALE * 1.4) + 13*SCALE*2)
    title_h = int(68 * SCALE * 1.12 * len(copy["title"].split("\n")))
    sub_h   = int(24 * SCALE * 1.60 * len(copy["sub"].split("\n")))
    block_h = pill_h + int(24*SCALE) + title_h + int(26*SCALE) + int(10*SCALE) + sub_h
    cy      = max(int(H*0.05), (text_area_h - block_h) // 2)

    cy = pill_badge(img, f"  {copy['tag']}  ", margin, cy, font_tag, acc)
    cy += int(24 * SCALE)

    cy = draw_text_wrapped(draw2, copy["title"],
                           margin, cy, text_zone_w,
                           font_title, hl, line_spacing=1.10)
    cy += int(26 * SCALE)

    draw2.rectangle([margin, cy, margin + int(52*SCALE), cy + int(4*SCALE)],
                    fill=acc)
    cy += int(18 * SCALE)

    draw_text_wrapped(draw2, copy["sub"],
                      margin, cy, text_zone_w,
                      font_sub, sub_c, line_spacing=1.60)

    # Brand watermark bottom-centre
    bb  = draw2.textbbox((0,0), "SilicIA", font=font_brand)
    bw  = bb[2]-bb[0]
    draw2.text(((W-bw)//2, H - int(52*SCALE)),
               "SilicIA", font=font_brand, fill=(*hl[:3], 70))

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
