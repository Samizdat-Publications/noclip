# Things Claude needs from Stewart

Claude keeps this list short and gives exact click-by-click steps. Nothing here blocks Claude from working.

## 1. (When you have 5 minutes) Play the new endless level and write what you felt
The game is now an endless, generated maze instead of the small test area. Your notes outrank every AI critic.
1. Double-click `Play NOCLIP.bat` in `C:\Users\stewa\ClaudeProjects\Noclip`.
2. Walk east down the long hall you start in. Hold the right mouse button now and then to look through the camcorder, especially down long halls.
3. Keep walking east down that hall for a minute or two. Read the writing on the walls.
4. Open `docs\STEWART_FEEDBACK.md` in Notepad and write a few lines at the top: what felt good, what felt off, what scared you, what bored you. Save.

## 2. (Optional, 2 minutes) Let the blind critic hand its review back directly
Right now the critic's safety guard also blocks the button it uses to send its review back, so Claude digs the review out of the critic's log instead. It works, but this small fix makes it cleaner. Claude is not allowed to edit this file itself, on purpose.
1. Open File Explorer and go to `C:\Users\stewa\ClaudeProjects\Noclip\.claude\hooks\`.
2. Right-click `critic_guard.mjs`, choose "Open with", then "Notepad".
3. Find the line that says `const tool = input.tool_name || "";` (around line 18).
4. Click at the end of that line, press Enter, and paste this exact line:
   `if (tool === "SubagentHandback") allow();`
5. Save (Ctrl+S) and close Notepad. Done. Nothing else changes: the critic still cannot read anything outside the review folder.

## 3. (Before the monster milestone) Get the free Meshy credits
The Meshy account (3D model generator) had only 3 credits. The monster is our own original design, and Meshy is the right tool for it because it can generate it on-theme and also rig and animate it.
1. Finish Meshy's onboarding (you found it gives 300 free credits).
2. That is enough for the monster: about 150 to 250 credits for a few design attempts, rigging, and roughly 8 animations (Claude's estimate; exact prices get checked before spending).

## Done
- Gemini API key (added 2026-10-01; the video critic and the graffiti images use it).
