"""Gemini critic: the only critic that HEARS the game and sees real motion.

    python tools/critic_gemini/critic.py OUT.md [--model MODEL]

Sends review/inbox/video/clip.mp4 (with audio), 4 frames, the store page and perf.json to the
strongest Gemini model that accepts video, using the persona and output format from the body
of .claude/agents/player-critic.md (read verbatim from the file, never paraphrased).
Logs the paid call to docs/SPEND.md. The API key is loaded from .env inside this script and
is never printed.
"""
import argparse
import datetime as dt
import glob
import json
import os
import re
import sys
import time

from dotenv import load_dotenv
from google import genai
from google.genai import types

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
INBOX = os.path.join(ROOT, "review", "inbox")
PERSONA_FILE = os.path.join(ROOT, ".claude", "agents", "player-critic.md")
SPEND = os.path.join(ROOT, "docs", "SPEND.md")

FALLBACK_MODELS = ["gemini-3.1-pro-preview", "gemini-3-pro-preview", "gemini-2.5-pro"]
# USD per 1M tokens (input, output) for cost logging; conservative.
PRICES = {"pro": (2.0, 12.0), "flash": (0.75, 3.75)}


def persona():
    text = open(PERSONA_FILE, encoding="utf-8").read()
    parts = text.split("---", 2)
    return parts[2].strip() if len(parts) == 3 else text


def pick_model(client, forced=None):
    if forced:
        return forced
    best, best_v = None, -1.0
    try:
        for m in client.models.list():
            name = (m.name or "").replace("models/", "")
            acts = [a.lower() for a in (getattr(m, "supported_actions", None) or [])]
            if acts and not any("generatecontent" in a for a in acts):
                continue
            mm = re.fullmatch(r"gemini-(\d+(?:\.\d+)?)-pro(?:-preview)?(?:-\d{2}-\d{4})?", name)
            if not mm:
                continue
            v = float(mm.group(1)) - (0.001 if "preview" in name else 0.0)
            if v > best_v:
                best, best_v = name, v
    except Exception as e:  # listing can fail; fall back
        print("[gemini] model list failed:", type(e).__name__)
    return best or FALLBACK_MODELS[0]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("out")
    ap.add_argument("--model", default=None)
    ap.add_argument("--fps", type=float, default=2.0)
    a = ap.parse_args()
    load_dotenv(os.path.join(ROOT, ".env"))
    key = os.environ.get("GEMINI_API_KEY") or os.environ.get("GOOGLE_API_KEY")
    if not key:
        sys.exit("GEMINI_API_KEY missing from .env")
    client = genai.Client(api_key=key)
    model = pick_model(client, a.model)
    print("[gemini] model:", model)

    clip = os.path.join(INBOX, "video", "clip.mp4")
    frames = sorted(glob.glob(os.path.join(INBOX, "frames", "*.png")))
    if not os.path.exists(clip) or not frames:
        sys.exit("inbox is missing the clip or frames")
    pick = [frames[int(i * (len(frames) - 1) / 3)] for i in range(4)]
    store = open(os.path.join(INBOX, "store_page.md"), encoding="utf-8").read()
    perf = open(os.path.join(INBOX, "perf.json"), encoding="utf-8").read() if os.path.exists(os.path.join(INBOX, "perf.json")) else "{}"

    f = client.files.upload(file=clip)
    t0 = time.time()
    while not f.state or f.state.name != "ACTIVE":
        if f.state and f.state.name == "FAILED":
            sys.exit("video processing failed")
        if time.time() - t0 > 600:
            sys.exit("video processing timed out")
        time.sleep(5)
        f = client.files.get(name=f.name)

    intro = (
        "You are receiving the files directly instead of a folder. Here is everything you get:\n"
        "1. store_page.md (below).\n2. perf.json (below).\n"
        "3. clip.mp4: a gameplay video of someone playing the build, WITH the game's own sound. "
        "You can hear it and see real motion, so judge Sound and motion from the video.\n"
        "4. Four still frames from the same session (images after the video).\n"
        "There is no previous build to compare to this time unless the video says so.\n\n"
        f"--- store_page.md ---\n{store}\n--- perf.json ---\n{perf}\n"
    )
    contents = [
        types.Part(file_data=types.FileData(file_uri=f.uri, mime_type=f.mime_type),
                   video_metadata=types.VideoMetadata(fps=a.fps)),
    ]
    for p in pick:
        contents.append(types.Part.from_bytes(data=open(p, "rb").read(), mime_type="image/png"))
    contents.append(intro)
    cfg = types.GenerateContentConfig(system_instruction=persona(), max_output_tokens=16384, temperature=0.7)
    resp = None
    for attempt in range(4):
        try:
            resp = client.models.generate_content(model=model, contents=contents, config=cfg)
            break
        except Exception as e:
            wait = 10 * (2 ** attempt)
            print(f"[gemini] attempt {attempt + 1} failed ({type(e).__name__}); retry in {wait}s")
            time.sleep(wait)
            if attempt == 1 and a.model is None and model != FALLBACK_MODELS[-1]:
                model = FALLBACK_MODELS[min(FALLBACK_MODELS.index(model) + 1, len(FALLBACK_MODELS) - 1)] if model in FALLBACK_MODELS else FALLBACK_MODELS[0]
                print("[gemini] falling back to", model)
    try:
        client.files.delete(name=f.name)
    except Exception:
        pass
    if resp is None or not resp.text:
        sys.exit("no response from Gemini")
    text = resp.text.strip()
    os.makedirs(os.path.dirname(os.path.abspath(a.out)), exist_ok=True)
    open(a.out, "w", encoding="utf-8", newline="\n").write(text + "\n")
    um = resp.usage_metadata
    tin = getattr(um, "prompt_token_count", 0) or 0
    tout = (getattr(um, "candidates_token_count", 0) or 0) + (getattr(um, "thoughts_token_count", 0) or 0)
    pin, pout = PRICES["flash" if "flash" in model else "pro"]
    cost = tin / 1e6 * pin + tout / 1e6 * pout
    sys.path.insert(0, os.path.join(ROOT, "tools"))
    import progress  # the session number comes from docs/HANDOFF.md
    sess = f"S{progress.DEFAULT_SESSION:02d}"
    with open(SPEND, "a", encoding="utf-8", newline="\n") as s:
        s.write(f"| {dt.date.today().isoformat()} | {sess} | Gemini ({model}) | video critic -> {os.path.basename(a.out)} | 1 | ${cost:.2f} ({tin} in / {tout} out tokens) |\n")
    print(f"[gemini] saved {a.out} ({len(text)} chars), est ${cost:.2f}")


if __name__ == "__main__":
    main()
