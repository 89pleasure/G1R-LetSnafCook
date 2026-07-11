# Let Snaf Cook

Snaf finally steps up his cooking game.

In the early game, Snaf's daily food reward is useful enough: 3x Meatbug Ragout whenever you ask him for something to eat. As you help him recover better recipes, however, that reward should improve with him.

This UE4SS Lua mod upgrades Snaf's daily reward as his recipe quests progress. After The Forgotten Recipe, Snaf gives you 3x Brock's Stew. After his Syra recipe quest, he upgrades again to 3x Syra's Stew.

## Features

- Keeps Snaf's original daily Meatbug Ragout reward before the recipe quests are completed
- Upgrade 1: replaces the reward with 3x Brock's Stew after The Forgotten Recipe
- Upgrade 2: replaces the reward with 3x Syra's Stew after completing the Syra recipe quest
- Configurable upgraded reward mixes, such as 1x Syra's Stew and 2x Brock's Stew
- Optional in-game configuration through SharedModMenu
- Works with existing savegames
- Lightweight UE4SS Lua mod
- No new items, just a small configurable reward progression fix

## Configuration

If SharedModMenu is installed, open it in game and use the `Let Snaf Cook` tab.
Each upgrade has three portion slots:

- `1` = Meatbug Ragout
- `2` = Brock's Stew
- `3` = Syra's Stew

Changes made in SharedModMenu are saved to `LetSnafCook.ini`.

You can also edit `LetSnafCook.ini` in the mod folder directly:

```ini
Upgrade1=meatbug,brock,brock
Upgrade2=meatbug,brock,syra
```

`Upgrade1` is active after The Forgotten Recipe unlocks Brock's Stew. `Upgrade2` is active after Snaf's Syra recipe quest unlocks Syra's Stew. Each upgrade must contain exactly 3 portions.

Allowed values:

- `meatbug` or `meat`
- `brock`
- `syra`

Commas and dots both work as separators, so `Upgrade2=brock,brock.syra` is treated like `Upgrade2=brock,brock,syra`.

The mod still checks quest progress. If a configured portion is not unlocked, it falls back to the next lower available food: Syra -> Brock -> Meatbug Ragout. For example, `Upgrade2=brock,brock,syra` becomes `meatbug,meatbug,syra` if Syra is done but Brock is not. If an upgrade line is invalid, Snaf uses 3x the lower available food for that upgrade.

## Requirements

- Gothic 1 Remake
- UE4SS
- PleasureLib
- Optional: SharedModMenu for in-game configuration

Install `PleasureLib` next to this mod in the game's UE4SS `Mods` directory.
`Let Snaf Cook` can load it from the neighboring `PleasureLib` folder even when
`mods.txt` does not define the load order.

## Installation

Copy `package/LetSnafCook` into your UE4SS `Mods` directory:

```text
G1R/Binaries/Win64/ue4ss/Mods/
```

The final installed paths should look like this:

```text
G1R/Binaries/Win64/ue4ss/Mods/LetSnafCook/Scripts/main.lua
G1R/Binaries/Win64/ue4ss/Mods/LetSnafCook/Scripts/modmenu.lua
G1R/Binaries/Win64/ue4ss/Mods/LetSnafCook/Scripts/pleasure_lib_loader.lua
G1R/Binaries/Win64/ue4ss/Mods/LetSnafCook/LetSnafCook.ini
```

## Compatibility

This mod only touches Snaf's daily food reward logic. It should be compatible with most other mods unless they modify the same dialogue reward or inventory handling.

## Nexus Assets

Nexus image assets are stored in `assets/nexus`:

- `let-snaf-cook-header-1300x372.png`
- `let-snaf-cook-gallery.png`

## Why?

Because each time you help Snaf improve his cooking, he should probably stop handing you the same old weak ragout.

Let Snaf cook.
