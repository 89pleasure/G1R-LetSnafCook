# Repository Guidelines

## Project Structure & Module Organization

This repository contains a UE4SS Lua mod for Gothic 1 Remake.

- `package/LetSnafCook/Scripts/main.lua` contains all runtime mod logic.
- `package/LetSnafCook/LetSnafCook.ini` is the user-facing configuration file.
- `package/LetSnafCook/enabled.txt` and `readme.txt` are packaged with the mod.
- `README.md` is the public project documentation.
- `assets/nexus/` stores Nexus Mods image assets.
- `package/LetSnafCook.zip` is package output; avoid editing it by hand.

There is currently no separate test suite or build system.

## Build, Test, and Development Commands

No build step is required. To install for local testing, copy the mod folder:

```powershell
Copy-Item .\package\LetSnafCook `
  "D:\SteamLibrary\steamapps\common\Gothic 1 Remake\G1R\Binaries\Win64\ue4ss\Mods\" `
  -Recurse -Force
```

Useful checks:

```powershell
rg -n "Upgrade1|Upgrade2|BROCK_QUEST" package/LetSnafCook
git diff
```

On this machine, `git` may not be on `PATH`. Use the GitHub Desktop bundled binary when needed:

```powershell
& "C:\Users\lenna\AppData\Local\GitHubDesktop\app-3.6.2\resources\app\git\cmd\git.exe" status --short
```

If a Lua interpreter is available, run a syntax check with `luac -p package/LetSnafCook/Scripts/main.lua`.

## Coding Style & Naming Conventions

Use Lua with 4-space indentation and local functions/variables. Keep constants near the top of `main.lua` and use uppercase names for object paths, e.g. `MEATBUG_RAGOUT`. Prefer small helper functions over inline repeated logic. Keep files ASCII-only unless existing game text requires otherwise.

Line endings are enforced by `.gitattributes`: Lua, Markdown, text, and git metadata use LF; PNG files are binary.

## Testing Guidelines

Primary testing is in-game through UE4SS. Verify:

- before recipe quests: original `3x Meatbug Ragout`
- after The Forgotten Recipe: `Upgrade1`
- after Syra quest: `Upgrade2`
- invalid config and locked-food fallback behavior

Check UE4SS logs for `Loaded config from ...` and fallback messages.

## Commit & Pull Request Guidelines

Commit history uses short imperative messages, for example `Add configurable Snaf reward upgrades`. Keep commits focused on one behavior or documentation change.

Pull requests should include a concise summary, changed files, in-game test notes, and any relevant UE4SS log output. If visual/Nexus assets change, include before/after screenshots.

## Configuration Notes

`LetSnafCook.ini` supports `Upgrade1` and `Upgrade2`, each with exactly three portions. Allowed values are `meatbug`/`meat`, `brock`, and `syra`; comma and dot separators are accepted.
