# Paid API spend log

Soft cap per session: `SESSION_SPEND_CAP_USD` from .env (default 40). Estimates are in US dollars.
| Date | Session | Service | Purpose | Calls | Est. cost |

|---|---|---|---|---|---|
| 2026-10-01 | S01 | Sketchfab (free download API) | Level 0 props, 11 evaluated, 4 used | 11 | $0 |
| 2026-10-01 | S01 | ElevenLabs (eleven_text_to_sound_v2) | Level 0 footsteps (4 takes) and distant thuds (3), sliced into one-shots; cached in pipeline/audio/cache | 7 | ~$0.09 (286 credits) |
| 2026-10-01 | S01 | Meshy | Props attempt, blocked: account had 3 credits (402 Insufficient funds) | 0 | $0 |
| 2026-10-01 | S01 | Gemini (gemini-3.1-pro-preview) | video critic -> 006_gemini.md | 1 | $0.08 (20631 in / 3313 out tokens) |

Session 01 total: about $0.17 of a $40 cap.

## Session 02
| Date | Session | Service | Purpose | Calls | Est. cost |
|---|---|---|---|---|---|
| 2026-10-01 | S02 | Gemini (gemini-3.1-pro-preview) | video critic -> 007_gemini.md | 1 | $0.09 (20631 in / 3752 out tokens) |
| 2026-10-02 | S02 | Gemini (gemini-2.5-flash-image) | Level 0 graffiti decals, first pass, 14 pieces (build_graffiti.py) | 14 | ~$0.55 ($0.039 each) |
| 2026-10-02 | S02 | Gemini (gemini-2.5-flash-image) | graffiti retries: lights, exits (apostrophes) | 2 | ~$0.08 |
| 2026-10-02 | S02 | Gemini (gemini-3.1-flash-image) | graffiti retries: tally_copy, same, gaps_child (tally glyphs, garbled SAME, crayon figure) | 3 | ~$0.20 ($0.067 each) |
| 2026-10-02 | S02 | Gemini (gemini-3.1-flash-image) | graffiti retry 2: lights, exits (apostrophe, faint scratches) | 2 | ~$0.13 |
| 2026-10-02 | S02 | Gemini (gemini-3.1-pro-preview) | video critic -> 008_gemini.md | 1 | $0.09 (24555 in / 3173 out tokens) |

Session 02 total: about $1.14 of a $40 cap (graffiti $0.96, two video critiques $0.18).
