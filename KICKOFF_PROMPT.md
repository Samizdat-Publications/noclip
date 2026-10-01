# Session 1 kickoff prompt

Launch (PowerShell):
```
cd C:\dev\noclip
claude --model claude-opus-5-5 --effort xhigh --permission-mode auto
```
Then paste everything inside the box below as your first message.

```
You are starting a brand new project in this folder: an original first-person surreal horror game set in the Backrooms. I'm Stewart, the owner. I'm not a programmer, so don't let my ideas of what is possible limit you. You have full authority over engine, language, architecture, tools, art direction details, and game design. I want you to work autonomously for long stretches, make decisions without asking me, and stop only at the session boundaries defined in CLAUDE.md.

Before doing anything, read CLAUDE.md, docs/VISION.md, and docs/ROADMAP.md in full. They are the rules, the creative bible, and the plan. You may improve VISION.md and ROADMAP.md; log why in docs/DECISIONS.md.

What I care about, in order:
1. Graphics, lighting, and atmosphere at the highest fidelity that runs in real time on my RTX 5070 (and on a high-end laptop with a lower preset). This is the whole point.
2. Sound design that makes you feel physically there.
3. Surreal non-euclidean spaces and real fear from a monster.
4. A loop that makes me want one more run, with progress that carries between runs.
5. A URL I can send people. An itch.io download page is fine if native looks better than web.

This session is Milestone 1, Foundation and Look-Dev:
a. Environment check. Verify or install git, git LFS, Node, Python, ffmpeg, Blender, Godot 4.7.x, and gh, and confirm captures render on the GPU. Anything that needs me goes in docs/NEEDS_STEWART.md with exact steps; keep going.
b. Set up the repo: git, LFS, the layout from CLAUDE.md, and a private GitHub repo via gh if I'm logged in.
c. Look-dev spike. Build the same hero slice of Level 0 (about 30 m x 30 m: corridors, one large open room, a doorway, a fluorescent grid with some dead and failing tubes, damp carpet, stained walls) at final quality in Godot Forward+, plus a time-boxed three.js WebGPU version (no more than about a quarter of this session). Capture both the same way and let player-critic judge them blind as "Build A" and "Build B". Pick the engine on that evidence plus the practical factors in CLAUDE.md. If it's close, Godot wins. Record the decision.
d. Build the review machinery in the chosen engine: autoplay bot, one-command capture harness, review packet, the Gemini video-and-audio critic script, scores.csv, LEDGER.md, perf overlay. Prove the critic guard works: ask player-critic to read CLAUDE.md and confirm it gets blocked. If it isn't blocked, fix that before anything else.
e. Push the hero slice through at least three critic loops. Lighting, materials, and atmosphere are the entire point of this milestone. Make it look like a real place that is wrong.
f. Follow the end-of-session protocol in CLAUDE.md, then give me the next-session command and prompt.

Use the Sonnet subagents (asset-smith, scout) at medium effort for well-defined parallel work like research, Blender batch scripts, and generation jobs. Keep architecture, rendering, and every taste decision yourself. My API keys for OpenAI, Gemini, ElevenLabs, Meshy, and PixelLab are in .env. Never read or print that file; load it inside scripts.

Don't ask me questions. Decide, log it, and keep moving. Go.
```

## Every session after that
Claude ends each session by printing the exact launch command and prompt for the next one. If you ever need a generic one:
```
cd C:\dev\noclip
claude --model claude-opus-5-5 --effort high --permission-mode auto
```
```
Continue the project. Read CLAUDE.md, then docs/HANDOFF.md, then docs/STEWART_FEEDBACK.md, then the VISION.md sections for the next milestone in docs/ROADMAP.md. Work autonomously per CLAUDE.md, run the critic loop, and stop only at a session boundary with the full end-of-session protocol.
```
