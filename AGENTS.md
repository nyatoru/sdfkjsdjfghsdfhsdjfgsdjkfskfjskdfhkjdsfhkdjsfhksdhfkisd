# Neko_Hub — Agent Guide

Roblox exploit hub (Luau) for Violence District. Loaded via executor at runtime. All scripts client-side only. **No build, no tests, no lint, no CI.**

## Entry Chain

```
Loader.lua (bootstrap via executor)
 ├── Load.lua (animated loading screen)
 ├── Neko_HubGui/Gui.lua (WindUI window setup)
 ├── Neko_HubGui/Menu.lua (UI tabs → LogicFunction callbacks)
 └── Neko_HubGui/LogicFunction.lua (~2370 lines, core logic)
```

- `Loader.lua` fetches children via `game:HttpGet()` from GitHub raw URLs or local `isfile()`/`readfile()` fallback.
- `Menu.lua` loads `LogicFunction.lua` via `require` → `readfile` → HTTP → `getgenv().Neko_HubLogic`.
- `Gui.lua` depends on **WindUI v1.6.65** (`Footagesus/WindUI`), fetched at runtime.
- `neko_hub.lua` is a **standalone legacy script** (different game, Obsidian library). Do not merge with it.

## Coding & Conventions

- All files use `--!strict`. Services via `game:GetService()`.
- Executor globals used: `getgenv`, `gethui`, `hookmetamethod`, `newcclosure`, `checkcaller`, `isfile`, `readfile`, `writefile`, `makefolder`, `firesignal`.
- UI: **WindUI** (Window → Tab → Section → Toggle/Slider/Dropdown/Colorpicker). API note: `Colorpicker` lowercase `p`.
- Config: `local NekoConfig = Window.ConfigManager:Config("NekoHubConfig")` — saves to `WindUI/Neko_Hub/configs/NekoHubConfig.json`. Every element has a `Flag` (prefix `neko_`). Callbacks call `NekoConfig:Save()`. **Gotcha**: `NekoConfig:Load()` restores UI visuals but does NOT fire callbacks, so `LogicFunction.lua` also reads the config JSON directly at startup to sync logic state.
- Theme: custom `"NekoTheme"` (pink), set in `Gui.lua`. `HideSearchBar = true`.
- Remotes: `ReplicatedStorage:WaitForChild("Remotes"):...`
- On-screen floating elements: `ScreenGui` parented to `gethui()` or `PlayerGui`, using `TextButton` + `UICorner` (circular, draggable).

## LogicFunction.lua Architecture

Exports a single `Logic` table at `getgenv().Neko_HubLogic` with sections:

| Section | Contents |
|---|---|
| `Logic.Combat` | Auto Parry/Dash/Dodge, Auto Pallet, Auto Skillcheck (2 modes), Fast Vault |
| `Logic.ESP` | 6 kinds: Generator/Pallet/Window/Hook/SCP/Player. Per-kind Color3 + color lerp (gen: orange→green). Player state (downed). Hide done gen. |
| `Logic.Aim` | Gun aim (Silent/AimLock) + Veil aim (spear). FOV circles via `Drawing`. Target mode (Killer/Survivor). Wallcheck, predict, smooth. |
| `Logic.Player` | Unlimited zoom, custom FOV (enforced via `RenderStepped` every frame) |

### ESP internals
- `type ESPKind = "Generator" | "Pallet" | "Window" | "Hook" | "SCP" | "Player"`
- Map objects detected via `setMapContainer()` with `DescendantAdded`/`DescendantRemoving`/`Destroying` + periodic 10s resync.
- Per-kind detection: `isGenerator()`, `isPallet()`, `isWindowObj()`, `isHook()`, `isZombie()`.
- `classifyAndTrack()` dispatches by kind. `tracked[model]` stores highlight + billboard.
- `ensureDistLoop()` — single merged loop for all ESP label updates + `lastDistances` cache (skip if dist change <1m).

### Skillcheck modes (`skillCheckMode`)
| Mode | Mechanism | Input |
|---|---|---|
| `"Crossing"` (default) | `RenderStepped` polls `PlayerGui.SkillCheckPromptGui.Check`, detects zone crossing via `Line.Rotation` | `VirtualInputManager:SendKeyEvent(Space)` / `SendTouchEvent` (mobile) |
| `"RotationHook"` | `hookmetamethod(game, "__index")` on `.Rotation` → returns `goal.Rotation + 104`. Detection via `SkillCheckEvent` RemoteEvent under `Remotes.Generator`/`Remotes.Healing`. | `firesignal` or `VirtualInputManager` |

### Skillcheck key: `PlayerGui` must be defined globally. Currently `local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")` at top of file.

### Lobby detection
- `LocalPlayer:GetPropertyChangedSignal("Team")` → `lobbyLocked` flag.
- Team names that trigger lock: `"spectator"`, `""`, `"lobby"`.
- Guards added to: combat heartbeat, auto skillcheck, auto pallet, ESP dist loop.

### Floating aim icons
- Two circular `ScreenGui` buttons (`G`/`V`), draggable, at right edge of screen.
- Each icon shows only when its feature (Gun/Veil) is not `"Disabled"` in the dropdown.
- Hide/show per-icon on `RenderStepped`.

### Auto Pallet
- `CollectionService:GetTagged("PalletPoint")` cache with signal-based add/remove.
- Drops when player within `PLAYER_INTERACT_DISTANCE` (6) and killer within `TRIGGER_DISTANCE` (default 13.2).
- Debounce per pallet (5s cooldown). Skips if health ≤50 / carrying / doing action.

### Fast Vault
- Hooks `Animator.AnimationPlayed` on character. Replaces `83873880822918` with `136962284480779`. Speed adjustable (1.0–5.0).
- Auto-rehooks on `CharacterAdded`.

### Killer notification
- One-time popup on **match end** (team transitions to spectator/lobby).
- Shows `"⚠ Match Over — Killer: [name]"` (amber) or `"⚔ Match Over — You were the Killer"` (red).
- Auto-destroys after 4s. Re-arms on next match.

## Key Gotchas

- After pushing to `nyatoru/Neko_Hub`, remote users load new content immediately via `game:HttpGet()`. No deploy step needed.
- `LogicFunction.lua` is the only file for gameplay logic changes. `Menu.lua` wires UI → Logic setters.
- Config file is at executor-specific path: `WindUI/Neko_Hub/configs/NekoHubConfig.json`.
- `neko_hub.lua` is for a completely different game — do not copy code or remotes from it.
- `GitHub raw URLs` point to `nyatoru/Neko_Hub` — update these if repo moves.
