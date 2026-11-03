@echo off
setlocal
cd /d "%~dp0"
set "GODOT_EXE=D:\Godot\Godot_v4.7.1-stable_win64\Godot_v4.7.1-stable_win64.exe"
if not exist "%GODOT_EXE%" (
    set "GODOT_EXE=D:\Godot\Godot_v4.7.1-stable_win64\Godot_v4.7.1-stable_win64_console.exe"
)
start "" "%GODOT_EXE%" --path "%~dp0." res://main.tscn
