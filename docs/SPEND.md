# Paid API spend log

Soft cap per session: `SESSION_SPEND_CAP_USD` from .env (default 40). Estimates are in US dollars.
| Date | Session | Service | Purpose | Calls | Est. cost |

|---|---|---|---|---|---|
| 2026-10-01 | S01 | Sketchfab (free download API) | Level 0 props, 11 evaluated, 4 used | 11 | $0 |
| 2026-10-01 | S01 | ElevenLabs (eleven_text_to_sound_v2) | Level 0 footsteps (4 takes) and distant thuds (3), sliced into one-shots; cached in pipeline/audio/cache | 7 | ~$0.09 (286 credits) |
| 2026-10-01 | S01 | Meshy | Props attempt, blocked: account had 3 credits (402 Insufficient funds) | 0 | $0 |
| 2026-10-01 | S01 | Gemini (gemini-3.1-pro-preview) | video critic -> 006_gemini.md | 1 | $0.08 (20631 in / 3313 out tokens) |

Session 01 total: about $0.17 of a $40 cap.
| 2026-10-01 | auto | Gemini (gemini-3.1-pro-preview) | video critic -> 007_gemini.md | 1 | $0.09 (20631 in / 3752 out tokens) |
