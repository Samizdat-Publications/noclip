# NOCLIP: the plan and how to run it

## How this works
```
 You (5 min between sessions: play it, jot notes)
          |
          v
 Opus 5.5 lead dev  <---- CLAUDE.md (rules) + VISION.md (bible) + ROADMAP.md (plan) + HANDOFF.md (memory)
   |   builds the game, owns every taste decision
   |
   |-- asset-smith (Sonnet, medium)   Blender headless, Meshy, ElevenLabs, textures
   |-- scout (Sonnet, medium)         current docs and API research
   |
   |-- capture harness  -> random seed, autoplay bot, stills + motion grids + video w/ audio + perf
   |        |
   |        v
   |   player-critic (Sonnet high; Opus at milestone gates)   BLIND: sees only review/inbox
   |   Gemini critic (watches the video and HEARS the audio)
   |        |
   |        v
   |   LEDGER.md: every complaint gets FIX / DEFER / REJECT, then the loop repeats
   |
   |-- qa-auditor (Sonnet high) at session end: checks every "done" claim is actually true
   v
 Handoff, commit, and the exact command + prompt for your next session
```

## The decisions I made, and why
| Decision | Choice | Why |
|---|---|---|
| Engine | Godot 4.7 (Forward+), with a blind bake-off against three.js WebGPU in session 1 | Realtime global illumination that works on procedurally generated rooms, real area lights for fluorescent panels, volumetric fog, and deterministic video capture with audio for the critic. Godot's web export cannot use its high-end renderer, so the bake-off decides whether a browser version can match it. |
| Unity / Unreal | Not used | Unity HDRP looks great but is slow and clunky for an AI to drive from the command line. Unreal is not installed and is the heaviest for an agent to iterate on. |
| Hosting | itch.io page with a download button (or Cloudflare Pages if web wins) | Gives you a shareable URL without giving up the high-end look. |
| Critics | Two blind critics plus you | Claude critic judges stills and motion grids. Gemini watches the actual video and hears the sound, which Claude cannot. Your notes outrank both. |
| Blindness | Enforced, not just requested | The critic's tools are limited to reading images, it loads no project instructions, and a hook blocks any file outside review/inbox. The builder is blocked from editing the critic. |
| Anti-gaming | The harness picks random seeds and an autoplay bot plays | The builder cannot hand-pick pretty screenshots. |
| Monster | Original design, Meshy to Blender pipeline | Meshy now does rigging and animation by API. Mixamo has no API and has been unreliable, so it is a fallback only. Nothing copied from the film or fan wikis. |
| Progression hook | "The Backrooms remember you" | Your chalk marks, footprints, and your dropped camcorder from past deaths show up in future runs, and the camcorder plays back how you died. Plus gear upgrades, shortcuts deeper, and lore tapes. |

## One-time setup (about 15 minutes)
Keep the project OUT of OneDrive. Syncing a game repo full of large files will cause problems.

1. Update Claude Code (the kit needs a recent version for auto mode and the critic's settings):
```
cd $env:USERPROFILE
claude update
claude --version
```
2. Make the folder and unzip the kit into it:
```
cd C:\
New-Item -ItemType Directory -Force -Path C:\dev\noclip | Out-Null
cd C:\dev\noclip
Expand-Archive -Path "$env:USERPROFILE\Downloads\noclip-kit.zip" -DestinationPath C:\dev\noclip -Force
```
3. Add your API keys:
```
cd C:\dev\noclip
Copy-Item .env.example .env
notepad .env
```
4. Have these installed (session 1 installs anything missing, but these save time): Git for Windows, Node.js LTS, Python 3.12+, Blender, Godot 4.7.x, ffmpeg, GitHub CLI logged in (`gh auth login`). Meshy's API requires a Meshy Pro plan or higher.

## Session 1
```
cd C:\dev\noclip
claude --model claude-opus-5-5 --effort xhigh --permission-mode auto
```
Paste the prompt from KICKOFF_PROMPT.md. Walk away. Windows will pop up on screen while it captures footage; that is normal, so leave the PC awake and don't use it for gaming at the same time.

## Model and effort plan
| Session | Milestone | Lead (Opus 5.5) effort |
|---|---|---|
| 1 | Foundation, engine bake-off, critic loop, hero room | xhigh |
| 2 | Infinite Level 0 and impossible geometry | xhigh |
| 3 | Sound | high |
| 4 | The monster | xhigh |
| 5 | Run loop and progression | high |
| 6-7 | Deeper levels (Underlot, Pipeworks, Pools, After Hours) | xhigh |
| 8 | Ship to itch.io | high |
| 9+ | Polish loops until the ship gate | high (max only for a nasty bug) |

Subagents are pinned in their files: asset-smith and scout are Sonnet 5.5 at medium, player-critic and qa-auditor are Sonnet 5.5 at high (judging images and catching false "done" claims is where cheap thinking costs you), and the critic is bumped to Opus for milestone gate reviews. Claude also prints the right command at the end of every session, so you don't need to memorize this table. If you start hitting usage limits, run that session at `high` instead of `xhigh`.

## Your job between sessions (5 to 10 minutes)
1. Read Claude's final message. Do anything on its "need from you" list (it lives in docs/NEEDS_STEWART.md too).
2. Play the build for 5 minutes. Write raw notes at the top of docs/STEWART_FEEDBACK.md ("hallway felt too clean", "monster looked goofy", "jumped at the light pop"). Claude treats your notes as the top-priority critique.
3. Start the next session with the command and prompt Claude gave you.

## Guardrails built in
- Paid API spend is logged in docs/SPEND.md with a soft cap per session (set SESSION_SPEND_CAP_USD in .env; default $40).
- Claude cannot read your .env, force-push, or edit the critic.
- Every session ends with a commit and tag, so any session can be rolled back.
- The qa-auditor checks every "done" claim before you see it.

## If something goes sideways
| Problem | Do this |
|---|---|
| It stops to ask you a question | Reply: "Decide using VISION.md, log it in DECISIONS.md, and continue." |
| Critic scores look too generous | Tell the next session: "Run the gate review with the Opus critic and compare it to your own read of the frames." |
| It stopped without a handoff | Start a session with: "The last session ended without a handoff. Reconstruct state from git log and docs, write docs/HANDOFF.md, then continue." |
| A session runs very long with no visible progress | Interrupt with: "Stop at the next clean point, run the end-of-session protocol." |
| Captures look black or tiny | The PC probably slept or the display was locked during capture. Keep it awake during sessions. |

## Honest expectations
- Expect roughly 8 to 12 sessions to a shippable game, and more to make it great. The polish loops are where "good" becomes "scary."
- AI-generated monsters tend to look generic at first; the Blender distortion pass and the VHS treatment are what make it unsettling, and that takes several critic loops.
- The Claude critic judges stills and motion grids; only the Gemini critic and you can judge sound and real motion. Your 5 minutes of play matter.
