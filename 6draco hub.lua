
--========================================================
-- PREMIUM COMBAT CONTROL V30
-- Organized GUI | PC + CONTROLLER
--
-- PC:
-- 1 = Fighting Mode
-- M1 = Punch
--
-- Controller:
-- L1 = Fighting Mode
-- R2 = Punch
--
-- RightShift = GUI
--========================================================

local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local ContentProvider = game:GetService("ContentProvider")

local Player = Players.LocalPlayer

--========================================================
-- GUI
--========================================================

local Library = loadstring(game:HttpGet(
    "https://raw.githubusercontent.com/whosnetworph/Destruction/main/Destruction.lua"
))()

Library.Font = Font.fromEnum(Enum.Font.Gotham)
Library:SetPreset("Gold")
Library.MenuKeybind = Enum.KeyCode.RightShift

local Window = Library:Window({
    Title = "Combat Control",
    Size = UDim2.new(0, 570, 0, 470)
})

local CombatPage = Window:Page({Title = "Combat"})
local StylesPage = Window:Page({Title = "Styles"})
local VisualsPage = Window:Page({Title = "Visuals"})
local ControlsPage = Window:Page({Title = "Controls"})

local CombatSub = CombatPage:SubPage({
    Title = "Combat Settings",
    OneColumn = true
})

local ModeSection = CombatSub:Section({Title = "Fighting Mode"})
local ComboSection = CombatSub:Section({Title = "Combo Settings"})
local AuraSection = CombatSub:Section({Title = "Kill Aura"})

local StyleSub = StylesPage:SubPage({
    Title = "Animation Settings",
    OneColumn = true
})

local StyleSection = StyleSub:Section({Title = "Fighting Styles"})
local AnimationSection = StyleSub:Section({Title = "Style Changer"})

local VisualSub = VisualsPage:SubPage({
    Title = "Visual Settings",
    OneColumn = true
})

local PreviewSection = VisualSub:Section({Title = "Hitbox Preview"})

local ControlsSub = ControlsPage:SubPage({
    Title = "Keybinds",
    OneColumn = true
})

local ControlsSection = ControlsSub:Section({Title = "Controls"})

--========================================================
-- SETTINGS
--========================================================

local FightingEnabled = true
local StyleChangerEnabled = true
local TriplePunchEnabled = false
local KillAuraEnabled = false
local HitboxPreviewEnabled = false

local TriplePunchDelay = 0.25
local AttackRange = 6
local PreviewSize = 6
local AuraCooldown = 0.15

local SelectedStyle = "Karate"

--========================================================
-- ANIMATIONS
--========================================================

local Styles = {
    ["Karate"] = {
        Idle = "104468049270279",
        Punches = {
            "135075258740189",
            "79590019604052",
            "106851474615914",
            "102575967906366"
        }
    },

    ["Slap Boxing"] = {
        Idle = "103725421631244",
        Punches = {
            "71698809253226",
            "76012261026027",
            "123140940385070"
        }
    }
}

--========================================================
-- CHARACTER STATE
--========================================================

local Character
local Humanoid
local Animator
local LeftHand

local CharacterGeneration = 0
local AttackSequenceId = 0
local Attacking = false

local StyleTracks = {}
local CurrentIdleTrack
local CurrentPunchTrack

local PunchIndexes = {
    ["Karate"] = 0,
    ["Slap Boxing"] = 0
}

--========================================================
-- REMOTE
--========================================================

local Remotes = Player:WaitForChild("Remotes")
local HitEvent = Remotes:WaitForChild("HitEvent")

--========================================================
-- CHARACTER HELPERS
--========================================================

local function getCharacterParts()
    Character = Player.Character
    if not Character then return false end

    Humanoid = Character:FindFirstChildOfClass("Humanoid")

    if not Humanoid or Humanoid.Health <= 0 then
        return false
    end

    Animator = Humanoid:FindFirstChildOfClass("Animator")
    LeftHand = Character:FindFirstChild("LeftHand")

    return Animator ~= nil
end

local function isCurrentAttack(generation, sequence)
    return generation == CharacterGeneration
        and sequence == AttackSequenceId
        and FightingEnabled
        and Humanoid ~= nil
        and Humanoid.Health > 0
end

--========================================================
-- ANIMATION CLEANUP
--========================================================

local function stopTrack(track, fade)
    if track then
        pcall(function()
            track:Stop(fade or 0.1)
        end)
    end
end

local function destroyStyleTracks()
    stopTrack(CurrentIdleTrack, 0.1)
    stopTrack(CurrentPunchTrack, 0.1)

    for _, style in pairs(StyleTracks) do
        if style.Idle then
            pcall(function()
                style.Idle:Stop(0.1)
                style.Idle:Destroy()
            end)
        end

        for _, track in ipairs(style.Punches or {}) do
            pcall(function()
                track:Stop(0.1)
                track:Destroy()
            end)
        end
    end

    StyleTracks = {}
    CurrentIdleTrack = nil
    CurrentPunchTrack = nil
end

--========================================================
-- LOAD ANIMATIONS
--========================================================

local function loadAnimation(id)
    local animation = Instance.new("Animation")
    animation.AnimationId = "rbxassetid://" .. id

    local track = Animator:LoadAnimation(animation)
    track.Priority = Enum.AnimationPriority.Action4
    track.Looped = false

    return track, animation
end

local function loadStyles()
    if not getCharacterParts() then return false end

    destroyStyleTracks()

    local animations = {}

    for styleName, data in pairs(Styles) do
        local idleTrack, idleAnimation = loadAnimation(data.Idle)
        local punchTracks = {}

        table.insert(animations, idleAnimation)

        for _, id in ipairs(data.Punches) do
            local track, animation = loadAnimation(id)

            track.Priority = Enum.AnimationPriority.Action4
            track.Looped = false

            table.insert(punchTracks, track)
            table.insert(animations, animation)
        end

        StyleTracks[styleName] = {
            Idle = idleTrack,
            Punches = punchTracks
        }
    end

    pcall(function()
        ContentProvider:PreloadAsync(animations)
    end)

    for _, animation in ipairs(animations) do
        animation:Destroy()
    end

    return true
end

--========================================================
-- IDLE ANIMATION
--========================================================

local function playIdle()
    if not FightingEnabled then return end
    if not StyleChangerEnabled then return end
    if Attacking then return end
    if not getCharacterParts() then return end

    local style = StyleTracks[SelectedStyle]
    if not style or not style.Idle then return end

    if CurrentIdleTrack and CurrentIdleTrack.IsPlaying then
        return
    end

    CurrentIdleTrack = style.Idle

    pcall(function()
        CurrentIdleTrack.Priority = Enum.AnimationPriority.Action4
        CurrentIdleTrack:Play(0.2, 1, 1)
    end)
end

--========================================================
-- TARGET FINDER
--========================================================

local function getClosestPlayer(range)
    if not getCharacterParts() then return nil end

    local root = Character:FindFirstChild("HumanoidRootPart")
    if not root then return nil end

    local closestPlayer = nil
    local shortestDistance = range

    for _, target in ipairs(Players:GetPlayers()) do
        if target ~= Player and target.Character then
            local targetCharacter = target.Character
            local targetHumanoid = targetCharacter:FindFirstChildOfClass("Humanoid")
            local targetRoot = targetCharacter:FindFirstChild("HumanoidRootPart")

            if targetHumanoid and targetHumanoid.Health > 0 and targetRoot then
                local distance = (targetRoot.Position - root.Position).Magnitude

                if distance < shortestDistance then
                    shortestDistance = distance
                    closestPlayer = target
                end
            end
        end
    end

    return closestPlayer
end

local function targetIsValid(target)
    if not target or not target.Character then return false end
    if not getCharacterParts() then return false end

    local targetHumanoid = target.Character:FindFirstChildOfClass("Humanoid")
    local targetRoot = target.Character:FindFirstChild("HumanoidRootPart")
    local localRoot = Character:FindFirstChild("HumanoidRootPart")

    if not targetHumanoid or targetHumanoid.Health <= 0 then return false end
    if not targetRoot or not localRoot then return false end

    return (targetRoot.Position - localRoot.Position).Magnitude <= AttackRange
end

--========================================================
-- HIT EVENT
--========================================================

local function fireHit()
    if not getCharacterParts() then return end

    LeftHand = Character:FindFirstChild("LeftHand")
    if not LeftHand then return end

    -- Reacquire a valid target for every punch.
    local target = getClosestPlayer(AttackRange)
    if not target or not targetIsValid(target) then return end

    local targetCharacter = target.Character
    local targetRoot = targetCharacter:FindFirstChild("HumanoidRootPart")
    local targetArm = targetCharacter:FindFirstChild("RightUpperArm")

    if not targetRoot or not targetArm then return end

    local args = {
        "HitEvent",
        "Punch",
        {
            Normal = targetRoot.CFrame.LookVector.Unit,
            Instance = targetArm,
            Position = targetRoot.Position
        },
        {
            Limb = LeftHand,
            NonHit = false,
            Combo = 3
        }
    }

    pcall(function()
        HitEvent:FireServer(unpack(args))
    end)
end

--========================================================
-- PLAY ONE PUNCH ANIMATION
--========================================================

local function playPunchAnimation(generation, sequence)
    -- Animations only play if BOTH toggles are enabled.
    if not FightingEnabled or not StyleChangerEnabled then
        return true
    end

    if not getCharacterParts() then return false end
    if not isCurrentAttack(generation, sequence) then return false end

    local style = StyleTracks[SelectedStyle]
    if not style or #style.Punches == 0 then
        return true
    end

    stopTrack(CurrentIdleTrack, 0.12)

    PunchIndexes[SelectedStyle] =
        (PunchIndexes[SelectedStyle] % #style.Punches) + 1

    local track = style.Punches[PunchIndexes[SelectedStyle]]
    if not track then return true end

    CurrentPunchTrack = track

    pcall(function()
        track.Priority = Enum.AnimationPriority.Action4
        track.Looped = false
        track:Stop(0)
        track.TimePosition = 0
        track:Play(0.08, 1, 1)
    end)

    -- Wait for the complete animation, unless cancelled.
    local startTime = os.clock()
    local maxWait = math.max(track.Length + 1, 3)

    while track.IsPlaying do
        if not isCurrentAttack(generation, sequence) then
            return false
        end

        if os.clock() - startTime > maxWait then
            stopTrack(track, 0.05)
            break
        end

        task.wait()
    end

    if not isCurrentAttack(generation, sequence) then
        return false
    end

    CurrentPunchTrack = nil
    return true
end

--========================================================
-- SHARED ATTACK QUEUE
-- M1 AND KILL AURA BOTH USE THIS
--========================================================

local function performAttack()
    if Attacking then return end
    if not FightingEnabled then return end
    if not getCharacterParts() then return end

    Attacking = true

    local generation = CharacterGeneration

    AttackSequenceId += 1
    local sequence = AttackSequenceId

    -- One punch normally, three when enabled.
    local punchCount = TriplePunchEnabled and 3 or 1

    for punchNumber = 1, punchCount do
        if not isCurrentAttack(generation, sequence) then
            break
        end

        -- Play the custom animation only in fighting mode
        -- with Style Changer enabled.
        local animationCompleted = playPunchAnimation(
            generation,
            sequence
        )

        if not animationCompleted then
            break
        end

        if not isCurrentAttack(generation, sequence) then
            break
        end

        -- Send one hit request for each punch.
        fireHit()

        -- Wait between punches, not after the final punch.
        if punchNumber < punchCount then
            local delayValue = math.clamp(
                tonumber(TriplePunchDelay) or 0.25,
                0.05,
                1.5
            )

            local delayStarted = os.clock()

            while os.clock() - delayStarted < delayValue do
                if not isCurrentAttack(generation, sequence) then
                    break
                end

                task.wait(0.01)
            end
        end
    end

    -- Only the current sequence may unlock the attack system.
    if generation == CharacterGeneration
        and sequence == AttackSequenceId then

        Attacking = false
        CurrentPunchTrack = nil
        playIdle()
    end
end

--========================================================
-- FIGHTING MODE
--========================================================

local function setFighting(value)
    FightingEnabled = value

    AttackSequenceId += 1
    Attacking = false

    if not value then
        stopTrack(CurrentIdleTrack, 0.12)
        stopTrack(CurrentPunchTrack, 0.08)

        CurrentIdleTrack = nil
        CurrentPunchTrack = nil
        return
    end

    if StyleChangerEnabled then
        if not StyleTracks[SelectedStyle] then
            loadStyles()
        end

        playIdle()
    end
end

--========================================================
-- STYLE CHANGER
-- ENABLING IT AUTOMATICALLY ENABLES FIGHTING MODE
--========================================================

local function setStyleChanger(value)
    StyleChangerEnabled = value

    if value then
        -- Automatically enable fighting mode.
        FightingEnabled = true

        if loadStyles() then
            playIdle()
        end
    else
        -- Stop and remove custom animation tracks.
        stopTrack(CurrentIdleTrack, 0.12)
        stopTrack(CurrentPunchTrack, 0.08)

        destroyStyleTracks()
    end
end

local function setStyle(value)
    if not Styles[value] then return end

    SelectedStyle = value
    PunchIndexes[value] = 0

    if StyleChangerEnabled and FightingEnabled then
        loadStyles()
        playIdle()
    end
end

--========================================================
-- HITBOX PREVIEW
--========================================================

local PreviewPart

local function removePreview()
    if PreviewPart then
        PreviewPart:Destroy()
        PreviewPart = nil
    end
end

local function updatePreview()
    if not HitboxPreviewEnabled then
        removePreview()
        return
    end

    if not getCharacterParts() then
        removePreview()
        return
    end

    local root = Character:FindFirstChild("HumanoidRootPart")
    if not root then return end

    if not PreviewPart then
        PreviewPart = Instance.new("Part")
        PreviewPart.Name = "LocalHitboxPreview"
        PreviewPart.Shape = Enum.PartType.Ball
        PreviewPart.Material = Enum.Material.ForceField
        PreviewPart.Transparency = 0.75
        PreviewPart.Color = Color3.fromRGB(255, 190, 60)
        PreviewPart.Anchored = true
        PreviewPart.CanCollide = false
        PreviewPart.CanTouch = false
        PreviewPart.CanQuery = false
        PreviewPart.Parent = workspace
    end

    PreviewPart.Size = Vector3.new(
        PreviewSize,
        PreviewSize,
        PreviewSize
    )

    PreviewPart.CFrame = root.CFrame
end

RunService.RenderStepped:Connect(updatePreview)

--========================================================
-- KILL AURA
-- USES THE SAME ATTACK QUEUE AS M1
--========================================================

local LastAuraAttack = 0

RunService.Heartbeat:Connect(function()
    if not KillAuraEnabled then return end
    if not FightingEnabled then return end
    if Attacking then return end

    if os.clock() - LastAuraAttack < AuraCooldown then
        return
    end

    local target = getClosestPlayer(AttackRange)
    if not target then return end

    -- Reserve the aura cooldown before starting the combo.
    LastAuraAttack = os.clock()

    task.spawn(function()
        performAttack()
    end)
end)

--========================================================
-- INPUT
--========================================================

UIS.InputBegan:Connect(function(input, processed)
    if processed then return end

    if input.KeyCode == Enum.KeyCode.One
        or input.KeyCode == Enum.KeyCode.ButtonL1 then

        setFighting(not FightingEnabled)
        return
    end

    if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.KeyCode == Enum.KeyCode.ButtonR2 then

        task.spawn(performAttack)
    end
end)

--========================================================
-- RESPAWN HANDLING
--========================================================

local function setupCharacter(char)
    CharacterGeneration += 1
    AttackSequenceId += 1
    Attacking = false

    destroyStyleTracks()

    Character = char
    Humanoid = char:WaitForChild("Humanoid")
    Animator = Humanoid:WaitForChild("Animator")

    task.wait(0.35)

    if Player.Character ~= char then return end

    if StyleChangerEnabled then
        loadStyles()

        if FightingEnabled then
            playIdle()
        end
    end
end

Player.CharacterAdded:Connect(setupCharacter)

if Player.Character then
    task.spawn(setupCharacter, Player.Character)
end

--========================================================
-- GUI: COMBAT
--========================================================

ModeSection:Toggle({
    Name = "Fighting Mode",
    Default = FightingEnabled,
    Callback = function(value)
        setFighting(value)
    end
})

ComboSection:Toggle({
    Name = "Triple Punch",
    Default = TriplePunchEnabled,
    Callback = function(value)
        TriplePunchEnabled = value
    end
})

ComboSection:Slider({
    Name = "Triple Punch Delay",
    Min = 0.05,
    Max = 1.5,
    Default = TriplePunchDelay,
    Callback = function(value)
        TriplePunchDelay = tonumber(value) or 0.25
    end
})

AuraSection:Toggle({
    Name = "Kill Aura",
    Default = KillAuraEnabled,
    Callback = function(value)
        KillAuraEnabled = value
    end
})

AuraSection:Slider({
    Name = "Attack Range",
    Min = 1,
    Max = 20,
    Default = AttackRange,
    Callback = function(value)
        AttackRange = tonumber(value) or 6
    end
})

--========================================================
-- GUI: STYLES
--========================================================

AnimationSection:Toggle({
    Name = "Style Changer",
    Default = StyleChangerEnabled,
    Callback = function(value)
        setStyleChanger(value)
    end
})

StyleSection:Dropdown({
    Name = "Fighting Style",
    Items = {"Karate", "Slap Boxing"},
    Default = SelectedStyle,
    Callback = function(value)
        setStyle(value)
    end
})

--========================================================
-- GUI: VISUALS
--========================================================

PreviewSection:Toggle({
    Name = "Hitbox Preview",
    Default = HitboxPreviewEnabled,
    Callback = function(value)
        HitboxPreviewEnabled = value

        if not value then
            removePreview()
        end
    end
})

PreviewSection:Slider({
    Name = "Preview Size",
    Min = 2,
    Max = 20,
    Default = PreviewSize,
    Callback = function(value)
        PreviewSize = tonumber(value) or 6
    end
})

--========================================================
-- GUI: CONTROLS
--========================================================

ControlsSection:Paragraph({
    Title = "PC Controls",
    Content = "1 = Fighting Mode\nM1 = Punch"
})

ControlsSection:Paragraph({
    Title = "Controller Controls",
    Content = "L1 = Fighting Mode\nR2 = Punch"
})

ControlsSection:Paragraph({
    Title = "GUI",
    Content = "RightShift = Open / Close"
})

ControlsSection:Paragraph({
    Title = "Animation Rules",
    Content = "Style Changer ON automatically enables Fighting Mode.\nCustom animations only play while Fighting Mode is ON."
})
