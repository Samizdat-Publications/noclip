"""Monster Lab panel, Gemini judge (D051): shows every option image in a round folder to Gemini with
the panel prompt and saves its verdict.

  python tools/monster_panel.py review/monster_lab/r1 review/critiques/monster_r1_gemini.md

The folder holds only option_N.png files (shuffled, unlabeled). The prompt is
pipeline/monster_lab/panel_prompt.md (or --prompt). Writes one SPEND.md row.
"""
import argparse
import datetime as dt
import glob
import os
import re
import sys
import time

from dotenv import load_dotenv
from google import genai
from google.genai import types

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools", "critic_gemini"))
sys.path.insert(0, os.path.join(ROOT, "tools"))
from critic import pick_model, PRICES, SPEND  # noqa: E402


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("folder")
    ap.add_argument("out")
    ap.add_argument("--prompt", default=os.path.join(ROOT, "pipeline", "monster_lab", "panel_prompt.md"))
    ap.add_argument("--model", default=None)
    ap.add_argument("--session", default="S07")
    a = ap.parse_args()
    load_dotenv(os.path.join(ROOT, ".env"))
    client = genai.Client(api_key=os.environ["GEMINI_API_KEY"])
    model = pick_model(client, a.model)
    print("[panel] model:", model)
    files = sorted(glob.glob(os.path.join(a.folder, "option_*.*")), key=lambda p: int(re.findall(r"\d+", os.path.basename(p))[0]))
    contents = [open(a.prompt, encoding="utf-8").read()]
    for f in files:
        n = re.findall(r"\d+", os.path.basename(f))[0]
        contents.append("OPTION %s:" % n)
        mime = "image/png" if f.lower().endswith(".png") else "image/jpeg"
        contents.append(types.Part.from_bytes(data=open(f, "rb").read(), mime_type=mime))
    resp = None
    for attempt in range(3):
        try:
            resp = client.models.generate_content(model=model, contents=contents,
                                                  config=types.GenerateContentConfig(temperature=0.6))
            break
        except Exception as e:
            print("[panel] attempt", attempt + 1, "failed:", type(e).__name__, str(e)[:200])
            time.sleep(10 * (attempt + 1))
    if resp is None:
        sys.exit(1)
    os.makedirs(os.path.dirname(os.path.abspath(a.out)), exist_ok=True)
    with open(a.out, "w", encoding="utf-8", newline="\n") as f:
        f.write(resp.text or "")
    um = resp.usage_metadata
    tin, tout = (um.prompt_token_count or 0), (um.candidates_token_count or 0) + (getattr(um, "thoughts_token_count", 0) or 0)
    pin, pout = PRICES["flash" if "flash" in model else "pro"]
    cost = tin / 1e6 * pin + tout / 1e6 * pout
    sess = a.session
    with open(SPEND, "a", encoding="utf-8", newline="\n") as s:
        s.write(f"| {dt.date.today().isoformat()} | {sess} | Gemini ({model}) | monster panel -> {os.path.basename(a.out)} | 1 | ${cost:.2f} ({tin} in / {tout} out tokens) |\n")
    print("[panel] wrote", a.out, "cost $%.2f" % cost)


if __name__ == "__main__":
    main()
