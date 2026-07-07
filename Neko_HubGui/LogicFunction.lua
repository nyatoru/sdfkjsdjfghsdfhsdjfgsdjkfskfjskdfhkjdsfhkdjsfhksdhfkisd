--!strict

-- Services
local Players          = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local RunService        = game:GetService("RunService")
local UserInputService  = game:GetService("UserInputService")
local Teams             = game:GetService("Teams")
local Workspace         = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer

-- Clean up any standalone UI if present
pcall(function()
    local cg = (gethui and gethui()) or game:GetService("CoreGui")
    local oldParry = cg:FindFirstChild("Neko_Hub_AutoParry")
    if oldParry then oldParry:Destroy() end
    local oldESP = cg:FindFirstChild("Neko_Hub_ESP")
    if oldESP then oldESP:Destroy() end
end)

-- =====================================================================
-- COMBAT MODULE (Auto Parry, Dash Parry, Auto Dodge Abyss)
-- =====================================================================

local Character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
local Humanoid  = Character:WaitForChild("Humanoid")
local RootPart  = Character:WaitForChild("HumanoidRootPart")

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local parryResult = Remotes:WaitForChild("Items"):WaitForChild("Parrying Dagger"):WaitForChild("parryResult")
local DamagevizEvent = Remotes:WaitForChild("Killers"):WaitForChild("Damageviz")
local SlowAttack = Remotes:WaitForChild("Killers"):FindFirstChild("SlowAttack")
local KillerTeam = Teams:FindFirstChild("Killer")

local killerDistance = 999
local killerRoot: BasePart? = nil
local killerFilterCache: { Instance } = { Character }

LocalPlayer.CharacterAdded:Connect(function(newChar)
    Character = newChar
    Humanoid = newChar:WaitForChild("Humanoid") :: Humanoid
    RootPart = newChar:WaitForChild("HumanoidRootPart") :: BasePart
end)

-- State Toggles & Distances
local autoParryEnabled = false
local parryDistance = 9
local dashDistance = 30

local autoDodgeEnabled = false
local dodgeDistance = 25

-- Optimized Heartbeat for Killer Tracking (Only runs when Combat features are active)
RunService.Heartbeat:Connect(function()
    if not autoParryEnabled and not autoDodgeEnabled then return end
    if not RootPart or not RootPart.Parent then return end
    
    local nearest = 9999
    local nearestRoot: BasePart? = nil
    
    table.clear(killerFilterCache)
    table.insert(killerFilterCache, Character)
    
    if KillerTeam then
        for _, plr in ipairs(KillerTeam:GetPlayers()) do
            local kChar = plr.Character
            if kChar then
                table.insert(killerFilterCache, kChar)
                local kRoot = kChar:FindFirstChild("HumanoidRootPart") :: BasePart?
                if kRoot then
                    local d = (RootPart.Position - kRoot.Position).Magnitude
                    if d < nearest then
                        nearest = d
                        nearestRoot = kRoot
                    end
                end
            end
        end
    end
    
    killerDistance = nearest
    killerRoot = nearestRoot
end)

-- Optimized RaycastParams instance (reused to prevent GC overhead)
local raycastParams = RaycastParams.new()
raycastParams.FilterType = Enum.RaycastFilterType.Exclude
raycastParams.IgnoreWater = true

local function hasLineOfSight(): boolean
    if not RootPart or not RootPart.Parent or not killerRoot or not killerRoot.Parent then return false end
    raycastParams.FilterDescendantsInstances = killerFilterCache
    local rayResult = Workspace:Raycast(RootPart.Position, killerRoot.Position - RootPart.Position, raycastParams)
    return rayResult == nil
end

-- Animation Event Hooks
local animHandlers: { (plr: Player, idRaw: any, animId: string) -> () } = {}
local killerAnimConnections: { RBXScriptConnection } = {}

local function onKillerAnim(fn: (plr: Player, idRaw: any, animId: string) -> ())
    table.insert(animHandlers, fn)
end

local function fireAnim(plr: Player, idRaw: any, animId: string)
    for _, h in ipairs(animHandlers) do
        pcall(h, plr, idRaw, animId)
    end
end

local function hookKillerAnimators()
    for _, c in ipairs(killerAnimConnections) do pcall(function() c:Disconnect() end) end
    table.clear(killerAnimConnections)
    if not KillerTeam then return end
    
    for _, plr in ipairs(KillerTeam:GetPlayers()) do
        local function hook(char: Model)
            local hum = char:WaitForChild("Humanoid", 5) :: Humanoid?
            if hum then
                local animator = hum:WaitForChild("Animator", 5) :: Animator?
                if animator then
                    table.insert(killerAnimConnections, animator.AnimationPlayed:Connect(function(animTrack)
                        local id = animTrack.Animation and animTrack.Animation.AnimationId
                        local animId = id and tostring(id):match("%d+") or ""
                        fireAnim(plr, id, animId)
                    end))
                end
            end
        end
        if plr.Character then task.spawn(hook, plr.Character) end
        table.insert(killerAnimConnections, plr.CharacterAdded:Connect(hook))
    end
end

-- Auto Parry Mechanics
local isOnCooldown, isResolving, isSilenced, isAutoParrying = false, false, false, false
local ATTACK_ANIM_IDS: { [string]: boolean } = {
    ["117042998468241"] = true, ["129784271201071"] = true, ["113255068724446"] = true,
    ["118907603246885"] = true, ["122812055447896"] = true, ["110355011987939"] = true,
    ["135002183282873"] = true, ["105374834496520"] = true, ["138720291317243"] = true,
    ["115244153053858"] = true, ["106871536134254"] = true,
}
local lastPrePress, rearmCooldown, postParryCooldown, lastAutoPress = 0, 0.08, 0.25, 0
local facingDotThreshold = 0.1

local function canParry(): boolean
    if isOnCooldown or isSilenced or LocalPlayer:GetAttribute("IsDead") then return false end
    if not Character or not Character.Parent or Character:GetAttribute("IsCarried") or Character:GetAttribute("IsHooked") then return false end
    if CollectionService:HasTag(RootPart, "doing action") then return false end
    return true
end

local function cleanupStaleActionTag()
    if not RootPart or not RootPart.Parent then return end
    if CollectionService:HasTag(RootPart, "doing action") then
        local checkInt = Character and Character:FindFirstChild("CheckInterractable")
        if not checkInt or not checkInt:GetAttribute("isRepairing") then
            CollectionService:RemoveTag(RootPart, "doing action")
            if RootPart.Anchored then RootPart.Anchored = false end
            isResolving, isOnCooldown = false, false
        end
    end
end

local function isKillerFacing(): boolean
    if not killerRoot or not killerRoot.Parent or not RootPart or not RootPart.Parent then return true end
    local dot = killerRoot.CFrame.LookVector:Dot((RootPart.Position - killerRoot.Position).Unit)
    return dot >= facingDotThreshold
end

local parryController: any = nil
local function resolveParryController(): any
    if parryController then return parryController end
    -- Match instance by its exact class metatable (ParryClient), same as the
    -- working standalone script. The old loose duck-typing scan grabbed the
    -- first table with .Parry/.CanUse (usually the class module/prototype),
    -- so :Parry() ran without instance state and silently did nothing.
    local ok, ParryClient = pcall(function()
        return require(ReplicatedStorage.Modules.Items.ParryClient)
    end)
    if not ok or not ParryClient then return nil end
    if type(getgc) ~= "function" then return nil end

    for _, v in ipairs(getgc(true)) do
        if type(v) == "table" and getmetatable(v) == ParryClient then
            parryController = v
            break
        end
    end

    return parryController
end

local function doParryPress()
    isAutoParrying = true
    lastAutoPress = os.clock()
    lastPrePress = os.clock()
    local ctrl = resolveParryController()
    if ctrl then
        local ok, err = pcall(function()
            if ctrl:CanUse() then ctrl:Parry() end
        end)
        if not ok then parryController = nil end
    else
        warn("[Neko_Hub Debug] Controller is nil!")
    end
    task.delay(0.05, function() isAutoParrying = false end)
end

local function attemptParry(maxRange: number)
    if not autoParryEnabled then warn("[Neko_Hub Debug] AutoParry disabled") return end
    if killerDistance > maxRange then warn("[Neko_Hub Debug] Out of range:", killerDistance, ">", maxRange) return end
    if not canParry() then warn("[Neko_Hub Debug] canParry() is false. CD:", isOnCooldown, "Silenced:", isSilenced) return end
    if (os.clock() - lastPrePress) < rearmCooldown then warn("[Neko_Hub Debug] Rearm cooldown active") return end
    if not hasLineOfSight() then warn("[Neko_Hub Debug] No line of sight") return end
    if not isKillerFacing() then warn("[Neko_Hub Debug] Killer not facing") return end
    
    warn("[Neko_Hub Debug] attemptParry PASSED ALL CHECKS, calling doParryPress()")
    doParryPress()
end

local function triggerParry()
    attemptParry(parryDistance)
end

DamagevizEvent.OnClientEvent:Connect(triggerParry)
if SlowAttack then SlowAttack.OnClientEvent:Connect(triggerParry) end

onKillerAnim(function(plr, idRaw, animId)
    if ATTACK_ANIM_IDS[animId] then triggerParry() end
end)

parryResult.OnClientEvent:Connect(function(success, cd)
    isResolving = false
    if success then
        isOnCooldown = true
        task.delay(postParryCooldown, function() isOnCooldown = false end)
    end
end)

UserInputService.InputBegan:Connect(function(input, gp)
    if not gp and input.UserInputType == Enum.UserInputType.MouseButton2 then
        if isAutoParrying or (os.clock() - lastAutoPress) < 0.2 then return end
        if canParry() then isResolving = true end
    end
end)

CollectionService:GetInstanceAddedSignal("Silenced"):Connect(function(i) if i == Character then isSilenced = true end end)
CollectionService:GetInstanceRemovedSignal("Silenced"):Connect(function(i) if i == Character then isSilenced = false end end)
LocalPlayer.CharacterAdded:Connect(function() isOnCooldown, isResolving, isSilenced, parryController = false, false, false, nil end)

if KillerTeam then
    hookKillerAnimators()
    KillerTeam.PlayerAdded:Connect(hookKillerAnimators)
    KillerTeam.PlayerRemoved:Connect(hookKillerAnimators)
end

RunService.Heartbeat:Connect(function()
    if autoParryEnabled and RootPart and CollectionService:HasTag(RootPart, "doing action") then
        cleanupStaleActionTag()
    end
end)

-- Dash Parry (Hidden)
local DASH_WINDUP_ID = "98163597193511"
local dashParryDelay = 0.775
local dashFacingDotMin = math.cos(math.rad(10))
local dashRetriggerGuard = 1.4
local dashPending = false
local lastDashSchedule = -999

local function dashFacingInfo(kr: BasePart?): (number, boolean)
    if not kr or not kr.Parent or not RootPart or not RootPart.Parent then return 999, false end
    local toPlayer = RootPart.Position - kr.Position
    local dist = toPlayer.Magnitude
    if dist < 0.01 then return dist, true end
    local dot = math.clamp(kr.CFrame.LookVector:Dot(toPlayer.Unit), -1, 1)
    return dist, (dot >= dashFacingDotMin)
end

local function fireDashParry(getKr: () -> BasePart?)
    dashPending = false
    if not autoParryEnabled then return end
    local kr = getKr()
    local dist, facingOk = dashFacingInfo(kr)
    if dist > dashDistance or not facingOk then return end
    if not canParry() or not hasLineOfSight() then return end
    doParryPress()
end

local function scheduleDashParry(plr: Player, kr: BasePart?)
    if not autoParryEnabled or dashPending or (os.clock() - lastDashSchedule) < dashRetriggerGuard then return end
    local dist, facingOk = dashFacingInfo(kr)
    if dist > dashDistance or not facingOk then return end
    dashPending = true
    lastDashSchedule = os.clock()
    task.delay(dashParryDelay, function()
        fireDashParry(function()
            return plr.Character and (plr.Character:FindFirstChild("HumanoidRootPart") :: BasePart?)
        end)
    end)
end

onKillerAnim(function(plr, idRaw, animId)
    if idRaw and tostring(idRaw):find(DASH_WINDUP_ID) then
        scheduleDashParry(plr, plr.Character and (plr.Character:FindFirstChild("HumanoidRootPart") :: BasePart?))
    end
end)

-- Auto Dodge Abysswalker
local crouchHoldTime = 1.0
local dodgeTriggerDelay = 0.1
local dodgeSkillWindow = 2.0
local dodgeCheckInterval = 0.1
local ABYSS_SKILL_ID = "80411309607666"
local isDodging = false
local dodgeSkillPending = false

local crouchController: any = nil
local function resolveCrouchController(): any
    if crouchController then return crouchController end
    local ok, SAC = pcall(function()
        return require(ReplicatedStorage.Modules.Survivors.SurvivorAnimationsController)
    end)
    if not ok or not SAC then return nil end
    if type(getgc) ~= "function" then return nil end
    for _, v in ipairs(getgc(true)) do
        if type(v) == "table" and getmetatable(v) == SAC then
            crouchController = v
            break
        end
    end
    return crouchController
end

local function setCrouch(state: boolean): boolean
    local ctrl = resolveCrouchController()
    if not ctrl then return false end
    local ok = pcall(function() ctrl:_setCrouching(state) end)
    if not ok then crouchController = nil end
    return ok
end

local function doCrouch()
    if isDodging then return end
    isDodging = true
    setCrouch(true)
    task.delay(crouchHoldTime, function()
        setCrouch(false)
        isDodging = false
    end)
end

LocalPlayer.CharacterAdded:Connect(function() crouchController = nil isDodging = false end)

local function triggerDodge()
    if not autoDodgeEnabled or isDodging then return end
    if killerDistance <= dodgeDistance and hasLineOfSight() then
        task.delay(dodgeTriggerDelay, function()
            if not isDodging and not dodgeSkillPending and killerDistance <= dodgeDistance and hasLineOfSight() then
                doCrouch()
            end
        end)
        return
    end
    if dodgeSkillPending then return end
    dodgeSkillPending = true
    task.spawn(function()
        local elapsed = 0
        while elapsed < dodgeSkillWindow do
            task.wait(dodgeCheckInterval)
            elapsed = elapsed + dodgeCheckInterval
            if not autoDodgeEnabled or isDodging then break end
            if killerDistance <= dodgeDistance and hasLineOfSight() then
                task.delay(dodgeTriggerDelay, function()
                    if not isDodging and not dodgeSkillPending and killerDistance <= dodgeDistance and hasLineOfSight() then
                        doCrouch()
                    end
                end)
                break
            end
        end
        dodgeSkillPending = false
    end)
end

onKillerAnim(function(plr, idRaw, animId)
    if idRaw and tostring(idRaw):find(ABYSS_SKILL_ID) then triggerDodge() end
end)

if KillerTeam then
    hookKillerAnimators()
    KillerTeam.PlayerAdded:Connect(hookKillerAnimators)
    KillerTeam.PlayerRemoved:Connect(hookKillerAnimators)
end


-- =====================================================================
-- AUTO SKILLCHECK MODULE
-- =====================================================================
local autoSkillcheckEnabled = false
local scBusy = false

local CONFIG_SC = {
    zoneMin      = 102,
    zoneMax      = 116,
}

local function pressSpace()
    local VIM = game:GetService("VirtualInputManager")
    VIM:SendKeyEvent(true, Enum.KeyCode.Space, false, game)
    task.wait()
    VIM:SendKeyEvent(false, Enum.KeyCode.Space, false, game)
end

local TOUCH_ID = 8822
local ActionPath = "Survivor-mob.Controls.action.check"

local function GetActionTarget()
    local current = LocalPlayer:FindFirstChild("PlayerGui")
    for segment in string.gmatch(ActionPath, "[^%.]+") do
        current = current and current:FindFirstChild(segment)
    end
    return current
end

local function triggerMobileButton()
    local b = GetActionTarget()
    if b and b:IsA("GuiObject") then
        local p, s, i = b.AbsolutePosition, b.AbsoluteSize, game:GetService("GuiService"):GetGuiInset()
        local cx, cy = p.X + (s.X/2) + i.X, p.Y + (s.Y/2) + i.Y
        pcall(function()
            local VIM = game:GetService("VirtualInputManager")
            VIM:SendTouchEvent(TOUCH_ID, 0, cx, cy)
            task.wait()
            VIM:SendTouchEvent(TOUCH_ID, 2, cx, cy)
        end)
    end
end

RunService.RenderStepped:Connect(function()
    if not autoSkillcheckEnabled or scBusy then return end

    local PlayerGui = LocalPlayer:FindFirstChild("PlayerGui")
    local gui = PlayerGui and PlayerGui:FindFirstChild("SkillCheckPromptGui")
    if not gui then return end

    local check = gui:FindFirstChild("Check")
    if not check or not check.Visible then return end

    local line = check:FindFirstChild("Line")
    local goal = check:FindFirstChild("Goal")
    if not line or not goal then return end

    local lr = line.Rotation % 360
    local gr = goal.Rotation % 360

    local startRange = (gr + CONFIG_SC.zoneMin) % 360
    local endRange   = (gr + CONFIG_SC.zoneMax) % 360

    local success =
        (startRange > endRange and (lr >= startRange or lr <= endRange))
        or (lr >= startRange and lr <= endRange)

    if success then
        scBusy = true
        task.spawn(function()
            if game:GetService("UserInputService").TouchEnabled then
                triggerMobileButton()
            else
                pressSpace()
            end
            task.wait(0.01)
            scBusy = false
        end)
    end
end)

-- =====================================================================
-- VISUAL (ESP) MODULE
-- =====================================================================

local COLOR_GEN      = Color3.fromRGB(255, 170, 0)
local COLOR_GEN_DONE = Color3.fromRGB(0, 255, 120)
local COLOR_PALLET   = Color3.fromRGB(255, 215, 0)
local COLOR_WINDOW  = Color3.fromRGB(74, 255, 181)
local COLOR_ZOMBIE  = Color3.fromRGB(255, 60, 60)
local COLOR_PLAYER  = Color3.fromRGB(0, 255, 170)
local COLOR_KILLER  = Color3.fromRGB(255, 60, 60)
local COLOR_OUTLINE = Color3.fromRGB(255, 255, 255)

type ESPKind = "Generator" | "Pallet" | "Window" | "SCP" | "Player"

type TrackedEntry = {
    hl: Highlight?,
    bill: BillboardGui?,
    anchor: BasePart,
    sub: TextLabel?,
    nameL: TextLabel?,
    progConns: { RBXScriptConnection }?,
    wantDist: boolean?,
    kind: ESPKind
}

local ESP = {}

local espMasterEnabled = false
local espShowDistance = true
local espShowName = true
local espShowGenPercent = true
local espPlayerState = false

local COLOR_DOWNED = Color3.fromRGB(255, 0, 0)

local espColors: { [string]: Color3 } = {
    Generator = COLOR_GEN,
    Pallet = COLOR_PALLET,
    Window = COLOR_WINDOW,
    SCP = COLOR_ZOMBIE,
    Player = COLOR_PLAYER,
    PlayerDowned = COLOR_DOWNED,
}

local selectedKinds: { [string]: boolean } = {
    Generator = false,
    Pallet = false,
    Window = false,
    SCP = false,
    Player = false
}

local activeKinds: { [string]: boolean } = {
    Generator = false,
    Pallet = false,
    Window = false,
    SCP = false,
    Player = false
}

local tracked: { [Instance]: TrackedEntry } = {}
local connsByKind: { [string]: { RBXScriptConnection } } = {
    Generator = {},
    Pallet = {},
    Window = {},
    SCP = {},
    Player = {}
}

local distLoopRunning = false

local function isKindActive(kind: string): boolean
    return espMasterEnabled and (selectedKinds[kind] == true)
end

local function pushConn(kind: string, c: RBXScriptConnection)
    local cs = connsByKind[kind]
    if cs then cs[#cs + 1] = c end
end

local function cleanup(model: Instance)
    local t = tracked[model]
    if not t then return end
    if t.progConns then
        for _, c in ipairs(t.progConns) do pcall(function() c:Disconnect() end) end
    end
    if t.hl then pcall(function() t.hl:Destroy() end) end
    if t.bill then pcall(function() t.bill:Destroy() end) end
    tracked[model] = nil
end

local function stopKind(kind: string)
    local cs = connsByKind[kind]
    if cs then
        for _, c in ipairs(cs) do pcall(function() c:Disconnect() end) end
        connsByKind[kind] = {}
    end
    for key, e in pairs(tracked) do
        if e.kind == kind then cleanup(key) end
    end
end

local function mkHighlight(model: Instance, color: Color3): Highlight
    local hl = Instance.new("Highlight")
    hl.Name = "ESP_ObjHL"
    hl.FillColor = color
    hl.OutlineColor = COLOR_OUTLINE
    hl.FillTransparency = 0.5
    hl.OutlineTransparency = 0
    hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    hl.Adornee = model
    hl.Parent = model
    return hl
end

local function mkBillboard(anchor: BasePart, color: Color3, topText: string): (BillboardGui, TextLabel, TextLabel)
    local bill = Instance.new("BillboardGui")
    bill.Name = "ESP_ObjTag"
    bill.Size = UDim2.new(0, 140, 0, 34)
    bill.StudsOffset = Vector3.new(0, 3, 0)
    bill.AlwaysOnTop = true
    bill.LightInfluence = 0
    bill.MaxDistance = 2500
    bill.Adornee = anchor
    bill.Parent = anchor

    local nameLabel = Instance.new("TextLabel")
    nameLabel.Size = UDim2.new(1, 0, 0.55, 0)
    nameLabel.BackgroundTransparency = 1
    nameLabel.TextSize = 13
    nameLabel.Font = Enum.Font.SourceSansBold
    nameLabel.TextColor3 = color
    nameLabel.Text = topText
    nameLabel.TextStrokeTransparency = 0
    nameLabel.Parent = bill

    local subLabel = Instance.new("TextLabel")
    subLabel.Size = UDim2.new(1, 0, 0.45, 0)
    subLabel.Position = UDim2.new(0, 0, 0.55, 0)
    subLabel.BackgroundTransparency = 1
    subLabel.TextSize = 12
    subLabel.Font = Enum.Font.SourceSans
    subLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    subLabel.Text = ""
    subLabel.TextStrokeTransparency = 0
    subLabel.Parent = bill

    return bill, nameLabel, subLabel
end

local function ensureDistLoop()
    if distLoopRunning then return end
    distLoopRunning = true
    task.spawn(function()
        while espMasterEnabled and next(tracked) ~= nil do
            local char = LocalPlayer.Character
            local root = if char then char:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
            if root then
                local rootPos = root.Position

                -- Re-track any untracked players (handles respawn timing)
                if isKindActive("Player") then
                    for _, plr in ipairs(Players:GetPlayers()) do
                        if plr ~= LocalPlayer then
                            local plrChar = plr.Character
                            if plrChar and plrChar.Parent and not tracked[plrChar] then
                                local hum = plrChar:FindFirstChildOfClass("Humanoid")
                                if hum and hum.Health > 0 then
                                    applyPlayer(plrChar, plr)
                                end
                            end
                        end
                    end
                end

                -- Cleanup dead player ESP
                for model, t in pairs(tracked) do
                    if t.kind == "Player" then
                        local hum = model:FindFirstChildOfClass("Humanoid")
                        if not hum or hum.Health <= 0 or not model.Parent then
                            cleanup(model)
                        end
                    end
                end
                for _, t in pairs(tracked) do
                    if t.sub and t.anchor and t.anchor.Parent then
                        if t.kind ~= "Generator" then
                            if t.wantDist and espShowDistance then
                                local dist = math.floor((t.anchor.Position - rootPos).Magnitude)
                                t.sub.Text = string.format("[%dm]", dist)
                            elseif t.wantDist and not espShowDistance then
                                t.sub.Text = ""
                            end
                        end
                    end
                    if t.nameL then
                        t.nameL.Visible = espShowName
                    end
                    -- Player state: check if downed and update color/name
                    if espPlayerState and t.kind == "Player" and t.anchor and t.anchor.Parent then
                        local plrChar = t.anchor:FindFirstAncestorOfClass("Model")
                        if plrChar then
                            local hum = plrChar:FindFirstChildOfClass("Humanoid")
                            local isDowned = false
                            if hum then
                                isDowned = hum.Health <= 0
                                    or hum.Health < 2
                                    or plrChar:GetAttribute("Downed") == true
                                    or plrChar:GetAttribute("IsDown") == true
                                    or plrChar:GetAttribute("Knocked") == true
                            end
                            if isDowned then
                                if t.hl then
                                    t.hl.FillColor = espColors.PlayerDowned
                                    t.hl.OutlineColor = espColors.PlayerDowned
                                end
                                if t.nameL then
                                    local baseName = t.nameL.Text:gsub("^.- ", "")
                                    if not t.nameL.Text:find("^DOWN") then
                                        t.nameL.Text = "DOWN " .. baseName
                                    end
                                    t.nameL.TextColor3 = espColors.PlayerDowned
                                end
                            else
                                -- Restore original color
                                local origCol = espColors.Player
                                local plr = Players:GetPlayerFromCharacter(plrChar)
                                if plr then
                                    if plr.Team and (string.find(string.lower(plr.Team.Name), "killer") or string.find(string.lower(plr.Team.Name), "hunter")) then
                                        origCol = COLOR_KILLER
                                    elseif plr:GetAttribute("Role") == "Killer" or plr:GetAttribute("Killer") then
                                        origCol = COLOR_KILLER
                                    end
                                end
                                if t.hl then
                                    t.hl.FillColor = origCol
                                    t.hl.OutlineColor = origCol
                                end
                                if t.nameL then
                                    local baseName = t.nameL.Text:gsub("^DOWN ", "")
                                    t.nameL.Text = baseName
                                    t.nameL.TextColor3 = origCol
                                end
                            end
                        end
                    end
                end
            end
            task.wait(0.2)
        end
        distLoopRunning = false
    end)
end

local function hookRemoval(m: Instance, kind: string)
    pushConn(kind, m.Destroying:Connect(function() cleanup(m) end))
    pushConn(kind, m.AncestryChanged:Connect(function(_, parent)
        if not parent then cleanup(m) end
    end))
end

-- Generator ESP
local function anchorGen(model: Model): BasePart?
    local body = model:FindFirstChild("GeneratorBody")
    if body and body:IsA("BasePart") then return body :: BasePart end
    return model:FindFirstChildWhichIsA("BasePart") :: BasePart?
end

local function applyGen(model: Model)
    if tracked[model] then return end
    local anchor = anchorGen(model)
    if not anchor then return end
    
    local color = espColors.Generator
    local hl = mkHighlight(model, color)
    local bill, nameL, sub = mkBillboard(anchor, color, "Generator")
    
    local function upd()
        local p = tonumber(model:GetAttribute("RepairProgress")) or 0
        local regress = model:GetAttribute("Regressing")
        -- Lerp color from base to done based on progress
        local cp = math.clamp(p, 0, 100)
        local genColor = espColors.Generator:Lerp(COLOR_GEN_DONE, cp / 100)
        if hl then
            hl.FillColor = genColor
            hl.OutlineColor = genColor
        end
        if nameL then nameL.TextColor3 = genColor end
        if espShowGenPercent then
            sub.Text = string.format("[%d%%]%s", math.floor(p), regress and " \u{2193}" or "")
            sub.TextColor3 = regress and Color3.fromRGB(255, 120, 120) or Color3.fromRGB(120, 255, 120)
        else
            sub.Text = ""
        end
    end
    upd()
    
    local pc1 = model:GetAttributeChangedSignal("RepairProgress"):Connect(upd)
    local pc2 = model:GetAttributeChangedSignal("Regressing"):Connect(upd)
    
    tracked[model] = { hl = hl, bill = bill, anchor = anchor, nameL = nameL, sub = sub, progConns = { pc1, pc2 }, kind = "Generator" }
end

local function startGenerator()
    local Map = Workspace:FindFirstChild("Map")
    if not Map then return end
    for _, d in ipairs(Map:GetDescendants()) do
        if d:IsA("Model") and string.find(string.lower(d.Name), "generator") then
            applyGen(d)
            hookRemoval(d, "Generator")
        end
    end
    -- ponytail: use DescendantAdded to avoid replication race conditions where folders don't exist yet
    pushConn("Generator", Map.DescendantAdded:Connect(function(desc)
        if isKindActive("Generator") and desc:IsA("Model") and string.find(string.lower(desc.Name), "generator") then
            task.defer(function()
                if isKindActive("Generator") and desc.Parent and not tracked[desc] then
                    applyGen(desc)
                    hookRemoval(desc, "Generator")
                end
            end)
        end
    end))
end

-- Pallet ESP
local function pickPlank(model: Model): BasePart?
    local best: BasePart? = nil
    local bestVol = 0
    for _, d in ipairs(model:GetChildren()) do
        if d:IsA("MeshPart") and d.Transparency < 1 then
            local s = d.Size
            local vol = s.X * s.Y * s.Z
            if vol > bestVol then best = d :: BasePart; bestVol = vol end
        end
    end
    if best then return best end
    for _, d in ipairs(model:GetDescendants()) do
        if d:IsA("MeshPart") and d.Transparency < 1 then
            local s = d.Size
            local vol = s.X * s.Y * s.Z
            if vol > bestVol then best = d :: BasePart; bestVol = vol end
        end
    end
    return best or (model:FindFirstChildWhichIsA("BasePart") :: BasePart?)
end

local function applyPallet(model: Model)
    if tracked[model] then return end
    local anchor = pickPlank(model)
    if not anchor then return end
    local color = espColors.Pallet
    local hl = mkHighlight(model, color)
    local bill, nameL, sub = mkBillboard(anchor, color, "Pallet")
    tracked[model] = { hl = hl, bill = bill, anchor = anchor, nameL = nameL, sub = sub, wantDist = true, kind = "Pallet" }
end

local function startPallet()
    local Map = Workspace:FindFirstChild("Map")
    if not Map then return end
    for _, m in ipairs(Map:GetDescendants()) do
        if m:IsA("Model") then
            local nm = string.lower(m.Name)
            if string.find(nm, "pallet") and not string.find(nm, "crate") then
                applyPallet(m)
                hookRemoval(m, "Pallet")
            end
        end
    end
    -- ponytail: use DescendantAdded to avoid replication race conditions where folders don't exist yet
    pushConn("Pallet", Map.DescendantAdded:Connect(function(desc)
        if isKindActive("Pallet") and desc:IsA("Model") then
            local nm = string.lower(desc.Name)
            if string.find(nm, "pallet") and not string.find(nm, "crate") then
                task.defer(function()
                    if isKindActive("Pallet") and desc.Parent and not tracked[desc] then
                        applyPallet(desc)
                        hookRemoval(desc, "Pallet")
                    end
                end)
            end
        end
    end))
    ensureDistLoop()
end

-- Window ESP
local function applyWindow(model: Model)
    if tracked[model] then return end
    local anchor = model:FindFirstChildWhichIsA("BasePart") :: BasePart?
    if not anchor then return end
    local color = espColors.Window
    local hl = mkHighlight(model, color)
    local bill, nameL, sub = mkBillboard(anchor, color, "Window")
    tracked[model] = { hl = hl, bill = bill, anchor = anchor, nameL = nameL, sub = sub, wantDist = true, kind = "Window" }
end

local function startWindow()
    local Map = Workspace:FindFirstChild("Map")
    if not Map then return end
    for _, m in ipairs(Map:GetDescendants()) do
        if m:IsA("Model") and m.Name == "Window" then
            applyWindow(m)
            hookRemoval(m, "Window")
        end
    end
    pushConn("Window", Map.DescendantAdded:Connect(function(desc)
        if isKindActive("Window") and desc:IsA("Model") and desc.Name == "Window" then
            task.defer(function()
                if isKindActive("Window") and desc.Parent and not tracked[desc] then
                    applyWindow(desc)
                    hookRemoval(desc, "Window")
                end
            end)
        end
    end))
    ensureDistLoop()
end

-- SCP / Zombie ESP
local function anchorZombie(model: Model): BasePart?
    local hrp = model:FindFirstChild("HumanoidRootPart") or model:FindFirstChild("Torso") or model:FindFirstChild("Head")
    if hrp and hrp:IsA("BasePart") then return hrp :: BasePart end
    return model:FindFirstChildWhichIsA("BasePart") :: BasePart?
end

local function isZombie(m: Instance): boolean
    return m:IsA("Model") and m:FindFirstChildOfClass("Humanoid") ~= nil and Players:GetPlayerFromCharacter(m :: Model) == nil
end

local function applyZombie(model: Model)
    if tracked[model] then return end
    local anchor = anchorZombie(model)
    if not anchor then return end
    local nameLower = string.lower(model.Name)
    local labelText = string.find(nameLower, "scp") and "Zombie" or model.Name
    local color = espColors.SCP
    local hl = mkHighlight(model, color)
    local bill, nameL, sub = mkBillboard(anchor, color, labelText)
    tracked[model] = { hl = hl, bill = bill, anchor = anchor, nameL = nameL, sub = sub, wantDist = true, kind = "SCP" }
end

local function startZombie()
    local Map = Workspace:FindFirstChild("Map")
    if not Map then return end
    for _, d in ipairs(Map:GetDescendants()) do
        if isZombie(d) then
            applyZombie(d :: Model)
            hookRemoval(d, "SCP")
        end
    end
    pushConn("SCP", Map.DescendantAdded:Connect(function(desc)
        if isKindActive("SCP") and desc:IsA("Model") then
            task.defer(function()
                if isKindActive("SCP") and desc.Parent and not tracked[desc] and isZombie(desc) then
                    applyZombie(desc :: Model)
                    hookRemoval(desc, "SCP")
                end
            end)
        end
    end))
    ensureDistLoop()
end

-- Player ESP
local function anchorPlayer(char: Model): BasePart?
    local hrp = char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Head")
    if hrp and hrp:IsA("BasePart") then return hrp :: BasePart end
    return char:FindFirstChildWhichIsA("BasePart") :: BasePart?
end

local function playerColor(plr: Player): Color3
    local tm = plr.Team
    if tm and (string.find(string.lower(tm.Name), "killer") or string.find(string.lower(tm.Name), "hunter")) then
        return COLOR_KILLER
    end
    if plr:GetAttribute("Role") == "Killer" or plr:GetAttribute("Killer") then
        return COLOR_KILLER
    end
    return COLOR_PLAYER
end

local function recolorPlayer(plr: Player)
    local char = plr.Character
    local t = char and tracked[char]
    if not t then return end
    local col = playerColor(plr)
    if t.hl then
        t.hl.FillColor = col
        t.hl.OutlineColor = col
    end
    if t.nameL then t.nameL.TextColor3 = col end
end

local function applyPlayer(char: Model, plr: Player)
    if tracked[char] then return end
    local anchor = anchorPlayer(char)
    if not anchor then return end
    local col = espColors.Player
    if plr.Team and (string.find(string.lower(plr.Team.Name), "killer") or string.find(string.lower(plr.Team.Name), "hunter")) then
        col = COLOR_KILLER
    elseif plr:GetAttribute("Role") == "Killer" or plr:GetAttribute("Killer") then
        col = COLOR_KILLER
    end
    local hl = mkHighlight(char, col)
    local bill, nameL, sub = mkBillboard(anchor, col, plr.Name)
    tracked[char] = { hl = hl, bill = bill, anchor = anchor, nameL = nameL, sub = sub, wantDist = true, kind = "Player" }
end

local function startPlayer()
    local function setup(plr: Player)
        if plr == LocalPlayer then return end
        local function onChar(char: Model)
            task.defer(function()
                if isKindActive("Player") and char.Parent and not tracked[char] then
                    applyPlayer(char, plr)
                    pushConn("Player", char.AncestryChanged:Connect(function(_, parent)
                        if not parent then cleanup(char) end
                    end))
                end
            end)
        end
        if plr.Character then onChar(plr.Character) end
        pushConn("Player", plr.CharacterAdded:Connect(onChar))
        pushConn("Player", plr:GetPropertyChangedSignal("Team"):Connect(function() recolorPlayer(plr) end))
    end
    
    for _, plr in ipairs(Players:GetPlayers()) do setup(plr) end
    pushConn("Player", Players.PlayerAdded:Connect(function(plr)
        if isKindActive("Player") then setup(plr) end
    end))
    ensureDistLoop()
end

local starters = {
    Player = startPlayer,
    Generator = startGenerator,
    Pallet = startPallet,
    Window = startWindow,
    SCP = startZombie
}

-- ponytail: listen for when the map spawns (e.g. entering game from lobby) and re-initialize ESPs
Workspace.ChildAdded:Connect(function(child)
    if child.Name == "Map" then
        task.defer(function()
            for kind, active in pairs(activeKinds) do
                if active then
                    stopKind(kind)
                    starters[kind]()
                end
            end
        end)
    end
end)

function ESP.UpdateStates()
    for _, kind in ipairs({"Generator", "Pallet", "Window", "SCP", "Player"}) do
        local shouldBeActive = espMasterEnabled and (selectedKinds[kind] == true)
        if shouldBeActive ~= activeKinds[kind] then
            activeKinds[kind] = shouldBeActive
            if shouldBeActive then
                starters[kind]()
            else
                stopKind(kind)
            end
        end
    end
end

function ESP.SetMasterEnabled(enabled: boolean)
    espMasterEnabled = enabled
    ESP.UpdateStates()
end

function ESP.SetShowDistance(enabled: boolean)
    espShowDistance = enabled
end

function ESP.SetShowName(enabled: boolean)
    espShowName = enabled
end

function ESP.SetShowGenPercent(enabled: boolean)
    espShowGenPercent = enabled
end

function ESP.SetPlayerState(enabled: boolean)
    espPlayerState = enabled
end

function ESP.SetColor(kind: string, color: Color3)
    if espColors[kind] then
        espColors[kind] = color
        for model, entry in pairs(tracked) do
            if entry.kind == kind then
                if entry.hl then
                    entry.hl.FillColor = color
                    entry.hl.OutlineColor = color
                end
                if entry.nameL then entry.nameL.TextColor3 = color end
            end
        end
    end
end

function ESP.GetColors()
    return espColors
end

function ESP.SetSelectedKinds(selected: any)
    local newSelected: { [string]: boolean } = {
        Generator = false,
        Pallet = false,
        Window = false,
        SCP = false,
        Player = false
    }
    if typeof(selected) == "table" then
        for k, v in pairs(selected) do
            if typeof(k) == "number" and typeof(v) == "string" then
                if v == "SCP / Zombie" or v == "Zombie" then newSelected["SCP"] = true else newSelected[v] = true end
            elseif typeof(k) == "string" and v == true then
                if k == "SCP / Zombie" or k == "Zombie" then newSelected["SCP"] = true else newSelected[k] = true end
            end
        end
    end
    selectedKinds = newSelected
    ESP.UpdateStates()
end

-- =====================================================================
-- PLAYER MODULE (Zoom, FOV)
-- =====================================================================

local PlayerConfig = {
    UnlimitedZoom = false,
    MaxDistance = 1000,
    MinDistance = 0,
    FOVEnabled = false,
    FOV = 70,
    DefaultFOV = workspace.CurrentCamera.FieldOfView
}

local function applyUnlimitedZoom()
    if PlayerConfig.UnlimitedZoom then
        LocalPlayer.CameraMaxZoomDistance = PlayerConfig.MaxDistance
        LocalPlayer.CameraMinZoomDistance = PlayerConfig.MinDistance
    else
        LocalPlayer.CameraMaxZoomDistance = 128
        LocalPlayer.CameraMinZoomDistance = 0.5
    end
end

local function applyCameraFOV()
    local cam = workspace.CurrentCamera
    if not cam then return end
    if PlayerConfig.FOVEnabled then
        cam.FieldOfView = PlayerConfig.FOV
    else
        cam.FieldOfView = PlayerConfig.DefaultFOV
    end
end

-- Apply on respawn
LocalPlayer.CharacterAdded:Connect(function()
    task.wait(0.5)
    applyUnlimitedZoom()
    applyCameraFOV()
end)

local Player = {
    SetUnlimitedZoom = function(enabled: boolean)
        PlayerConfig.UnlimitedZoom = enabled
        applyUnlimitedZoom()
    end,
    SetMaxZoomDistance = function(dist: number)
        PlayerConfig.MaxDistance = dist
        if PlayerConfig.UnlimitedZoom then
            applyUnlimitedZoom()
        end
    end,
    SetCustomFOV = function(enabled: boolean)
        PlayerConfig.FOVEnabled = enabled
        applyCameraFOV()
    end,
    SetFOV = function(fov: number)
        PlayerConfig.FOV = fov
        applyCameraFOV()
    end,
}

-- =====================================================================
-- AIM CONFIGURATION & LOGIC MODULE EXPORT
-- =====================================================================
local AIM_CONFIG = {
    -- Aim Gun
    aimTargetMode   = "Killer",  -- "Killer" / "Survivor"
    silentAimGun    = true,      -- silent aim peluru (remote Fire)
    aimLock         = true,      -- kamera lock pas nahan pistol
    aimWallcheck    = true,      -- cuma target yg keliatan (LOS)
    aimEnableLead   = true,      -- prediksi gerak target
    aimFovRadius    = 120,
    aimLeadMult     = 1.0,
    aimSmooth       = 0.25,
    aimShowFov      = false,     -- POV circle (visual). set true kalau mau

    -- Aim Veil
    veilSilentAim   = true,      -- silent aim spear (remote Spearthrow)
    veilAimLock     = true,      -- kamera lock ballistic pas throw stance
    veilEnableLead  = true,
    veilFovRadius   = 150,
    veilShowFov     = false,     -- POV circle (visual). set true kalau mau
}

local Logic = {
    Combat = {
        SetAutoParry = function(enabled: boolean)
            autoParryEnabled = enabled
        end,
        SetParryDistance = function(dist: number)
            parryDistance = dist
        end,
        SetDashParryDistance = function(dist: number)
            dashDistance = dist
        end,
        SetAutoDodgeAbyss = function(enabled: boolean)
            autoDodgeEnabled = enabled
        end,
        SetDodgeDistance = function(dist: number)
            dodgeDistance = dist
        end,
        SetAutoSkillcheck = function(enabled: boolean)
            autoSkillcheckEnabled = enabled
        end
    },
    ESP = ESP,
    Aim = {
        -- Aim Gun Setters
        SetTargetMode = function(value: string)
            AIM_CONFIG.aimTargetMode = value
        end,
        SetSilentAim = function(value: boolean)
            AIM_CONFIG.silentAimGun = value
        end,
        SetAimLock = function(value: boolean)
            AIM_CONFIG.aimLock = value
        end,
        SetWallcheck = function(value: boolean)
            AIM_CONFIG.aimWallcheck = value
        end,
        SetEnableLead = function(value: boolean)
            AIM_CONFIG.aimEnableLead = value
        end,
        SetFovRadius = function(value: number)
            AIM_CONFIG.aimFovRadius = value
        end,
        SetShowFov = function(value: boolean)
            AIM_CONFIG.aimShowFov = value
        end,
        SetSmooth = function(value: number)
            AIM_CONFIG.aimSmooth = value
        end,
        SetLeadMult = function(value: number)
            AIM_CONFIG.aimLeadMult = value
        end,

        -- Aim Veil Setters
        SetVeilSilentAim = function(value: boolean)
            AIM_CONFIG.veilSilentAim = value
        end,
        SetVeilAimLock = function(value: boolean)
            AIM_CONFIG.veilAimLock = value
        end,
        SetVeilEnableLead = function(value: boolean)
            AIM_CONFIG.veilEnableLead = value
        end,
        SetVeilFovRadius = function(value: number)
            AIM_CONFIG.veilFovRadius = value
        end,
        SetVeilShowFov = function(value: boolean)
            AIM_CONFIG.veilShowFov = value
        end,
    },
    Player = Player,
}

-- ============================================================
-- Violence District | AIM (Side Script / Standalone)
-- ============================================================

local Players           = game:GetService("Players")
local Teams             = game:GetService("Teams")
local Workspace         = game:GetService("Workspace")
local RunService        = game:GetService("RunService")
local UserInputService  = game:GetService("UserInputService")
local LocalPlayer       = Players.LocalPlayer

-- ============================================================
-- SHARED: namecall hook infra (buat silent aim)
-- ============================================================
local silentSupported = (getrawmetatable ~= nil) and (getnamecallmethod ~= nil) and (newcclosure ~= nil)
local namecallHandlers = {}
local rawCall = nil

local function onNamecall(fn) table.insert(namecallHandlers, fn) end
local function callOriginal(self, ...) return rawCall(self, ...) end

local function installNamecallHook()
    if not silentSupported then
        warn("[Aim] Silent aim ga didukung executor ini (butuh getrawmetatable/getnamecallmethod/newcclosure).")
        return
    end
    local mt = getrawmetatable(game)
    if setreadonly then pcall(setreadonly, mt, false) end
    if getgenv and getgenv().__tomaAimOrig then
        pcall(function() mt.__namecall = getgenv().__tomaAimOrig end)
    end
    local oldNamecall = mt.__namecall
    if getgenv then getgenv().__tomaAimOrig = oldNamecall end
    rawCall = function(self, ...) return oldNamecall(self, ...) end
    local hookFn = function(self, ...)
        if typeof(self) == "Instance" then
            local method = getnamecallmethod()
            for _, h in ipairs(namecallHandlers) do
                local ok, res = h(self, method, ...)
                if ok then return res end
            end
        end
        return oldNamecall(self, ...)
    end
    mt.__namecall = newcclosure and newcclosure(hookFn) or hookFn
end

-- ============================================================
-- MODULE 1: Twist of Fate (Aim Lock + Silent Aim gun)
-- ============================================================
local function initTwistOfFate()
    local fovFollowMouse = false
    local AIM_TARGET_PART = "HumanoidRootPart"
    local AIM_BULLET_SPEED = 200
    local AIM_MUZZLE_OFFSET = Vector3.new(-1.41, -1.10, -5.44)
    local AimCamera = Workspace.CurrentCamera
    local aimSilentDir, aimTargetVel = nil, nil
    local GUN_ANIM_ID = "75029269564639"

    local function localAnimPlaying(animIdStr)
        local char = LocalPlayer.Character
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        local animator = hum and hum:FindFirstChildOfClass("Animator")
        if not animator then return false end
        for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
            if track.Animation and string.find(track.Animation.AnimationId, animIdStr, 1, true) then return true end
        end
        return false
    end
    local aimVelSampleName, aimVelSamplePos, aimVelSampleT = nil, nil, 0

    local function aimGetTeam() if AIM_CONFIG.aimTargetMode == "Survivor" then return Teams:FindFirstChild("Survivors") end return Teams:FindFirstChild("Killer") end
    local function aimGetFovCenter() if fovFollowMouse then local m = UserInputService:GetMouseLocation() return Vector2.new(m.X, m.Y) end local vp = AimCamera.ViewportSize return Vector2.new(vp.X/2, vp.Y/2) end
    local function aimGetPart(plr) return plr and plr.Character and plr.Character:FindFirstChild(AIM_TARGET_PART) end

    -- ponytail: RaycastParams pre-allocated to avoid garbage collection overhead in RenderStepped/HasLOS
    local aimRaycastParams = RaycastParams.new()
    aimRaycastParams.FilterType = Enum.RaycastFilterType.Exclude
    aimRaycastParams.IgnoreWater = true

    local function aimHasLOS(part)
        if not part or not part.Parent then return false end
        local origin = AimCamera.CFrame.Position
        local ignore = {}
        for _, plr in ipairs(Players:GetPlayers()) do if plr.Character then table.insert(ignore, plr.Character) end end
        aimRaycastParams.FilterDescendantsInstances = ignore
        local char = part.Parent
        local points = { part.Position }
        local head = char and char:FindFirstChild("Head")
        if head then table.insert(points, head.Position) end
        table.insert(points, part.Position + Vector3.new(0, 2.5, 0))
        table.insert(points, part.Position - Vector3.new(0, 2.5, 0))
        for _, p in ipairs(points) do if Workspace:Raycast(origin, p - origin, aimRaycastParams) == nil then return true end end
        return false
    end

    local function aimGetTarget()
        local team = aimGetTeam() if not team then return nil end
        local center = aimGetFovCenter()
        local best, bestDist = nil, AIM_CONFIG.aimFovRadius
        for _, plr in ipairs(team:GetPlayers()) do
            if plr ~= LocalPlayer then
                local part = aimGetPart(plr)
                if part then
                    local sp, onScreen = AimCamera:WorldToViewportPoint(part.Position)
                    if onScreen then
                        local d = (Vector2.new(sp.X, sp.Y) - center).Magnitude
                        if d <= bestDist then if (not AIM_CONFIG.aimWallcheck) or aimHasLOS(part) then best, bestDist = plr, d end end
                    end
                end
            end
        end
        return best
    end

    local function aimComputeDir(part, targetVel)
        local muzzle = AimCamera.CFrame:PointToWorldSpace(AIM_MUZZLE_OFFSET)
        local tp = part.Position local aimPoint = tp
        if AIM_CONFIG.aimEnableLead and targetVel then
            local tvel = targetVel * AIM_CONFIG.aimLeadMult
            local tof = (tp - muzzle).Magnitude / AIM_BULLET_SPEED
            for _ = 1, 2 do local predicted = tp + tvel * tof tof = (predicted - muzzle).Magnitude / AIM_BULLET_SPEED end
            aimPoint = tp + tvel * tof
        end
        local dir = (aimPoint - muzzle) if dir.Magnitude < 0.01 then return nil end return dir.Unit
    end

    local aimFovCircle = nil
    if Drawing then
        aimFovCircle = Drawing.new("Circle")
        aimFovCircle.Thickness = 2 aimFovCircle.NumSides = 64 aimFovCircle.Radius = AIM_CONFIG.aimFovRadius
        aimFovCircle.Filled = false aimFovCircle.Visible = false aimFovCircle.Color = Color3.fromRGB(255, 255, 255)
    end

    local aimRenderConn = RunService.RenderStepped:Connect(function()
        AimCamera = Workspace.CurrentCamera
        if not (AIM_CONFIG.silentAimGun or AIM_CONFIG.aimLock) then aimSilentDir = nil if aimFovCircle then aimFovCircle.Visible = false end return end
        if aimFovCircle then aimFovCircle.Visible = AIM_CONFIG.aimShowFov aimFovCircle.Radius = AIM_CONFIG.aimFovRadius aimFovCircle.Position = aimGetFovCenter() end
        local target = aimGetTarget()
        if target then
            local part = aimGetPart(target)
            if part then
                local pos = part.Position local now = tick()
                if aimVelSampleName == target.Name and aimVelSamplePos then
                    local dt = now - aimVelSampleT
                    if dt >= 0.04 then
                        local instVel = (pos - aimVelSamplePos) / dt
                        aimTargetVel = aimTargetVel and aimTargetVel:Lerp(instVel, 0.5) or instVel
                        aimVelSamplePos = pos aimVelSampleT = now
                    end
                else aimVelSampleName = target.Name aimVelSamplePos = pos aimVelSampleT = now aimTargetVel = Vector3.zero end
                local dir = aimComputeDir(part, aimTargetVel)
                aimSilentDir = (AIM_CONFIG.silentAimGun and dir) or nil
                if aimFovCircle then aimFovCircle.Color = Color3.fromRGB(255, 0, 0) end
                if AIM_CONFIG.aimLock and dir and localAnimPlaying(GUN_ANIM_ID) then
                    local cf = AimCamera.CFrame local goal = CFrame.new(cf.Position, cf.Position + dir)
                    AimCamera.CFrame = cf:Lerp(goal, AIM_CONFIG.aimSmooth)
                end
            else aimSilentDir = nil aimVelSampleName = nil if aimFovCircle then aimFovCircle.Color = Color3.fromRGB(255, 255, 255) end end
        else aimSilentDir = nil aimVelSampleName = nil if aimFovCircle then aimFovCircle.Color = Color3.fromRGB(255, 255, 255) end end
    end)

    onNamecall(function(self, method, ...)
        if method == "FireServer" and AIM_CONFIG.silentAimGun and aimSilentDir and self.Name == "Fire" then
            local p = self.Parent
            if p and p.Parent and p.Parent.Name == "Items" then
                local args = { ... }
                if typeof(args[2]) == "Vector3" then args[2] = aimSilentDir return true, callOriginal(self, unpack(args)) end
                for i, v in ipairs(args) do if typeof(v) == "Vector3" then args[i] = aimSilentDir return true, callOriginal(self, unpack(args)) end end
            end
        end
        return false
    end)

    if getgenv then
        local g = getgenv()
        if g.__tomaAimRender then pcall(function() g.__tomaAimRender:Disconnect() end) end
        g.__tomaAimRender = aimRenderConn
        if g.__tomaFov then pcall(function() g.__tomaFov:Remove() end) end
        g.__tomaFov = aimFovCircle
    end
end

-- ============================================================
-- MODULE 2: Veil (Silent Aim + Aim Lock ballistic)
-- ============================================================
local function initVeil()
    local veilFovFollowMouse = false
    local VEIL_TARGET_PART = "HumanoidRootPart"
    local VEIL_GRAVITY = 98.1
    local VEIL_AIM_SMOOTH = 0.35
    local VEIL_AIM_LOCK_SPEED = 165

    -- ponytail: single combined aim prediction offsets as requested (10-40 -> 1.8, 40-70 -> 2.2)
    local function veilOffsetForDist(dist)
        if dist >= 10 and dist <= 40 then
            return 1.8
        elseif dist > 40 and dist <= 70 then
            return 2.2
        end
        return 1.0
    end

    local veilTargetPos, veilTargetVel, veilTargetName = nil, nil, nil
    local veilSampleName, veilSamplePos, veilSampleT = nil, nil, 0
    local veilLockedPlayer = nil
    local veilLockGraceUntil = 0

    local function veilGetFovCenter() if veilFovFollowMouse then local m = UserInputService:GetMouseLocation() return Vector2.new(m.X, m.Y) end local vp = Workspace.CurrentCamera.ViewportSize return Vector2.new(vp.X/2, vp.Y/2) end
    local function veilGetPart(plr) return plr and plr.Character and plr.Character:FindFirstChild(VEIL_TARGET_PART) end

    local function veilInRange(origin, targetPos, speed, g)
        local disp = targetPos - origin
        local dy = disp.Y
        local flatX, flatZ = disp.X, disp.Z
        local dx = math.sqrt(flatX * flatX + flatZ * flatZ)
        if dx < 0.001 then return true end
        local v2 = speed * speed
        local root = v2 * v2 - g * (g * dx * dx + 2 * dy * v2)
        return root >= 0
    end

    local function veilGetTarget()
        local team = Teams:FindFirstChild("Survivors") if not team then return nil end
        local cam = Workspace.CurrentCamera local origin = cam.CFrame.Position local center = veilGetFovCenter()
        local best, bestDist = nil, AIM_CONFIG.veilFovRadius
        for _, plr in ipairs(team:GetPlayers()) do
            if plr ~= LocalPlayer then
                local part = veilGetPart(plr)
                if part then
                    local sp, onScreen = cam:WorldToViewportPoint(part.Position)
                    if onScreen then
                        local d = (Vector2.new(sp.X, sp.Y) - center).Magnitude
                        if d <= bestDist and veilInRange(origin, part.Position, VEIL_AIM_LOCK_SPEED, VEIL_GRAVITY) then best, bestDist = plr, d end
                    end
                end
            end
        end
        return best
    end

    local function veilSolveBallistic(origin, target, speed, g)
        local disp = target - origin
        local dy = disp.Y
        local flatX, flatZ = disp.X, disp.Z
        local dx = math.sqrt(flatX * flatX + flatZ * flatZ)
        if dx < 0.001 then return (disp.Magnitude > 0) and disp.Unit or nil, 0 end
        local v2 = speed * speed
        local root = v2 * v2 - g * (g * dx * dx + 2 * dy * v2)
        local tanTheta
        if root < 0 then tanTheta = 1 else local sq = math.sqrt(root) tanTheta = (v2 - sq) / (g * dx) end
        local horiz = Vector3.new(flatX / dx, 0, flatZ / dx)
        local dir = (horiz + Vector3.new(0, tanTheta, 0))
        if dir.Magnitude < 0.001 then return nil end
        dir = dir.Unit
        local cosTheta = math.sqrt(dir.X * dir.X + dir.Z * dir.Z)
        local tof = (speed * cosTheta > 0.001) and (dx / (speed * cosTheta)) or 0
        return dir, tof
    end

    local function veilSolveLead(origin, targetPos, targetVel, speed, g)
        local pred = targetPos
        local dist = (targetPos - origin).Magnitude
        local applyLead = AIM_CONFIG.veilEnableLead and targetVel
        local mult = applyLead and veilOffsetForDist(dist) or 0
        local dir, tof
        for _ = 1, 3 do
            dir, tof = veilSolveBallistic(origin, pred, speed, g)
            if not dir then return nil end
            if applyLead then pred = targetPos + targetVel * (tof * mult) end
        end
        return dir, tof
    end

    local veilFovCircle = nil
    if Drawing then
        veilFovCircle = Drawing.new("Circle")
        veilFovCircle.Thickness = 2 veilFovCircle.NumSides = 64 veilFovCircle.Radius = AIM_CONFIG.veilFovRadius
        veilFovCircle.Filled = false veilFovCircle.Visible = false veilFovCircle.Color = Color3.fromRGB(255, 255, 255)
    end

    local veilRenderConn = RunService.RenderStepped:Connect(function()
        if not (AIM_CONFIG.veilSilentAim or AIM_CONFIG.veilAimLock) then
            veilTargetPos, veilTargetVel, veilTargetName = nil, nil, nil
            veilSampleName = nil veilLockedPlayer = nil
            if veilFovCircle then veilFovCircle.Visible = false end
            return
        end
        if veilFovCircle then veilFovCircle.Visible = AIM_CONFIG.veilShowFov veilFovCircle.Radius = AIM_CONFIG.veilFovRadius veilFovCircle.Position = veilGetFovCenter() end
        local stanceChar = LocalPlayer.Character
        local inThrowStance = stanceChar and stanceChar:GetAttribute("spearmode") == true
        local holding = inThrowStance == true
        local target
        if holding then
            if not veilLockedPlayer then veilLockedPlayer = veilGetTarget() end
            if not (veilLockedPlayer and veilLockedPlayer.Parent and veilGetPart(veilLockedPlayer)) then veilLockedPlayer = veilGetTarget() end
            target = veilLockedPlayer
            veilLockGraceUntil = tick() + 0.3
        elseif veilLockedPlayer and tick() < veilLockGraceUntil and veilLockedPlayer.Parent and veilGetPart(veilLockedPlayer) then
            target = veilLockedPlayer
        else
            veilLockedPlayer = nil
            target = veilGetTarget()
        end
        if target then
            local part = veilGetPart(target)
            if part then
                local pos = part.Position local now = tick()
                if veilSampleName == target.Name and veilSamplePos then
                    local dt = now - veilSampleT
                    if dt >= 0.04 then
                        local instVel = (pos - veilSamplePos) / dt
                        veilTargetVel = veilTargetVel and veilTargetVel:Lerp(instVel, 0.5) or instVel
                        veilSamplePos = pos veilSampleT = now
                    end
                else veilSampleName = target.Name veilSamplePos = pos veilSampleT = now veilTargetVel = Vector3.zero end
                veilTargetPos = pos veilTargetName = target.Name
                if veilFovCircle then veilFovCircle.Color = Color3.fromRGB(255, 0, 0) end
                if AIM_CONFIG.veilAimLock and holding then
                    local cam = Workspace.CurrentCamera local origin = cam.CFrame.Position
                    local dir = veilSolveLead(origin, pos, veilTargetVel, VEIL_AIM_LOCK_SPEED, VEIL_GRAVITY)
                    if dir then local goal = CFrame.new(origin, origin + dir) cam.CFrame = cam.CFrame:Lerp(goal, VEIL_AIM_SMOOTH) end
                end
            else veilTargetPos, veilTargetVel = nil, nil veilSampleName = nil if veilFovCircle then veilFovCircle.Color = Color3.fromRGB(255, 255, 255) end end
        else veilTargetPos, veilTargetVel = nil, nil veilSampleName = nil if veilFovCircle then veilFovCircle.Color = Color3.fromRGB(255, 255, 255) end end
    end)

    onNamecall(function(self, method, ...)
        if method == "FireServer" and AIM_CONFIG.veilSilentAim and veilTargetPos and self.Name == "Spearthrow" then
            local p = self.Parent
            if p and p.Name == "Veil" then
                local args = { ... }
                local dirArg, speedArg, originArg = args[1], args[2], args[3]
                if typeof(dirArg) == "Vector3" and type(speedArg) == "number" and typeof(originArg) == "Vector3" then
                    local newDir = veilSolveLead(originArg, veilTargetPos, veilTargetVel, speedArg, VEIL_GRAVITY)
                    if newDir then args[1] = newDir return true, callOriginal(self, unpack(args)) end
                end
            end
        end
        return false
    end)

    if getgenv then
        local g = getgenv()
        if g.__tomaVeilRender then pcall(function() g.__tomaVeilRender:Disconnect() end) end
        g.__tomaVeilRender = veilRenderConn
        if g.__tomaVeilFov then pcall(function() g.__tomaVeilFov:Remove() end) end
        g.__tomaVeilFov = veilFovCircle
    end
end

-- ==================== INIT ========================
initTwistOfFate()
initVeil()
installNamecallHook()

print("[Aim Hub] Pistol & Veil script loaded. Silent aim supported: " .. tostring(silentSupported))

getgenv().Neko_HubLogic = Logic
return Logic
