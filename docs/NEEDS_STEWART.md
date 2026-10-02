# Things Claude needs from Stewart

Claude keeps this list short and gives exact click-by-click steps. Nothing here blocks Claude from working.

## 1. (When you have 5 minutes) Play the new build and write what you felt
Your notes outrank every AI critic. New since last time: hidden doorways you can only see through the camcorder, a person who appears only on tape and comes closer each time you look again, rooms three times too tall, chairs that turn to face you when you are not looking, real wallpaper and carpet, and a new sound pass (breathing, room echo, squelchy carpet, a low drone when something is near, and a building hum that rises, falls and every minute or so sags into near silence).
1. Double-click `Play NOCLIP.bat` in `C:\Users\stewa\ClaudeProjects\Noclip`.
2. Walk east down the long hall you start in and read the chalk on the walls. Hold the right mouse button to look through the camcorder.
3. Find the block in a nearby room with a chalk door drawn on it ("HERE?"). Look at it through the camcorder, then walk through.
4. Down a long hall, film for a few seconds; lower the camera and raise it again.
5. Open `docs\STEWART_FEEDBACK.md` in Notepad and write a few lines at the top: what felt good, what felt off, what scared you, what bored you, how it sounded (headphones help). Save.

## 2. (Optional, 2 minutes) Let the blind critic hand its review back directly
You said yes to this on 2026-10-02, but Claude cannot make this edit: the file is protected on purpose so Claude can never quietly make the critic go easier, and the safety system refused the change even with your approval. It has to be you. Nothing is broken without it.
Right now the critic's safety guard also blocks the button it uses to send its review back, so Claude digs the review out of the critic's log instead. It works, but this small fix makes it cleaner. Claude is not allowed to edit this file itself, on purpose.
1. Open File Explorer and go to `C:\Users\stewa\ClaudeProjects\Noclip\.claude\hooks\`.
2. Right-click `critic_guard.mjs`, choose "Open with", then "Notepad".
3. Find the line that says `const tool = input.tool_name || "";` (around line 18).
4. Click at the end of that line, press Enter, and paste this exact line:
   `if (tool === "SubagentHandback") allow();`
5. Save (Ctrl+S) and close Notepad. Done. Nothing else changes: the critic still cannot read anything outside the review folder.

## Done
- Meshy credits (2026-10-02): 2,000 in the account, shared. NOCLIP budget 1,000 credits; Claude checks in before going past it and uses the Meshy 7.1 flagship for the monster.
- Gemini API key (added 2026-10-01; the video critic, graffiti, carpet and wallpaper use it).
