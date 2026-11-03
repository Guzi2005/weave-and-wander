# Weave&Wander 针脚与远方桌面启动入口

双击项目根目录的 `启动针脚与远方.bat` 即可启动完整游戏。脚本会把项目根目录作为工作目录传给 Godot，避免从其他目录启动时资源路径或导入缓存错误。

默认查找：

1. `D:\Godot\Godot_v4.7.1-stable_win64\Godot_v4.7.1-stable_win64.exe`
2. `C:\Program Files\Godot\Godot.exe`
3. `C:\Program Files\Godot\Godot_v4.7.1-stable_win64.exe`

Godot 安装在其他位置时，可以运行：

```powershell
powershell -ExecutionPolicy Bypass -File .\启动针脚与远方.ps1 -GodotPath "D:\你的路径\Godot.exe"
```

桌面已创建“Weave&Wander 针脚与远方”快捷方式，显式运行此项目的 `main.tscn`。开发版入口依赖本机已安装的 Godot，不是独立导出的发行版。

在游戏内点击“恢复视角 · Home”或按 Home，可以退出人物跟随、恢复当前房间的默认观察角度与正常速度。如果编辑器调试器已暂停游戏，需先在编辑器恢复运行。

从 Godot 请使用 F5“运行项目”。F6“运行当前场景”可能启动独立模型或静态截图场景；这些场景没有完整营业逻辑。当前主场景的正常启动检查通过，尚未在编辑器中复现用户原先的静止状态，不能将相机复位当作对该状态的根因修复。

入口验证：`powershell -ExecutionPolicy Bypass -File .\启动针脚与远方.ps1 -Verify`，通过实际图形窗口运行营业冒烟检查后退出，日志位于 `captures/desktop_launch_test.log`。
