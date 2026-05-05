-- game_load_manager.lua
-- Sailor Piece Auto-Farm Script
-- Handles movement, teleportation, and farming loops using game remotes only.
-- No hardcoded coordinates; relies on Workspace.NPCs and remote events.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer
local Character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
local HumanoidRootPart = Character:WaitForChild("HumanoidRootPart")
local Humanoid = Character:WaitForChild("Humanoid")

-- Remote references
local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
local TeleportToPortal = RemoteEvents:WaitForChild("TeleportToPortal")
local DashRemote = RemoteEvents:WaitForChild("DashRemote")

-- ────────────────────────────────────────────────────────────────────────────
-- IslandSystem
-- Associates mob / boss names with their island identifiers so the script can
-- fire the portal remote when a target is out of range.  No position vectors
-- are stored here; the game handles the actual teleport destination.
-- ────────────────────────────────────────────────────────────────────────────
local IslandSystem = {}

-- Map each mob / boss name to the island string expected by TeleportToPortal.
-- Extend this table as new mobs / islands are added to the game.
IslandSystem.MobMap = {
    -- Starter island mobs
    ["Slime"]           = "StarterIsland",
    ["Goblin"]          = "StarterIsland",
    ["Bandit"]          = "StarterIsland",

    -- Forest island mobs
    ["Wolf"]            = "ForestIsland",
    ["Treant"]          = "ForestIsland",
    ["Mushroom"]        = "ForestIsland",

    -- Desert island mobs
    ["Scorpion"]        = "DesertIsland",
    ["Mummy"]           = "DesertIsland",
    ["Sandworm"]        = "DesertIsland",

    -- Volcano island mobs
    ["Lava Golem"]      = "VolcanoIsland",
    ["Fire Salamander"] = "VolcanoIsland",
    ["Magma Crab"]      = "VolcanoIsland",

    -- Ocean island mobs
    ["Shark"]           = "OceanIsland",
    ["Sea Serpent"]     = "OceanIsland",
    ["Crab"]            = "OceanIsland",

    -- Snow island mobs
    ["Yeti"]            = "SnowIsland",
    ["Ice Golem"]       = "SnowIsland",
    ["Penguin"]         = "SnowIsland",

    -- Bosses (unique NPCs)
    ["Sea King"]        = "OceanIsland",
    ["Flame Warlord"]   = "VolcanoIsland",
    ["Frost Giant"]     = "SnowIsland",
    ["Sand Pharaoh"]    = "DesertIsland",
    ["Forest Guardian"] = "ForestIsland",
}

-- Fire TeleportToPortal to travel to the island associated with a given mob name.
-- Returns true if a teleport was attempted, false if no mapping was found.
function IslandSystem.TryPortalHopToIsland(mobName)
    local island = IslandSystem.MobMap[mobName]
    if island then
        TeleportToPortal:FireServer(island)
        return true
    end
    return false
end

-- ────────────────────────────────────────────────────────────────────────────
-- Utility helpers
-- ────────────────────────────────────────────────────────────────────────────

-- Distance threshold (studs) above which we use portal teleport instead of
-- dash movement.
local TELEPORT_THRESHOLD = 1000

-- Find the first NPC in Workspace.NPCs whose Name matches the given string.
-- Returns the NPC model, or nil if not found.
local function FindNPCByName(name)
    local npcsFolder = Workspace:FindFirstChild("NPCs")
    if not npcsFolder then return nil end
    for _, npc in ipairs(npcsFolder:GetChildren()) do
        if npc.Name == name then
            return npc
        end
    end
    return nil
end

-- Return the HumanoidRootPart of an NPC model, or nil.
local function GetNPCRoot(npc)
    if not npc then return nil end
    return npc:FindFirstChild("HumanoidRootPart") or npc:FindFirstChild("Root") or npc.PrimaryPart
end

-- Return the 3-D distance between the local character and an NPC model.
-- Returns math.huge if either part is missing.
local function DistanceToNPC(npc)
    local root = GetNPCRoot(npc)
    if not root then return math.huge end
    return (HumanoidRootPart.Position - root.Position).Magnitude
end

-- Refresh character references after a respawn / teleport.
local function RefreshCharacter()
    Character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
    HumanoidRootPart = Character:WaitForChild("HumanoidRootPart")
    Humanoid = Character:WaitForChild("Humanoid")
end

-- ────────────────────────────────────────────────────────────────────────────
-- MoveToGoal  –  Dash-based short-range movement
--
-- Fires DashRemote in small directional increments so movement looks like
-- normal player dashing rather than an instant position warp.
-- ────────────────────────────────────────────────────────────────────────────
local DASH_STEP_SIZE   = 20   -- studs per dash fire
local DASH_INTERVAL    = 0.15 -- seconds between dashes
local ARRIVE_TOLERANCE = 8    -- studs; considered "arrived" within this radius

local function MoveToGoal(targetPosition)
    RefreshCharacter()
    local iterations = 0
    -- Safety cap: (max expected dash range ~5000 studs / 20 studs per step) + buffer
    local maxIterations = 300

    while iterations < maxIterations do
        iterations = iterations + 1

        local currentPos = HumanoidRootPart.Position
        local delta = targetPosition - currentPos
        local distance = delta.Magnitude

        if distance <= ARRIVE_TOLERANCE then
            break
        end

        -- Direction toward the target, projected on the XZ plane so the dash
        -- stays at ground level.
        local direction = Vector3.new(delta.X, 0, delta.Z).Unit

        -- Compute the next step position, clamped to the remaining distance.
        local stepDist = math.min(DASH_STEP_SIZE, distance)
        local nextPos = currentPos + direction * stepDist

        -- Orient the character toward the target before dashing.
        HumanoidRootPart.CFrame = CFrame.lookAt(currentPos, Vector3.new(
            targetPosition.X, currentPos.Y, targetPosition.Z
        ))

        -- Fire the dash remote with the movement direction so the server
        -- registers a legitimate dash action.
        DashRemote:FireServer(direction)

        -- Apply a small position nudge within the dash distance so the
        -- character visually moves alongside the animation.
        HumanoidRootPart.CFrame = CFrame.new(nextPos)

        task.wait(DASH_INTERVAL)
    end
end

-- ────────────────────────────────────────────────────────────────────────────
-- Combat helper – attack the target NPC until it dies
-- ────────────────────────────────────────────────────────────────────────────
local function AttackNPC(npc)
    if not npc or not npc.Parent then return end

    local npcHumanoid = npc:FindFirstChildWhichIsA("Humanoid")
    local root = GetNPCRoot(npc)
    if not root or not npcHumanoid then return end

    -- Move close enough to attack
    MoveToGoal(root.Position)

    -- Wait until the NPC is defeated (health reaches 0 or it is removed)
    while npc.Parent and npcHumanoid.Health > 0 do
        task.wait(0.1)
    end
end

-- ────────────────────────────────────────────────────────────────────────────
-- Shared approach logic used by all farming loops.
--
-- 1. Locate the NPC by name.
-- 2. If it is beyond TELEPORT_THRESHOLD, fire TeleportToPortal and wait.
-- 3. Otherwise (or after teleport) use MoveToGoal (Dash) to close in.
-- Returns the found NPC model, or nil if not found.
-- ────────────────────────────────────────────────────────────────────────────
local function ApproachTarget(mobName)
    local npc = FindNPCByName(mobName)

    if not npc then
        -- Target not visible; try teleporting to its island first.
        IslandSystem.TryPortalHopToIsland(mobName)
        task.wait(3)  -- allow the teleport animation / loading to complete
        RefreshCharacter()
        npc = FindNPCByName(mobName)
        if not npc then return nil end
    end

    local dist = DistanceToNPC(npc)

    if dist > TELEPORT_THRESHOLD then
        -- Far away – use the portal remote to reach the island.
        local hopped = IslandSystem.TryPortalHopToIsland(mobName)
        if hopped then
            task.wait(3)
            RefreshCharacter()
            npc = FindNPCByName(mobName)
            if not npc then return nil end
        end
    end

    -- Now dash to the NPC.
    local root = GetNPCRoot(npc)
    if root then
        MoveToGoal(root.Position)
    end

    return npc
end

-- ────────────────────────────────────────────────────────────────────────────
-- Farm state flags – set these externally to start / stop each loop.
-- ────────────────────────────────────────────────────────────────────────────
local FarmState = {
    AutoLevel         = false,
    ManualFarm        = false,
    AutoPity          = false,
    AutoSummonBoss    = false,
    BossFarm          = false,
}

-- Current targets – set these before enabling the corresponding farm flag.
local FarmTargets = {
    AutoLevelMob      = "",   -- mob name for auto-levelling
    ManualFarmMob     = "",   -- mob name for manual mob farm
    PityBoss          = "",   -- boss name for pity farming
    SummonBoss        = "",   -- boss name for summonable boss farm
    Boss              = "",   -- boss name for direct boss farm
}

-- ────────────────────────────────────────────────────────────────────────────
-- AutoLevelLoop
-- Continuously finds and kills the quest mob to grind experience / levels.
-- ────────────────────────────────────────────────────────────────────────────
local function AutoLevelLoop()
    while FarmState.AutoLevel do
        local mobName = FarmTargets.AutoLevelMob
        if mobName == "" then
            task.wait(1)
        else
            local npc = ApproachTarget(mobName)
            if npc then
                AttackNPC(npc)
            end
            task.wait(0.5)
        end
    end
end

-- ────────────────────────────────────────────────────────────────────────────
-- ManualFarmLoop
-- Targets a specific mob selected by the user.
-- ────────────────────────────────────────────────────────────────────────────
local function ManualFarmLoop()
    while FarmState.ManualFarm do
        local mobName = FarmTargets.ManualFarmMob
        if mobName == "" then
            task.wait(1)
        else
            local npc = ApproachTarget(mobName)
            if npc then
                AttackNPC(npc)
            end
            task.wait(0.5)
        end
    end
end

-- ────────────────────────────────────────────────────────────────────────────
-- AutoPityLoop
-- Farms a boss on a pity timer (typically one with a guaranteed-drop mechanic).
-- ────────────────────────────────────────────────────────────────────────────
local function AutoPityLoop()
    while FarmState.AutoPity do
        local bossName = FarmTargets.PityBoss
        if bossName == "" then
            task.wait(1)
        else
            local npc = ApproachTarget(bossName)
            if npc then
                AttackNPC(npc)
            end
            task.wait(1)
        end
    end
end

-- ────────────────────────────────────────────────────────────────────────────
-- AutoSummonBossLoop
-- Travels to the boss island and summons/fights the boss repeatedly.
-- ────────────────────────────────────────────────────────────────────────────
local SummonBossRemote = RemoteEvents:FindFirstChild("SummonBoss")

local function AutoSummonBossLoop()
    while FarmState.AutoSummonBoss do
        local bossName = FarmTargets.SummonBoss
        if bossName == "" then
            task.wait(1)
        else
            -- First ensure we are on the right island via portal.
            local island = IslandSystem.MobMap[bossName]
            if island then
                TeleportToPortal:FireServer(island)
                task.wait(3)
                RefreshCharacter()
            end

            -- Attempt to summon the boss if the remote exists.
            if SummonBossRemote then
                SummonBossRemote:FireServer(bossName)
                task.wait(2)
            end

            -- Locate and fight the boss using the shared approach helper
            -- (portal teleport if far, then dash movement).
            local npc = ApproachTarget(bossName)
            if npc then
                AttackNPC(npc)
            end

            task.wait(1)
        end
    end
end

-- ────────────────────────────────────────────────────────────────────────────
-- BossFarmLoop
-- Continuously kills a specific world boss.
-- ────────────────────────────────────────────────────────────────────────────
local function BossFarmLoop()
    while FarmState.BossFarm do
        local bossName = FarmTargets.Boss
        if bossName == "" then
            task.wait(1)
        else
            local npc = ApproachTarget(bossName)
            if npc then
                AttackNPC(npc)
            end
            task.wait(1)
        end
    end
end

-- ────────────────────────────────────────────────────────────────────────────
-- Public API  –  start / stop each farming loop
-- ────────────────────────────────────────────────────────────────────────────
local GameLoadManager = {}

function GameLoadManager.StartAutoLevel(mobName)
    FarmTargets.AutoLevelMob = mobName or ""
    FarmState.AutoLevel = true
    task.spawn(AutoLevelLoop)
end

function GameLoadManager.StopAutoLevel()
    FarmState.AutoLevel = false
end

function GameLoadManager.StartManualFarm(mobName)
    FarmTargets.ManualFarmMob = mobName or ""
    FarmState.ManualFarm = true
    task.spawn(ManualFarmLoop)
end

function GameLoadManager.StopManualFarm()
    FarmState.ManualFarm = false
end

function GameLoadManager.StartAutoPity(bossName)
    FarmTargets.PityBoss = bossName or ""
    FarmState.AutoPity = true
    task.spawn(AutoPityLoop)
end

function GameLoadManager.StopAutoPity()
    FarmState.AutoPity = false
end

function GameLoadManager.StartAutoSummonBoss(bossName)
    FarmTargets.SummonBoss = bossName or ""
    FarmState.AutoSummonBoss = true
    task.spawn(AutoSummonBossLoop)
end

function GameLoadManager.StopAutoSummonBoss()
    FarmState.AutoSummonBoss = false
end

function GameLoadManager.StartBossFarm(bossName)
    FarmTargets.Boss = bossName or ""
    FarmState.BossFarm = true
    task.spawn(BossFarmLoop)
end

function GameLoadManager.StopBossFarm()
    FarmState.BossFarm = false
end

-- Refresh character after a respawn.
LocalPlayer.CharacterAdded:Connect(function(char)
    Character = char
    HumanoidRootPart = char:WaitForChild("HumanoidRootPart")
    Humanoid = char:WaitForChild("Humanoid")
end)

return GameLoadManager
