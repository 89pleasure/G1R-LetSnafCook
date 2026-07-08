# Let Snaf Cook

Snaf finally steps up his cooking game.

In the early game, Snaf's daily food reward is useful enough: 3x Meatbug Ragout whenever you ask him for something to eat. Later on, however, that reward becomes pretty underwhelming.

This UE4SS Lua mod upgrades Snaf's daily reward after you complete his Syra recipe quest. Once the quest is finished, Snaf gives you 3x Syra's Stew instead of 3x Meatbug Ragout.

## Features

- Keeps Snaf's original daily Meatbug Ragout reward before the quest is completed
- Upgrades the reward to 3x Syra's Stew after completing the Syra recipe quest
- Works with existing savegames
- Lightweight UE4SS Lua mod
- No new items, no balance overhaul, just a small reward progression fix

## Requirements

- Gothic 1 Remake
- UE4SS

## Installation

Copy `Mods/LetSnafCook` into your UE4SS `Mods` directory:

```text
G1R/Binaries/Win64/ue4ss/Mods/
```

The final installed path should look like this:

```text
G1R/Binaries/Win64/ue4ss/Mods/LetSnafCook/Scripts/main.lua
```

## Compatibility

This mod only touches Snaf's daily food reward logic. It should be compatible with most other mods unless they modify the same dialogue reward or inventory handling.

## Nexus Assets

Nexus image assets are stored in `assets/nexus`:

- `let-snaf-cook-header-1300x372.png`
- `let-snaf-cook-gallery.png`

## Why?

Because by the time you help Snaf improve his cooking, he should probably stop handing you the same old weak ragout.

Let Snaf cook.
