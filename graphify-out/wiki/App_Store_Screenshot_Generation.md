# App Store Screenshot Generation

> 33 nodes · cohesion 0.10

## Key Concepts

- **generate_slides_ipad.py** (11 connections) — `Screenshots/ios-screenshots/generate_slides_ipad.py`
- **generate_slides.py** (11 connections) — `Screenshots/macos-screenshots/generate_slides.py`
- **render_slide()** (9 connections) — `Screenshots/ios-screenshots/generate_slides_ipad.py`
- **render_slide()** (9 connections) — `Screenshots/macos-screenshots/generate_slides.py`
- **make_phone_mockup()** (5 connections) — `Screenshots/ios-screenshots/generate_slides_ipad.py`
- **draw_text_wrapped()** (5 connections) — `Screenshots/macos-screenshots/generate_slides.py`
- **make_screen_mockup()** (5 connections) — `Screenshots/macos-screenshots/generate_slides.py`
- **pill_badge()** (5 connections) — `Screenshots/macos-screenshots/generate_slides.py`
- **Image** (4 connections)
- **load_font()** (3 connections) — `Screenshots/ios-screenshots/generate_slides_ipad.py`
- **load_font()** (3 connections) — `Screenshots/macos-screenshots/generate_slides.py`
- **FreeTypeFont** (3 connections)
- **radial_glow()** (3 connections) — `Screenshots/macos-screenshots/generate_slides.py`
- **vertical_gradient()** (3 connections) — `Screenshots/macos-screenshots/generate_slides.py`
- **ImageDraw** (2 connections)
- **pathlib** (2 connections)
- **pil** (2 connections)
- **draw_text_wrapped()** (2 connections) — `Screenshots/ios-screenshots/generate_slides_ipad.py`
- **main()** (2 connections) — `Screenshots/ios-screenshots/generate_slides_ipad.py`
- **pill_badge()** (2 connections) — `Screenshots/ios-screenshots/generate_slides_ipad.py`
- **Image** (2 connections)
- **radial_glow()** (2 connections) — `Screenshots/ios-screenshots/generate_slides_ipad.py`
- **vertical_gradient()** (2 connections) — `Screenshots/ios-screenshots/generate_slides_ipad.py`
- **main()** (2 connections) — `Screenshots/macos-screenshots/generate_slides.py`
- **FreeTypeFont** (1 connections)
- *... and 8 more nodes in this community*

## Relationships

- No strong cross-community connections detected

## Source Files

- `Screenshots/ios-screenshots/generate_slides_ipad.py`
- `Screenshots/macos-screenshots/generate_slides.py`

## Audit Trail

- EXTRACTED: 54 (100%)
- INFERRED: 0 (0%)
- AMBIGUOUS: 0 (0%)

---

*Part of the graphify knowledge wiki. See [index](index.md) to navigate.*