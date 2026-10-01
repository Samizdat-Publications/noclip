"""Recover the player-critic's review from its own transcript.

Why this exists: the critic guard hook (.claude/hooks/critic_guard.mjs) blocks every tool
except Read and Glob, which also blocks the harness tool the critic uses to hand its report
back. The builder may not edit the guard (settings deny it), so the review is recovered
verbatim from the critic's transcript instead. See docs/DECISIONS.md D004.

Usage:
    python tools/critic_extract.py <agent_id> <out.md>
    python tools/critic_extract.py --latest <out.md>     (newest player-critic transcript)
"""
import glob
import json
import os
import sys

PROJECT_SLUG = "C--Users-stewa-ClaudeProjects-Noclip"


def transcript_candidates(agent_id=None):
    home = os.path.expanduser("~")
    pats = []
    aid = agent_id or "*"
    pats.append(os.path.join(home, ".claude", "projects", PROJECT_SLUG, "*", "subagents", f"agent-{aid}.jsonl"))
    tmp = os.environ.get("TEMP") or os.environ.get("TMP") or ""
    if tmp:
        pats.append(os.path.join(tmp, "claude", PROJECT_SLUG, "*", "tasks", f"{aid}.output"))
    out = []
    for p in pats:
        out.extend(glob.glob(p))
    return sorted(set(out), key=os.path.getmtime, reverse=True)


def is_critic(path):
    meta = path.replace(".jsonl", ".meta.json")
    if os.path.exists(meta):
        try:
            return "player-critic" in open(meta, encoding="utf-8").read()
        except OSError:
            pass
    try:
        with open(path, encoding="utf-8") as f:
            return "critic_guard.mjs" in f.read()
    except OSError:
        return False


def extract(path):
    handbacks, texts = [], []
    with open(path, encoding="utf-8") as f:
        for line in f:
            try:
                d = json.loads(line)
            except json.JSONDecodeError:
                continue
            m = d.get("message")
            if not isinstance(m, dict) or not isinstance(m.get("content"), list):
                continue
            if m.get("role") not in (None, "assistant") and d.get("type") != "assistant":
                continue
            for part in m["content"]:
                if part.get("type") == "tool_use" and part.get("name") == "SubagentHandback":
                    msg = part.get("input", {}).get("message", "")
                    if msg:
                        handbacks.append(msg)
                elif part.get("type") == "text" and d.get("type") == "assistant":
                    texts.append(part.get("text", ""))
    # Prefer the longest full review; the first handback attempt is normally the complete one.
    reviews = [t for t in handbacks + texts if "# Player Review" in t]
    if reviews:
        return max(reviews, key=len)
    allc = handbacks + texts
    return max(allc, key=len) if allc else ""


def main():
    if len(sys.argv) != 3:
        print(__doc__)
        sys.exit(1)
    key, out = sys.argv[1], sys.argv[2]
    if key == "--latest":
        cands = [p for p in transcript_candidates() if is_critic(p)]
    else:
        cands = transcript_candidates(key)
    if not cands:
        sys.exit("No transcript found.")
    text = extract(cands[0])
    if not text:
        sys.exit(f"No review text in {cands[0]}")
    os.makedirs(os.path.dirname(os.path.abspath(out)), exist_ok=True)
    with open(out, "w", encoding="utf-8", newline="\n") as f:
        f.write(text.strip() + "\n")
    print(f"Saved {len(text)} chars from {cands[0]} -> {out}")


if __name__ == "__main__":
    main()
