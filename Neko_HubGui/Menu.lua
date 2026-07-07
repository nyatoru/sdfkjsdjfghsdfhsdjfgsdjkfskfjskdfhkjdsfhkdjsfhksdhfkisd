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
    Callback = function(value: boolean)
        if Combat and Combat.SetAutoParry then
            Combat.SetAutoParry(value)
        end
    end
})

ParrySection:Slider({
    Title = "Parry Distance",
    Value = { Min = 5, Max = 25, Default = 9 },
    Callback = function(value: number)
        if Combat and Combat.SetParryDistance then
            Combat.SetParryDistance(value)
        end
    end
})

ParrySection:Slider({
    Title = "Dash Parry Distance",
    Value = { Min = 20, Max = 50, Default = 30 },
    Callback = function(value: number)
        if Combat and Combat.SetDashParryDistance then
            Combat.SetDashParryDistance(value)
        end
    end
})

local DodgeSection = CombatTab:Section({ Title = "Auto Dodge Settings" })
DodgeSection:Toggle({
    Title = "Auto Dodge (Abysswalker)",
    Desc = "Automatically dodge Abysswalker skills",
    Value = false,
    Callback = function(value: boolean)
        if Combat and Combat.SetAutoDodgeAbyss then
            Combat.SetAutoDodgeAbyss(value)
        end
    end
})

DodgeSection:Slider({
    Title = "Dodge Distance",
    Value = { Min = 15, Max = 35, Default = 25 },
    Callback = function(value: number)
        if Combat and Combat.SetDodgeDistance then
            Combat.SetDodgeDistance(value)
        end
    end
})

local PalletSection = CombatTab:Section({ Title = "Auto Drop Pallet Settings" })
PalletSection:Toggle({
    Title = "Auto Drop Pallet",
    Desc = "Automatically drop nearby pallets when killer is close",
    Value = false,
    Callback = function(value: boolean)
        if Combat and Combat.SetAutoPallet then
            Combat.SetAutoPallet(value)
        end
    end
})

PalletSection:Slider({
    Title = "Trigger Distance",
    Value = { Min = 5.0, Max = 25.0, Default = 13.2 },
    Callback = function(value: number)
        local stepped = math.round(value * 10) / 10
        if Combat and Combat.SetPalletDistance then
            Combat.SetPalletDistance(stepped)
        end
    end
})

local SkillcheckSection = CombatTab:Section({ Title = "Skillcheck Settings" })
SkillcheckSection:Toggle({
    Title = "Auto Skillcheck",
    Desc = "Automatically hit perfect skillchecks",
    Value = false,
    Callback = function(value: boolean)
        if Combat and Combat.SetAutoSkillcheck then
            Combat.SetAutoSkillcheck(value)
        end
    end
})

-- Visual Tab (ESP Settings)
local ESPSection = VisualTab:Section({ Title = "ESP Settings" })
ESPSection:Toggle({
    Title = "ESP",
    Desc = "Enable ESP visuals",
    Value = false,
    Callback = function(value: boolean)
        if ESP and ESP.SetMasterEnabled then
            ESP.SetMasterEnabled(value)
        end
    end
})

ESPSection:Dropdown({
    Title = "Select Esp",
    Desc = "Choose which ESP elements to display",
    Values = { "Player", "Generator", "Pallet", "Window", "Zombie" },
    Value = {},
    Multi = true,
    Callback = function(values: { string })
        if ESP and ESP.SetSelectedKinds then
            ESP.SetSelectedKinds(values)
        end
    end
})

ESPSection:Toggle({
    Title = "Show Distance",
    Desc = "Show distance on ESP labels",
    Value = true,
    Callback = function(value: boolean)
        if ESP and ESP.SetShowDistance then
            ESP.SetShowDistance(value)
        end
    end
})

ESPSection:Toggle({
    Title = "Show Name",
    Desc = "Show name on ESP labels",
    Value = true,
    Callback = function(value: boolean)
        if ESP and ESP.SetShowName then
            ESP.SetShowName(value)
        end
    end
})

ESPSection:Toggle({
    Title = "Show Generator Percent",
    Desc = "Show repair progress on generator ESP",
    Value = true,
    Callback = function(value: boolean)
        if ESP and ESP.SetShowGenPercent then
            ESP.SetShowGenPercent(value)
        end
    end
})

ESPSection:Toggle({
    Title = "Hide Done Generator",
    Desc = "Hide generator ESP when fully repaired (100%)",
    Value = false,
    Callback = function(value: boolean)
        if ESP and ESP.SetHideDoneGen then
            ESP.SetHideDoneGen(value)
        end
    end
})

ESPSection:Toggle({
    Title = "Player State",
    Desc = "Change color and show state for downed players",
    Value = false,
    Callback = function(value: boolean)
        if ESP and ESP.SetPlayerState then
            ESP.SetPlayerState(value)
        end
    end
})

local ESPColorSection = VisualTab:Section({ Title = "ESP Colors" })

ESPColorSection:Colorpicker({
    Title = "Generator Color",
    Default = Color3.fromRGB(255, 170, 0),
    Callback = function(value: Color3)
        if ESP and ESP.SetColor then
            ESP.SetColor("Generator", value)
        end
    end
})

ESPColorSection:Colorpicker({
    Title = "Pallet Color",
    Default = Color3.fromRGB(255, 215, 0),
    Callback = function(value: Color3)
        if ESP and ESP.SetColor then
            ESP.SetColor("Pallet", value)
        end
    end
})

ESPColorSection:Colorpicker({
    Title = "Window Color",
    Default = Color3.fromRGB(74, 255, 181),
    Callback = function(value: Color3)
        if ESP and ESP.SetColor then
            ESP.SetColor("Window", value)
        end
    end
})

ESPColorSection:Colorpicker({
    Title = "Zombie Color",
    Default = Color3.fromRGB(255, 60, 60),
    Callback = function(value: Color3)
        if ESP and ESP.SetColor then
            ESP.SetColor("SCP", value)
        end
    end
})

ESPColorSection:Colorpicker({
    Title = "Player Color",
    Default = Color3.fromRGB(0, 255, 170),
    Callback = function(value: Color3)
        if ESP and ESP.SetColor then
            ESP.SetColor("Player", value)
        end
    end
})

ESPColorSection:Colorpicker({
    Title = "Downed Player Color",
    Default = Color3.fromRGB(255, 0, 0),
    Callback = function(value: Color3)
        if ESP and ESP.SetColor then
            ESP.SetColor("PlayerDowned", value)
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
        end
    end
})

local aimGunActive = true
local aimGunButton = AimSection:Button({
    Title = "Aim Gun: ON",
    Desc = "Click to toggle aim gun on/off",
    Icon = "crosshair",
    IconAlign = "Left",
    Color = Color3.fromRGB(0, 200, 0),
    Callback = function()
        aimGunActive = not aimGunActive
        if aimGunActive then
            Aim.SetSilentAim(true)
            Aim.SetAimLock(true)
            aimGunButton:SetTitle("Aim Gun: ON")
            aimGunButton:SetDesc("Click to toggle aim gun on/off")
        else
            Aim.SetSilentAim(false)
            Aim.SetAimLock(false)
            aimGunButton:SetTitle("Aim Gun: OFF")
            aimGunButton:SetDesc("Click to toggle aim gun on/off")
        end
    end
})

AimSection:Dropdown({
    Title = "Aim Target",
    Desc = "Target team selection",
    Values = { "Killer", "Survivor" },
    Value = "Killer",
    Callback = function(value: string)
        if Aim and Aim.SetTargetMode then
            Aim.SetTargetMode(value)
        end
    end
})

AimSection:Toggle({
    Title = "Show FOV",
    Desc = "Show FOV circle",
    Value = false,
    Callback = function(value: boolean)
        if Aim and Aim.SetShowFov then
            Aim.SetShowFov(value)
        end
    end
})

AimSection:Slider({
    Title = "FOV Radius",
    Value = { Min = 30, Max = 300, Default = 120 },
    Callback = function(value: number)
        if Aim and Aim.SetFovRadius then
            Aim.SetFovRadius(value)
        end
    end
})

AimSection:Toggle({
    Title = "Wallcheck",
    Desc = "Aim only at visible targets",
    Value = true,
    Callback = function(value: boolean)
        if Aim and Aim.SetWallcheck then
            Aim.SetWallcheck(value)
        end
    end
})

AimSection:Toggle({
    Title = "Predict Movement",
    Desc = "Predict target movement trajectory",
    Value = true,
    Callback = function(value: boolean)
        if Aim and Aim.SetEnableLead then
            Aim.SetEnableLead(value)
        end
    end
})

AimSection:Slider({
    Title = "Aim Smooth",
    Value = { Min = 0.05, Max = 1.0, Default = 0.25 },
    Callback = function(value: number)
        if Aim and Aim.SetSmooth then
            Aim.SetSmooth(value)
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
        end
    end
})

local aimVeilActive = true
local aimVeilButton = AimVeilSection:Button({
    Title = "Aim Veil: ON",
    Desc = "Click to toggle aim veil on/off",
    Icon = "crosshair",
    IconAlign = "Left",
    Color = Color3.fromRGB(0, 200, 0),
    Callback = function()
        aimVeilActive = not aimVeilActive
        if aimVeilActive then
            Aim.SetVeilSilentAim(true)
            Aim.SetVeilAimLock(true)
            aimVeilButton:SetTitle("Aim Veil: ON")
            aimVeilButton:SetDesc("Click to toggle aim veil on/off")
        else
            Aim.SetVeilSilentAim(false)
            Aim.SetVeilAimLock(false)
            aimVeilButton:SetTitle("Aim Veil: OFF")
            aimVeilButton:SetDesc("Click to toggle aim veil on/off")
        end
    end
})

AimVeilSection:Toggle({
    Title = "Show FOV (Veil)",
    Desc = "Show FOV circle for Veil",
    Value = false,
    Callback = function(value: boolean)
        if Aim and Aim.SetVeilShowFov then
            Aim.SetVeilShowFov(value)
        end
    end
})

AimVeilSection:Slider({
    Title = "FOV Radius (Veil)",
    Value = { Min = 50, Max = 400, Default = 150 },
    Callback = function(value: number)
        if Aim and Aim.SetVeilFovRadius then
            Aim.SetVeilFovRadius(value)
        end
    end
})

AimVeilSection:Toggle({
    Title = "Predict Movement (Veil)",
    Desc = "Predict target movement trajectory for Veil",
    Value = true,
    Callback = function(value: boolean)
        if Aim and Aim.SetVeilEnableLead then
            Aim.SetVeilEnableLead(value)
        end
    end
})

-- Player Tab Sections
local PlayerSection = PlayerTab:Section({ Title = "Camera Settings" })

PlayerSection:Toggle({
    Title = "Unlimited Zoom",
    Desc = "Unlock camera zoom distance",
    Value = false,
    Callback = function(value: boolean)
        if Player and Player.SetUnlimitedZoom then
            Player.SetUnlimitedZoom(value)
        end
    end
})

PlayerSection:Slider({
    Title = "Max Zoom Distance",
    Value = { Min = 100, Max = 5000, Default = 1000 },
    Callback = function(value: number)
        if Player and Player.SetMaxZoomDistance then
            Player.SetMaxZoomDistance(value)
        end
    end
})

PlayerSection:Toggle({
    Title = "Custom FOV",
    Desc = "Override default field of view",
    Value = false,
    Callback = function(value: boolean)
        if Player and Player.SetCustomFOV then
            Player.SetCustomFOV(value)
        end
    end
})

PlayerSection:Slider({
    Title = "Camera FOV",
    Value = { Min = 40, Max = 120, Default = 70 },
    Callback = function(value: number)
        if Player and Player.SetFOV then
            Player.SetFOV(value)
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
    Callback = function(value: string)
        WindUI:SetTheme(value)
    end
})
