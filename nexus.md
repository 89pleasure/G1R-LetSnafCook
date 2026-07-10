# Let Snaf Cook

Snaf finally steps up his cooking game.

In the early game, Snaf's daily food reward is useful enough: 3x Meatbug Ragout whenever you ask him for something to eat. But after you help him recover better recipes, it feels strange that he keeps handing you the same old ragout.

This UE4SS Lua mod upgrades Snaf's daily food reward as his recipe quests progress.

## What It Does

- Before the recipe quests: Snaf keeps his original 3x Meatbug Ragout reward
- After The Forgotten Recipe: the reward upgrades to Brock's Stew
- After Snaf's Syra recipe quest: the reward upgrades to Syra's Stew
- The upgraded rewards can be customized
- Existing savegames are supported
- No new items are added
- The mod only changes Snaf's daily food reward logic

## SharedModMenu Support

The mod now supports optional in-game configuration through SharedModMenu.

If SharedModMenu is installed, open the menu in game and use the Let Snaf Cook tab. Each upgrade has three portion slots:

- 1 = Meatbug Ragout
- 2 = Brock's Stew
- 3 = Syra's Stew

Changes made in SharedModMenu are saved to LetSnafCook.ini.

SharedModMenu is optional. If you do not install it, Let Snaf Cook still works normally and can still be configured through the ini file.

## Manual Configuration

You can edit LetSnafCook.ini in the mod folder:

```ini
Upgrade1=meatbug,brock,brock
Upgrade2=syra,syra,syra
```

Upgrade1 is active after The Forgotten Recipe unlocks Brock's Stew.

Upgrade2 is active after Snaf's Syra recipe quest unlocks Syra's Stew.

Each upgrade must contain exactly three portions.

Allowed values:

- meatbug or meat
- brock
- syra

Commas and dots both work as separators, so this also works:

```ini
Upgrade2=brock,brock.syra
```

## Quest Gating And Fallbacks

The mod still checks quest progress.

If a configured portion is not unlocked yet, Snaf falls back to the next lower available food:

Syra -> Brock -> Meatbug Ragout

For example, if Upgrade2 is configured as:

```ini
Upgrade2=brock,brock,syra
```

but Syra is done and Brock is not, the reward becomes:

```text
meatbug,meatbug,syra
```

If an upgrade line is invalid, Snaf uses 3x the lower available food for that upgrade.

## Requirements

- Gothic 1 Remake
- UE4SS
- Optional: SharedModMenu for in-game configuration

## Installation

Install the mod folder into your UE4SS Mods directory:

```text
G1R/Binaries/Win64/ue4ss/Mods/LetSnafCook/
```

The installed folder should include:

```text
LetSnafCook/enabled.txt
LetSnafCook/LetSnafCook.ini
LetSnafCook/readme.txt
LetSnafCook/Scripts/main.lua
LetSnafCook/Scripts/modmenu.lua
```

If you use SharedModMenu, install SharedModMenu separately into the same UE4SS Mods directory.

## Compatibility

This mod only touches Snaf's daily food reward logic. It should be compatible with most other mods unless they modify the same dialogue reward or inventory handling.

SharedModMenu integration is optional and does not create a hard dependency.

## Updating

When updating from an older version, you can keep your existing LetSnafCook.ini if you already customized it.

The new modmenu.lua file is required for SharedModMenu support, so make sure the whole LetSnafCook folder is replaced or merged when updating.

## Changelog

### SharedModMenu Update

- Added optional SharedModMenu integration
- Added in-game controls for Upgrade1 and Upgrade2
- Added reset actions for both upgrade stages
- SharedModMenu changes are saved back to LetSnafCook.ini
- LetSnafCook.ini remains supported for manual configuration
- SharedModMenu is optional; the mod still loads and works without it

## Why?

Because each time you help Snaf improve his cooking, he should probably stop handing you the same old weak ragout.

Let Snaf cook.
