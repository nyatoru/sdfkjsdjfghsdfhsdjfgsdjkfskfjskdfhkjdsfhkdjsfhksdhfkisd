--!strict

local WindUI = getgenv().WindUI
local Window = getgenv().Window
if not WindUI or not Window then
    warn("[Neko_Hub] WindUI or Window not initialized!")
    return
end

-- ponytail: require, readfile, or HTTP fallback for Logic module
local Logic = (function()
    local logicScript = typeof(script) == "Instance" and script.Parent and script.Parent:FindFirstChild("LogicFunction")
    if logicScript and logicScript:IsA("ModuleScript") then
        local success, module = pcall(require, logicScript)
        if success then return module end
    end
    
    local ok, fileContent = pcall(readfile, "Neko_Hub/Neko_HubGui/LogicFunction.lua")
    if ok then
        local loader, err = loadstring(fileContent)
        if loader then
            local success, module = pcall(loader)
            if success and module then return module end
        end
    end
    
    local ok2, remoteContent = pcall(game.HttpGet, game, "https://raw.githubusercontent.com/nyatoru/Neko_Hub/main/Neko_HubGui/LogicFunction.lua")
    if ok2 then
        local loader, err = loadstring(remoteContent)
        if loader then
            local success, module = pcall(loader)
            if success and module then return module end
        end
    end
    
    return getgenv().Neko_HubLogic
end)()

local Combat = Logic and Logic.Combat
local ESP = Logic and Logic.ESP
local Aim = Logic and Logic.Aim
local Player = Logic and Logic.Player
local NekoConfig = Window.ConfigManager:Config("NekoHubConfig")

-- Create Tabs
local VisualTab = Window:Tab({ Title = "Visual", Icon = "eye" })
local CombatTab = Window:Tab({ Title = "Combat", Icon = "swords" })
local AimTab = Window:Tab({ Title = "Aim", Icon = "crosshair" })
local PlayerTab = Window:Tab({ Title = "Player", Icon = "user" })
local ThemeTab = Window:Tab({ Title = "Theme", Icon = "palette" })

-- Combat Tab Sections (Tidied and organized)
local ParrySection = CombatTab:Section({ Title = "Auto Parry Settings" })
ParrySection:Toggle({
    Title = "Auto Parry",
    Desc = "Automatically parry killer attacks",
    Value = false,
    Flag = "neko_parry",
    Callback = function(value: boolean)
        if Combat and Combat.SetAutoParry then
            Combat.SetAutoParry(value)
            NekoConfig:Save()
        end
    end
})

ParrySection:Slider({
    Title = "Parry Distance",
    Value = { Min = 5, Max = 25, Default = 9 },
    Flag = "neko_parry_dist",
    Callback = function(value: number)
        if Combat and Combat.SetParryDistance then
            Combat.SetParryDistance(value)
            NekoConfig:Save()
        end
    end
})

ParrySection:Slider({
    Title = "Dash Parry Distance",
    Value = { Min = 20, Max = 50, Default = 30 },
    Flag = "neko_parry_dash",
    Callback = function(value: number)
        if Combat and Combat.SetDashParryDistance then
            Combat.SetDashParryDistance(value)
            NekoConfig:Save()
        end
    end
})

local DodgeSection = CombatTab:Section({ Title = "Auto Dodge Settings" })
DodgeSection:Toggle({
    Title = "Auto Dodge (Abysswalker)",
    Desc = "Automatically dodge Abysswalker skills",
    Value = false,
    Flag = "neko_dodge",
    Callback = function(value: boolean)
        if Combat and Combat.SetAutoDodgeAbyss then
            Combat.SetAutoDodgeAbyss(value)
            NekoConfig:Save()
        end
    end
})

DodgeSection:Slider({
    Title = "Dodge Distance",
    Value = { Min = 15, Max = 35, Default = 25 },
    Flag = "neko_dodge_dist",
    Callback = function(value: number)
        if Combat and Combat.SetDodgeDistance then
            Combat.SetDodgeDistance(value)
            NekoConfig:Save()
        end
    end
})

local PalletSection = CombatTab:Section({ Title = "Auto Drop Pallet Settings" })
PalletSection:Toggle({
    Title = "Auto Drop Pallet",
    Desc = "Automatically drop nearby pallets when killer is close",
    Value = false,
    Flag = "neko_pallet",
    Callback = function(value: boolean)
        if Combat and Combat.SetAutoPallet then
            Combat.SetAutoPallet(value)
            NekoConfig:Save()
        end
    end
})

PalletSection:Slider({
    Title = "Trigger Distance",
    Value = { Min = 5.0, Max = 25.0, Default = 13.2 },
    Flag = "neko_pallet_dist",
    Callback = function(value: number)
        local stepped = math.round(value * 10) / 10
        if Combat and Combat.SetPalletDistance then
            Combat.SetPalletDistance(stepped)
            NekoConfig:Save()
        end
    end
})

local SkillcheckSection = CombatTab:Section({ Title = "Skillcheck Settings" })
SkillcheckSection:Toggle({
    Title = "Auto Skillcheck",
    Desc = "Automatically hit perfect skillchecks",
    Value = false,
    Flag = "neko_skillcheck",
    Callback = function(value: boolean)
        if Combat and Combat.SetAutoSkillcheck then
            Combat.SetAutoSkillcheck(value)
            NekoConfig:Save()
        end
    end
})

SkillcheckSection:Dropdown({
    Title = "Skillcheck Mode",
    Desc = "Crossing: detect line crossing zone. RotationHook: hook __index for perfect hit",
    Values = { "Crossing", "RotationHook" },
    Value = "Crossing",
    Flag = "neko_skillcheck_mode",
    Callback = function(value: string)
        if Combat and Combat.SetSkillCheckMode then
            Combat.SetSkillCheckMode(value)
            NekoConfig:Save()
        end
    end
})

local VaultSection = CombatTab:Section({ Title = "Fast Vault" })
VaultSection:Toggle({
    Title = "Fast Vault",
    Desc = "Replace vault animation with faster one",
    Value = false,
    Flag = "neko_vault",
    Callback = function(value: boolean)
        if Combat and Combat.SetFastVault then
            Combat.SetFastVault(value)
            NekoConfig:Save()
        end
    end
})

VaultSection:Slider({
    Title = "Animation Speed",
    Value = { Min = 1.0, Max = 5.0, Default = 1.2 },
    Flag = "neko_vault_speed",
    Callback = function(value: number)
        local stepped = math.round(value * 10) / 10
        if Combat and Combat.SetFastVaultSpeed then
            Combat.SetFastVaultSpeed(stepped)
            NekoConfig:Save()
        end
    end
})

-- Visual Tab (ESP Settings)
local ESPSection = VisualTab:Section({ Title = "ESP Settings" })
ESPSection:Toggle({
    Title = "ESP",
    Desc = "Enable ESP visuals",
    Value = false,
    Flag = "neko_esp",
    Callback = function(value: boolean)
        if ESP and ESP.SetMasterEnabled then
            ESP.SetMasterEnabled(value)
            NekoConfig:Save()
        end
    end
})

ESPSection:Dropdown({
    Title = "Select Esp",
    Desc = "Choose which ESP elements to display",
    Values = { "Player", "Generator", "Pallet", "Window", "Hook", "Zombie" },
    Value = {},
    Multi = true,
    Flag = "neko_esp_select",
    Callback = function(values: { string })
        if ESP and ESP.SetSelectedKinds then
            ESP.SetSelectedKinds(values)
            NekoConfig:Save()
        end
    end
})

ESPSection:Toggle({
    Title = "Show Distance",
    Desc = "Show distance on ESP labels",
    Value = true,
    Flag = "neko_esp_distance",
    Callback = function(value: boolean)
        if ESP and ESP.SetShowDistance then
            ESP.SetShowDistance(value)
            NekoConfig:Save()
        end
    end
})

ESPSection:Toggle({
    Title = "Show Name",
    Desc = "Show name on ESP labels",
    Value = true,
    Flag = "neko_esp_name",
    Callback = function(value: boolean)
        if ESP and ESP.SetShowName then
            ESP.SetShowName(value)
            NekoConfig:Save()
        end
    end
})

ESPSection:Toggle({
    Title = "Show Generator Percent",
    Desc = "Show repair progress on generator ESP",
    Value = true,
    Flag = "neko_esp_genpct",
    Callback = function(value: boolean)
        if ESP and ESP.SetShowGenPercent then
            ESP.SetShowGenPercent(value)
            NekoConfig:Save()
        end
    end
})

ESPSection:Toggle({
    Title = "Show Done Generator",
    Desc = "Show generator ESP when fully repaired (100%)",
    Value = true,
    Flag = "neko_esp_showdone",
    Callback = function(value: boolean)
        if ESP and ESP.SetShowDoneGen then
            ESP.SetShowDoneGen(value)
            NekoConfig:Save()
        end
    end
})

ESPSection:Toggle({
    Title = "Player State",
    Desc = "Change color and show state for downed players",
    Value = false,
    Flag = "neko_esp_playerstate",
    Callback = function(value: boolean)
        if ESP and ESP.SetPlayerState then
            ESP.SetPlayerState(value)
            NekoConfig:Save()
        end
    end
})

local ESPColorSection = VisualTab:Section({ Title = "ESP Colors" })

ESPColorSection:Colorpicker({
    Title = "Generator Color",
    Default = Color3.fromRGB(255, 170, 0),
    Flag = "neko_color_generator",
    Callback = function(value: Color3)
        if ESP and ESP.SetColor then
            ESP.SetColor("Generator", value)
            NekoConfig:Save()
        end
    end
})

ESPColorSection:Colorpicker({
    Title = "Pallet Color",
    Default = Color3.fromRGB(255, 215, 0),
    Flag = "neko_color_pallet",
    Callback = function(value: Color3)
        if ESP and ESP.SetColor then
            ESP.SetColor("Pallet", value)
            NekoConfig:Save()
        end
    end
})

ESPColorSection:Colorpicker({
    Title = "Window Color",
    Default = Color3.fromRGB(74, 255, 181),
    Flag = "neko_color_window",
    Callback = function(value: Color3)
        if ESP and ESP.SetColor then
            ESP.SetColor("Window", value)
            NekoConfig:Save()
        end
    end
})

ESPColorSection:Colorpicker({
    Title = "Hook Color",
    Default = Color3.fromRGB(170, 92, 255),
    Flag = "neko_color_hook",
    Callback = function(value: Color3)
        if ESP and ESP.SetColor then
            ESP.SetColor("Hook", value)
            NekoConfig:Save()
        end
    end
})

ESPColorSection:Colorpicker({
    Title = "Zombie Color",
    Default = Color3.fromRGB(255, 60, 60),
    Flag = "neko_color_zombie",
    Callback = function(value: Color3)
        if ESP and ESP.SetColor then
            ESP.SetColor("SCP", value)
            NekoConfig:Save()
        end
    end
})

ESPColorSection:Colorpicker({
    Title = "Player Color",
    Default = Color3.fromRGB(0, 255, 170),
    Flag = "neko_color_player",
    Callback = function(value: Color3)
        if ESP and ESP.SetColor then
            ESP.SetColor("Player", value)
            NekoConfig:Save()
        end
    end
})

ESPColorSection:Colorpicker({
    Title = "Downed Player Color",
    Default = Color3.fromRGB(255, 0, 0),
    Flag = "neko_color_downed",
    Callback = function(value: Color3)
        if ESP and ESP.SetColor then
            ESP.SetColor("PlayerDowned", value)
            NekoConfig:Save()
        end
    end
})

-- Aim Tab (Aim Gun Settings)
local AimSection = AimTab:Section({ Title = "Aim Gun Settings" })

AimSection:Dropdown({
    Title = "Aim Gun",
    Desc = "Select Aim Gun mode",
    Values = { "Disabled", "Silent Aim", "Aim Lock", "Both" },
    Value = "Both",
    Flag = "neko_aimgun",
    Callback = function(value: string)
        if Aim then
            if value == "Disabled" then
                Aim.SetSilentAim(false)
                Aim.SetAimLock(false)
            elseif value == "Silent Aim" then
                Aim.SetSilentAim(true)
                Aim.SetAimLock(false)
            elseif value == "Aim Lock" then
                Aim.SetSilentAim(false)
                Aim.SetAimLock(true)
            elseif value == "Both" then
                Aim.SetSilentAim(true)
                Aim.SetAimLock(true)
            end
            NekoConfig:Save()
        end
    end
})

AimSection:Dropdown({
    Title = "Aim Target",
    Desc = "Target team selection",
    Values = { "Killer", "Survivor" },
    Value = "Killer",
    Flag = "neko_aim_target",
    Callback = function(value: string)
        if Aim and Aim.SetTargetMode then
            Aim.SetTargetMode(value)
            NekoConfig:Save()
        end
    end
})

AimSection:Toggle({
    Title = "Show FOV",
    Desc = "Show FOV circle",
    Value = false,
    Flag = "neko_aim_showfov",
    Callback = function(value: boolean)
        if Aim and Aim.SetShowFov then
            Aim.SetShowFov(value)
            NekoConfig:Save()
        end
    end
})

AimSection:Slider({
    Title = "FOV Radius",
    Value = { Min = 30, Max = 300, Default = 120 },
    Flag = "neko_aim_fov",
    Callback = function(value: number)
        if Aim and Aim.SetFovRadius then
            Aim.SetFovRadius(value)
            NekoConfig:Save()
        end
    end
})

AimSection:Toggle({
    Title = "Wallcheck",
    Desc = "Aim only at visible targets",
    Value = true,
    Flag = "neko_aim_wallcheck",
    Callback = function(value: boolean)
        if Aim and Aim.SetWallcheck then
            Aim.SetWallcheck(value)
            NekoConfig:Save()
        end
    end
})

AimSection:Toggle({
    Title = "Predict Movement",
    Desc = "Predict target movement trajectory",
    Value = true,
    Flag = "neko_aim_predict",
    Callback = function(value: boolean)
        if Aim and Aim.SetEnableLead then
            Aim.SetEnableLead(value)
            NekoConfig:Save()
        end
    end
})

AimSection:Slider({
    Title = "Aim Smooth",
    Value = { Min = 0.05, Max = 1.0, Default = 0.25 },
    Flag = "neko_aim_smooth",
    Callback = function(value: number)
        if Aim and Aim.SetSmooth then
            Aim.SetSmooth(value)
            NekoConfig:Save()
        end
    end
})

-- Aim Veil Settings
local AimVeilSection = AimTab:Section({ Title = "Aim Veil Settings" })

AimVeilSection:Dropdown({
    Title = "Aim Veil",
    Desc = "Select Aim Veil mode",
    Values = { "Disabled", "Silent Aim", "Aim Lock", "Both" },
    Value = "Both",
    Flag = "neko_aimveil",
    Callback = function(value: string)
        if Aim then
            if value == "Disabled" then
                Aim.SetVeilSilentAim(false)
                Aim.SetVeilAimLock(false)
            elseif value == "Silent Aim" then
                Aim.SetVeilSilentAim(true)
                Aim.SetVeilAimLock(false)
            elseif value == "Aim Lock" then
                Aim.SetVeilSilentAim(false)
                Aim.SetVeilAimLock(true)
            elseif value == "Both" then
                Aim.SetVeilSilentAim(true)
                Aim.SetVeilAimLock(true)
            end
            NekoConfig:Save()
        end
    end
})

AimVeilSection:Toggle({
    Title = "Show FOV (Veil)",
    Desc = "Show FOV circle for Veil",
    Value = false,
    Flag = "neko_aimveil_showfov",
    Callback = function(value: boolean)
        if Aim and Aim.SetVeilShowFov then
            Aim.SetVeilShowFov(value)
            NekoConfig:Save()
        end
    end
})

AimVeilSection:Slider({
    Title = "FOV Radius (Veil)",
    Value = { Min = 50, Max = 400, Default = 150 },
    Flag = "neko_aimveil_fov",
    Callback = function(value: number)
        if Aim and Aim.SetVeilFovRadius then
            Aim.SetVeilFovRadius(value)
            NekoConfig:Save()
        end
    end
})

AimVeilSection:Toggle({
    Title = "Predict Movement (Veil)",
    Desc = "Predict target movement trajectory for Veil",
    Value = true,
    Flag = "neko_aimveil_predict",
    Callback = function(value: boolean)
        if Aim and Aim.SetVeilEnableLead then
            Aim.SetVeilEnableLead(value)
            NekoConfig:Save()
        end
    end
})

-- Player Tab Sections
local PlayerSection = PlayerTab:Section({ Title = "Camera Settings" })

PlayerSection:Toggle({
    Title = "Unlimited Zoom",
    Desc = "Unlock camera zoom distance",
    Value = false,
    Flag = "neko_player_zoom",
    Callback = function(value: boolean)
        if Player and Player.SetUnlimitedZoom then
            Player.SetUnlimitedZoom(value)
            NekoConfig:Save()
        end
    end
})

PlayerSection:Slider({
    Title = "Max Zoom Distance",
    Value = { Min = 100, Max = 5000, Default = 1000 },
    Flag = "neko_player_zoomdist",
    Callback = function(value: number)
        if Player and Player.SetMaxZoomDistance then
            Player.SetMaxZoomDistance(value)
            NekoConfig:Save()
        end
    end
})

PlayerSection:Toggle({
    Title = "Custom FOV",
    Desc = "Override default field of view",
    Value = false,
    Flag = "neko_player_fov",
    Callback = function(value: boolean)
        if Player and Player.SetCustomFOV then
            Player.SetCustomFOV(value)
            NekoConfig:Save()
        end
    end
})

PlayerSection:Slider({
    Title = "Camera FOV",
    Value = { Min = 40, Max = 120, Default = 70 },
    Flag = "neko_player_fovval",
    Callback = function(value: number)
        if Player and Player.SetFOV then
            Player.SetFOV(value)
            NekoConfig:Save()
        end
    end
})

-- Theme Tab (Dropdown selection)
local themes = {}
for name in pairs(WindUI:GetThemes()) do
    table.insert(themes, name)
end
table.sort(themes)

ThemeTab:Dropdown({
    Title = "Theme",
    Values = themes,
    Value = "NekoTheme",
    Flag = "neko_theme",
    Callback = function(value: string)
        WindUI:SetTheme(value)
        NekoConfig:Save()
    end
})

-- Load saved config
NekoConfig:Load()
