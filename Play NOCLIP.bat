@echo off
rem Play NOCLIP (Level 0 hero slice). WASD move, mouse look, Shift sprint, Ctrl crouch,
rem hold right mouse for the camcorder, F3 performance overlay, Esc pause (then Q quits).
cd /d "%~dp0"
set GODOT=%LOCALAPPDATA%\Microsoft\WinGet\Links\godot.exe
if not exist "%GODOT%" (
  echo Godot 4.7.2 is not installed. Run: winget install GodotEngine.GodotEngine
  pause
  exit /b 1
)
if not exist "game\.godot\imported" "%GODOT%" --headless --path game --import
start "" "%GODOT%" --path game
