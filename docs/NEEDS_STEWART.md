# Things Claude needs from Stewart

Claude keeps this list short and gives exact click-by-click steps. Nothing here blocks Claude from working.

## 1. (Optional, 2 minutes) Let the blind critic hand its review back directly
Right now the critic's safety guard also blocks the button it uses to send its review back, so Claude digs the review out of the critic's log instead. It works, but this small fix makes it cleaner. Claude is not allowed to edit this file itself, on purpose.
1. Open File Explorer and go to `C:\Users\stewa\ClaudeProjects\Noclip\.claude\hooks\`.
2. Right-click `critic_guard.mjs`, choose "Open with", then "Notepad".
3. Find the line that says `const tool = input.tool_name || "";` (around line 18).
4. Click at the end of that line, press Enter, and paste this exact line:
   `if (tool === "SubagentHandback") allow();`
5. Save (Ctrl+S) and close Notepad. Done. Nothing else changes: the critic still cannot read anything outside the review folder.
