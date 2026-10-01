# Things Claude needs from Stewart

Claude keeps this list short and gives exact click-by-click steps. Nothing here blocks Claude from working.

## 1. (Important, 3 minutes) Add your Gemini API key
The second critic, the one that watches the gameplay video and HEARS the sound, needs a Gemini key. The line for it in your keys file is empty, so that critic could not run this session. (Your ElevenLabs key works because it is set elsewhere on your PC. The OpenAI line is also empty, but nothing needs it yet.)
1. Open https://aistudio.google.com/apikey in your browser and sign in with your Google account.
2. Click "Create API key" (pick any project it offers), then click the copy icon next to the new key.
3. Open File Explorer and go to `C:\Users\stewa\ClaudeProjects\Noclip\`. Right-click the file named `.env`, choose "Open with", then "Notepad". (If you do not see `.env`, click View, then Show, then "Hidden items".)
4. Find the line `GEMINI_API_KEY=` and paste the key right after the `=` sign, with no spaces. It should look like `GEMINI_API_KEY=AIza...`.
5. Save (Ctrl+S) and close Notepad. That is all. Next session the video critic runs automatically.

## 2. (Optional, 2 minutes) Let the blind critic hand its review back directly
Right now the critic's safety guard also blocks the button it uses to send its review back, so Claude digs the review out of the critic's log instead. It works, but this small fix makes it cleaner. Claude is not allowed to edit this file itself, on purpose.
1. Open File Explorer and go to `C:\Users\stewa\ClaudeProjects\Noclip\.claude\hooks\`.
2. Right-click `critic_guard.mjs`, choose "Open with", then "Notepad".
3. Find the line that says `const tool = input.tool_name || "";` (around line 18).
4. Click at the end of that line, press Enter, and paste this exact line:
   `if (tool === "SubagentHandback") allow();`
5. Save (Ctrl+S) and close Notepad. Done. Nothing else changes: the critic still cannot read anything outside the review folder.

## 3. (Before session 4, the monster) Top up Meshy credits
The Meshy account (3D model generator) has only 3 credits left, so it could not make anything this session. Props were built in Blender instead, which is fine for now. The monster in session 4 needs Meshy for its base body and animation.
1. Open https://www.meshy.ai and sign in.
2. Click your profile picture (top right), then "Subscription" or "Credits".
3. Add credits so the balance is at least 1,000 (or upgrade the plan if it offers a monthly credit bundle). About 1,000 credits covers the monster plus a handful of props.
4. Nothing else to do: Claude checks the balance automatically next time.
