# Neko_Hub — Agent Guide

## What This Is

Roblox exploit hub (Luau) loaded via an executor at runtime. All scripts are client-side only and run inside a live Roblox game session. There is **no build system, no tests, no lint, no CI**.

## Entry Point Chain

```
Loader.lua  (bootstrap — loaded via executor)
  ├── Load.lua           (animated loading screen UI)
  ├── Neko_HubGui/Gui.lua     (WindUI window setup)
  ├── Neko_HubGui/Menu.lua    (UI tabs, connects callbacks to LogicFunction)
  └── Neko_HubGui/LogicFunction.lua  (core game logic: Combat, ESP, Aim)
```

- `Loader.lua` uses `game:HttpGet()` to fetch each script from GitHub raw URLs or local files via `isfile()`/`readfile()`.
- `Gui.lua` depends on **WindUI** (`Footagesus/WindUI`), fetched at runtime.
- `Menu.lua` loads `LogicFunction.lua` via `require` / `readfile` / HTTP fallback.
- `neko_hub.lua` is a **standalone legacy script** for a different game (uses Obsidian library). It is not part of the Neko_Hub loader chain.

## Coding Conventions

- All files use `--!strict` mode.
- Services accessed via `game:GetService()`. Executor-specific globals used: `getgenv`, `gethui`, `hookmetamethod`, `newcclosure`, `checkcaller`, `getnilinstances`, `isfile`, `readfile`, `writefile`, `makefolder`, `getcustomasset`/`getsynasset`.
- UI framework: **WindUI** (window/tabs/sections/toggles/sliders/dropdowns/colorpickers). All elements use `Flag` property for config persistence via `Window.ConfigManager:Config("NekoHubConfig")` (auto-saved to `WindUI/Neko_Hub/configs/`).
- Color theme: `"NekoTheme"` (custom pink theme, set in `Gui.lua`).
- Config/data stored in `getgenv()` globals shared across modules.
- Remotes referenced by name via `ReplicatedStorage:WaitForChild("Remotes"):...`.
- Floating on-screen toggle icons use `ScreenGui` (parented to `gethui()` or `PlayerGui`) with `TextButton` + `UICorner` for circular design.

## Key Gotchas

- Scripts are fetched at runtime from GitHub raw URLs (`https://raw.githubusercontent.com/nyatoru/Neko_Hub/main/...`). After pushing, fetchers load the new content immediately for remote users.
- Logo/icon downloaded to `Neko_Hub/Icon/logo.jpg` on first load via `writefile`.
- `LogicFunction.lua` is the largest and most complex file (~2200 lines). It contains all game-specific logic. Edit this file for feature changes.
- `Menu.lua` wires UI elements to `LogicFunction` methods (e.g., `Combat.SetAutoParry`, `ESP.SetColor`, `Aim.SetSilentAim`).
- `neko_hub.lua` references a completely different game's remotes and mechanics — do not mix changes between the two scripts.

## Features Added

| Feature | Description |
|---|---|
| **Auto Pallet Drop** | Auto-drops pallets when killer is within trigger distance + collection-service cache |
| **Fast Vault** | Replaces vault animation with faster one + speed slider via `hookVault` + `CharacterAdded` |
| **RotationHook Skillcheck** | Alternative skillcheck mode via `hookmetamethod(__index)` on `.Rotation` + RemoteEvent detection |
| **Floating Aim Icons** | Draggable circular `ScreenGui` buttons (G/V) for one-click aim on/off |
| **Auto-save/load Config** | `WindUI` Flags + `NekoConfig:Save()` in all callbacks + `NekoConfig:Load()` on start |
| **Veil Aim** | Silent aim + aim lock for spear/ballistic weapons (separate from gun aim) |
| **ESP Colors (customizable)** | Per-kind colorpickers for Generator/Pallet/Window/Zombie/Player/Downed |
| **Player State ESP** | Color change + state label for downed players |
| **Hide Done Generator** | Hides generator ESP when repair reaches 100% |
| **Zombie/Pallet ESP** | New ESP kinds: Pallet and Zombie (SCP) |
| **FOV Enforcement** | `RenderStepped` loop forces custom FOV every frame (prevents game override) |
| **Map Sync** | Centralized `setMapContainer` with `DescendantAdded`/`DescendantRemoving`/`Destroying` + periodic resync |
| **Performance** | Single merged `Heartbeat` for parry+dodge, `lastDistances` cache to skip redundant distance text updates
