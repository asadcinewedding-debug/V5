# AN AI Relight V5 — Generative Mood Relight

V5 is designed around one hard rule:

**Subject unchanged. Mood transformed.**

The generative model is used to infer a new lighting/mood field. V5 does not directly replace the subject with generated pixels. It transfers low-frequency illumination and color from the AI result back onto the original image, preserving facial identity, pose, clothing, texture, composition and fine detail.

Core:
- IC-Light generative relighting through Replicate
- MODNet subject matte
- YuNet face protection
- Low-frequency illumination/color-field transfer
- Safe / Balanced / Strong mood modes
- Batch TIFF output for Lightroom Classic

A Replicate API token is required for the generative model.

Build status: V5 Windows workflow enabled.
