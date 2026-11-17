# weave-and-wander

The active game and Git root is `D:/workspace/weave-and-wander`. Open `project.godot` here. The former `D:/GodotProjects/weave-and-wander/prototypes/dollhouse-3d` path is retired; do not use it for new work. The 2D project at `D:/GodotProjects/weave-and-wander` and the separate papercut editor are distinct projects.

Read `Docs/HANDOFF.md` and `DEVELOPMENT_STATUS.md` for current status. `Docs/WORKSPACE_HANDOFF_2026-11-09.md` is a pre-migration historical snapshot. `Docs/DEVELOPMENT_LOG.md`, `Docs/MVP_PLAN.md`, and other shared planning documents were copied here for independent access.

The Wiki is a separate Git repository at `D:/workspace/W&W Wiki`. Its local records and media stay there; game export tools write into its `public/assets` directory through `tools/wiki_paths.gd`.

Preserve existing staged, unstaged, and untracked work. Do not reset, clean, or bulk commit it. Use paths relative to this repository in new scripts and docs where possible. The Git remote still points to the former shared `weave-and-wander` GitHub repository; do not push it as a standalone project without deciding on a separate remote.
