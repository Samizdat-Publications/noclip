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

## Session 03
| Date | Session | Service | Purpose | Calls | Est. cost |
|---|---|---|---|---|---|
| 2026-10-02 | S03 | Gemini (gemini-3-pro-image, 1K/2K) | graffiti v2 photographic set, text pieces, 2 attempts each (build_graffiti_v2.py) | 42 | ~$5.63 ($0.134 each, list price estimate) |
| 2026-10-02 | S03 | Gemini (gemini-3.1-flash-image) | graffiti v2, no-text pieces (sigil, handprints, scrawl_small_3), 2 attempts each | 6 | ~$0.40 ($0.067 each) |
| 2026-10-02 | S03 | Gemini (gemini-3-pro-image + 3.1-flash-image) | wasted calls: sigil a1 (flash wrote a paragraph), scrawl_small_4 x2 (prompt text leaked into image); redone | 3 | ~$0.34 |
| 2026-10-02 | S03 | ElevenLabs (eleven_text_to_sound_v2) | soggy carpet steps (6 walk takes, 4 run takes) + 2 breath takes for reversed figure breath (build_s03.py); 538 credits | 12 | ~$0.16 |
| 2026-10-02 | S03 | Gemini (gemini-3-pro-image 2K x3 + gemini-3.1-flash-image 2K x1) | carpet v2 photographic candidates (build_carpet_v2.py) | 4 | ~$0.60 (3 x $0.134 + $0.067 list estimate; 2K may bill higher) |
| 2026-10-02 | S03 | Gemini (gemini-3.1-pro-preview) | video critic -> 009_gemini.md | 1 | $0.09 (24555 in / 3388 out tokens) |
| 2026-10-02 | S03 | Gemini (gemini-3.1-pro-preview) | video critic -> 010_gemini.md | 1 | $0.08 (24556 in / 2880 out tokens) |
| 2026-10-02 | S03 | Gemini (gemini-3.1-pro-preview) | video critic -> 011_gemini.md | 1 | $0.08 (24600 in / 2319 out tokens) |
| 2026-10-02 | S03 | ElevenLabs (eleven_text_to_sound_v2) | M3 sound: 6 breath takes (calm/heavy/fear x2), 6 distant one-shots, 6 soaked-carpet squish takes (build_m3.py); 1143 credits | 18 | ~$0.34 |
| 2026-10-02 | S03 | Gemini (gemini-3.1-pro-preview) | video critic -> 012_gemini.md | 1 | $0.08 (24599 in / 2849 out tokens) |
| 2026-10-02 | S03 | Gemini (gemini-3-pro-image 2K) | wallpaper v2 photographic candidates (build_wallpaper_v2.py); 4 kept + 1 failed empty response (probably unbilled) | 5 | ~$0.67 (list estimate) |
| 2026-10-02 | S03 | Gemini (gemini-3.1-pro-preview) | video critic -> 013_gemini.md | 1 | $0.08 (24596 in / 2452 out tokens) |
| 2026-10-02 | S03 | Gemini (gemini-3.1-pro-preview) | video critic -> 014_gemini.md | 1 | $0.09 (24599 in / 3569 out tokens) |
| 2026-10-02 | S03 | Gemini (gemini-3.1-pro-preview) | video critic -> 015_gemini.md | 1 | $0.11 (24600 in / 5135 out tokens) |
| 2026-10-02 | S03 | Gemini (gemini-3.1-pro-preview) | video critic -> 015_gemini.md | 1 | $0.09 (24600 in / 3459 out tokens) |
| 2026-10-02 | S03 | Gemini (gemini-3.1-pro-preview) | video critic -> 015_gemini.md | 1 | $0.12 (27639 in / 5033 out tokens) |
| 2026-10-02 | S03 | Gemini (gemini-3.1-pro-preview) | video critic -> 016_gemini.md | 1 | $0.09 (27639 in / 2879 out tokens) |
| 2026-10-02 | S03 | Gemini (gemini-3.1-pro-preview) | video critic -> 017_gemini.md | 1 | $0.10 (est) |
| 2026-10-02 | S03 | Gemini (gemini-3.1-pro-preview) | video critic -> 018_gemini.md | 1 | $0.09 (est) |

Session 03 total: about $9.24 of a $40 cap (graffiti v2 about $6.4, carpet and wallpaper about $1.3, sounds about $0.5, eleven video critiques about $1.0). Sketchfab models were free CC-BY downloads.
| 2026-10-02 | S04 | Gemini (gemini-3.1-pro-preview) | video critic -> 017_gemini.md | 1 | $0.10 (27638 in / 3623 out tokens) |
| 2026-10-02 | S04 | Gemini (gemini-3.1-pro-preview) | video critic -> 018_gemini.md | 1 | $0.09 (27639 in / 2534 out tokens) |

## Session 04
| Date | Session | Service | Purpose | Calls | Est. cost |
|---|---|---|---|---|---|
| 2026-10-02 | S04 | Gemini (gemini-3-pro-image, 2K, with wallpaper reference) | Occupant monster concept images, sets A and B (build_entity_concepts.py) | 12 | ~$1.61 ($0.134 each, list price estimate) |
| 2026-10-02 | S04 | Gemini (gemini-3-pro-image, 2K) | Occupant concept round 2: B2_2 redrawn as a front A-pose model sheet for Meshy (build_entity_concepts_c.py) | 4 | ~$0.54 |
| 2026-10-02 | S04 | Meshy (image-to-3d, meshy-7.1, 2k PBR, 40k tris, a-pose) | Occupant monster models from concept sheets C_2 and C_4 (build_entity_meshy.py); balance 1968 to 1908 | 2 | 60 credits |
