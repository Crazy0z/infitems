-- game-load-script.lua
-- Handles automated boss farming with a pity system.

-- ── Configuration ─────────────────────────────────────────────────────────────
-- Set AutoPityEnabled = true at runtime (e.g. via a UI toggle) to start the loop
-- and set it to false to stop it.
local AutoPityEnabled   = false  -- Runtime toggle; set to true to start the loop
local PityFarmBossList  = {}     -- Boss names selected in "Pity Farm Bosses" dropdown
local PityKillBoss      = ""     -- Boss to target exclusively at pity 24/25
local PityFarmBossIndex = 1      -- Tracks the next boss to summon in the farm phase

-- ── Helpers (implement these for your specific game) ─────────────────────────

-- Returns the live Model for bossName if it exists in the workspace, else nil.
local function GetBossAlive(bossName)
    for _, v in ipairs(workspace:GetDescendants()) do
        if v.Name == bossName and v:IsA("Model") then
            local humanoid = v:FindFirstChildOfClass("Humanoid")
            if humanoid and humanoid.Health > 0 then
                return v
            end
        end
    end
    return nil
end

-- Summons the specified boss (game-specific).
local function SummonBoss(bossName)
    -- TODO: implement game-specific summon logic for bossName
end

-- Attacks / kills the given boss Model (game-specific).
local function KillBoss(boss)
    -- TODO: implement game-specific attack logic for the boss Model
end

-- Farms regular mobs as filler while waiting for a boss to spawn (game-specific).
local function FarmMobs()
    -- TODO: implement game-specific mob-farming logic
end

-- Returns the player's current pity count, read from the game state (game-specific).
local function GetCurrentPity()
    -- TODO: implement game-specific pity retrieval (e.g. read from a RemoteFunction or
    -- a DataStore value exposed to the client).
    return 0
end

-- ── AutoPityLoop ──────────────────────────────────────────────────────────────
--
-- Priority rules:
--   • NEVER farm mobs while any relevant boss is alive in the workspace.
--   • Kill Phase  (CurrentPity >= 24): target PityKillBoss only.
--   • Farm Phase  (CurrentPity  < 24): target bosses from PityFarmBossList,
--       skipping PityKillBoss (saved for the Kill Phase).
--
local function AutoPityLoop()
    while AutoPityEnabled do
        local killBossName  = PityKillBoss
        local currentPity   = GetCurrentPity()  -- read pity from game state each iteration

        if currentPity >= 24 then
            -- ── Kill Phase ────────────────────────────────────────────────────
            -- Only the designated kill boss matters here.
            local aliveBoss = GetBossAlive(killBossName)
            if aliveBoss then
                -- Boss is up – kill it immediately; do NOT farm mobs.
                KillBoss(aliveBoss)
            else
                -- Boss is not yet alive; summon it and farm mobs as filler.
                SummonBoss(killBossName)
                FarmMobs()
            end
        else
            -- ── Farm Phase ────────────────────────────────────────────────────
            -- Build a filtered list that excludes PityKillBoss so we never
            -- accidentally spend the kill boss during the farm phase.
            local filteredList = {}
            for _, bossName in ipairs(PityFarmBossList) do
                if bossName ~= killBossName then
                    table.insert(filteredList, bossName)
                end
            end

            -- Check whether any boss from the filtered list is currently alive.
            local aliveBoss = nil
            for _, bossName in ipairs(filteredList) do
                local boss = GetBossAlive(bossName)
                if boss then
                    aliveBoss = boss
                    break
                end
            end

            if aliveBoss then
                -- A target boss is alive – kill it; do NOT farm mobs.
                KillBoss(aliveBoss)
            else
                -- No relevant boss is alive; summon the next one and fill time
                -- with mob farming while waiting for it to spawn.
                if #filteredList > 0 then
                    -- Cycle through the list so each boss gets summoned in turn.
                    if PityFarmBossIndex > #filteredList then
                        PityFarmBossIndex = 1
                    end
                    SummonBoss(filteredList[PityFarmBossIndex])
                    PityFarmBossIndex = PityFarmBossIndex + 1
                end
                FarmMobs()
            end
        end

        task.wait(0.1)
    end
end

return AutoPityLoop
