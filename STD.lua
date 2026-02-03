local vu = game:GetService("VirtualUser")
game:GetService("Players").LocalPlayer.Idled:Connect(function()
    vu:Button2Down(Vector2.new(0, 0), workspace.CurrentCamera.CFrame)
    task.wait(1)
    vu:Button2Up(Vector2.new(0, 0), workspace.CurrentCamera.CFrame)
end)

-- Create draggable button if not exists
if not game:GetService("Players").LocalPlayer.PlayerGui:FindFirstChild("DraggableControlButton") then
    local ScreenGui = Instance.new("ScreenGui")
    ScreenGui.Name = "DraggableControlButton"
    ScreenGui.ResetOnSpawn = false
    ScreenGui.Parent = game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")

    local Button = Instance.new("TextButton")
    Button.Size = UDim2.new(0, 100, 0, 40)
    Button.Position = UDim2.new(0.9, 0, 0.1, 0)
    Button.Text = "Open/Close"
    Button.BackgroundColor3 = Color3.fromRGB(60, 180, 75)
    Button.TextColor3 = Color3.new(1, 1, 1)
    Button.Font = Enum.Font.SourceSansBold
    Button.TextSize = 18
    Button.Active = true
    Button.Draggable = true
    Button.Parent = ScreenGui

    Button.MouseButton1Click:Connect(function()
        local vim = game:GetService("VirtualInputManager")
        vim:SendKeyEvent(true, "RightControl", false, game)
        vim:SendKeyEvent(false, "RightControl", false, game)
    end)
end

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local VirtualUser = game:GetService("VirtualUser")
local Workspace = game:GetService("Workspace")
local HttpService = game:GetService("HttpService")
local TweenService = game:GetService("TweenService")

local LocalPlayer = Players.LocalPlayer

-- // UI LIBRARY LOADING //
local MacLib = loadstring(game:HttpGet("https://github.com/biggaboy212/Maclib/releases/latest/download/maclib.txt"))()

local Window = MacLib:Window({
    Title = "Crazy Hub",
    Subtitle = "Sorcerer Tower Defense | By Crazy",
    Size = UDim2.fromOffset(868, 650),
    DragStyle = 2,
    DisabledWindowControls = {},
    ShowUserInfo = false,
    Keybind = Enum.KeyCode.RightControl,
    AcrylicBlur = false, 
})

-- // VARIABLES //
local FolderPath = "Crazy_Hub"
if not isfolder(FolderPath) then makefolder(FolderPath) end

local State = {
    IsRecording = false,
    IsReplaying = false,
    AutoJoin = false,
    AutoStart = false,
    AutoSkip = false,
    AutoReplay = false,
    
    CurrentMacro = {},
    MacroName = "", 
    RecordingMode = "Index",
    
    SelectedMacroToPlay = nil,
    SelectedMacroToDelete = nil,
    
    GameStart = 0,
    LastRequestedUnit = nil,
    
    SelectedMode = "Story",
    SelectedStage = 1,
    SelectedDifficulty = "Normal"
}

-- Tower Tracking
local TowerCounter = 0
local TowerIDToNumber = {} -- Name (BowSorcerer) -> Number (1)
local TowerNumberToID = {} -- Number (1) -> Name (BowSorcerer)
local TowerInstanceMap = {} -- Instance -> Number
local TowerPositions = {} -- Number -> Vector3 (The anchor for finding swaps)

-- // UTILITY FUNCTIONS //
local function SafeNotify(title, desc)
    task.spawn(function()
        pcall(function()
            Window:Notify({Title = title, Description = desc, Lifetime = 2})
        end)
    end)
end

local function GetRootPart()
    local char = LocalPlayer.Character
    return char and char:FindFirstChild("HumanoidRootPart")
end

local function GetMoney()
    if LocalPlayer:FindFirstChild("Gold") then return LocalPlayer.Gold.Value end
    local gui = LocalPlayer.PlayerGui:FindFirstChild("GameGui")
    if gui and gui:FindFirstChild("Info") then
        local stat = gui.Info:FindFirstChild("Stats")
        if stat and stat:FindFirstChild("Gold") then return tonumber(stat.Gold.Text) or 0 end
    end
    return 0
end

local function GetWave()
    if Workspace:FindFirstChild("Info") and Workspace.Info:FindFirstChild("Wave") then
        return Workspace.Info.Wave.Value
    end
    return 0
end

local function IsInGame()
    return Workspace:FindFirstChild("Info") and Workspace.Info:FindFirstChild("Wave") ~= nil
end

local function IsInLobby()
    return not IsInGame()
end

local function GetUnitCostFromGUI(unitID)
    local gui = LocalPlayer.PlayerGui:FindFirstChild("GameGui")
    if gui and gui:FindFirstChild("Towers") then
        local unitFrame = gui.Towers:FindFirstChild(unitID)
        if unitFrame then
            local priceObj = unitFrame:FindFirstChild("Price")
            if priceObj then
                if priceObj:IsA("TextLabel") then return tonumber(priceObj.Text) or 0
                elseif priceObj:IsA("Frame") and priceObj:FindFirstChild("TextLabel") then return tonumber(priceObj.TextLabel.Text) or 0 end
            end
        end
    end
    return 0
end

-- // TOWER TRACKING LOGIC //
local function getTowerNumber(towerInstance)
    if not towerInstance then return nil end
    
    -- 1. Instance Check (Fastest)
    if TowerInstanceMap[towerInstance] then return TowerInstanceMap[towerInstance] end
    
    -- 2. Name Check (Backup)
    -- WARNING: This is dangerous for duplicates, only use if instance failed
    local success, name = pcall(function() return towerInstance.Name end)
    if success and name and TowerIDToNumber[name] then 
        TowerInstanceMap[towerInstance] = TowerIDToNumber[name]
        return TowerIDToNumber[name] 
    end
    
    -- 3. Position Check (Best for Swaps/Upgrades)
    if towerInstance.PrimaryPart then
        local pos = towerInstance.PrimaryPart.Position
        for num, savedPos in pairs(TowerPositions) do
            if (pos - savedPos).Magnitude < 1.0 then
                -- Re-link the new name to the old number
                local oldName = TowerNumberToID[num]
                
                -- CRITICAL: Only clear old name if it's different!
                if oldName and oldName ~= towerInstance.Name then 
                    TowerIDToNumber[oldName] = nil 
                end 
                
                -- Update mapping for the new model (Upgrade)
                TowerIDToNumber[towerInstance.Name] = num
                TowerNumberToID[num] = towerInstance.Name
                TowerInstanceMap[towerInstance] = num
                return num
            end
        end
    end
    
    return nil
end

local function registerNewTower(towerInstance, forceNumber)
    local towerUUID = towerInstance.Name
    local pos = towerInstance.PrimaryPart and towerInstance.PrimaryPart.Position
    
    -- Force Number (Used in Playback & Initial Placement)
    if forceNumber then
        TowerCounter = math.max(TowerCounter, forceNumber)
        
        -- OVERWRITE any existing mapping for this name if forcing
        TowerIDToNumber[towerUUID] = forceNumber
        TowerNumberToID[forceNumber] = towerUUID
        TowerInstanceMap[towerInstance] = forceNumber
        if pos then TowerPositions[forceNumber] = pos end
        return forceNumber
    end

    -- Normal registration (Avoid duplicates)
    -- If this instance is already mapped, return it
    if TowerInstanceMap[towerInstance] then return TowerInstanceMap[towerInstance] end
    
    -- If we are just 'finding' it, but it has a name we know...
    -- BE CAREFUL: If 2 units have same name, this returns the first one.
    -- We rely on Position Check or forced numbering for new placements.
    if TowerIDToNumber[towerUUID] then 
        return TowerIDToNumber[towerUUID] 
    end
    
    -- New ID
    TowerCounter = TowerCounter + 1
    local towerNumber = TowerCounter
    
    TowerIDToNumber[towerUUID] = towerNumber
    TowerNumberToID[towerNumber] = towerUUID
    TowerInstanceMap[towerInstance] = towerNumber 
    if pos then TowerPositions[towerNumber] = pos end
    
    return towerNumber
end

local function clearTowerTracking()
    table.clear(TowerIDToNumber)
    table.clear(TowerNumberToID)
    table.clear(TowerInstanceMap)
    table.clear(TowerPositions)
    TowerCounter = 0
end

local function SaveMacro(name, data)
    local payload = {
        metadata = {
            recordingMode = State.RecordingMode,
            createdAt = os.time(),
            version = "2.2"
        },
        actions = data
    }
    writefile(FolderPath .. "/" .. name .. ".json", HttpService:JSONEncode(payload))
end

local function LoadMacro(name)
    local cleanName = name:gsub("SorcererTD_Hub[\\/]", ""):gsub("%.json", "")
    local fullPath = FolderPath .. "/" .. cleanName .. ".json"
    if isfile(fullPath) then
        local data = HttpService:JSONDecode(readfile(fullPath))
        if data.actions then return data.actions, data.metadata end
        return data, {recordingMode = "Index"}
    end
    return nil, nil
end

local function RefreshMacroList()
    local list = {}
    for _, file in ipairs(listfiles(FolderPath)) do
        if file:sub(-5) == ".json" then 
            local fileName = file:match("([^\\/]+)%.json$")
            if fileName then table.insert(list, fileName) end
        end
    end
    return list
end

LocalPlayer.Idled:Connect(function()
    VirtualUser:CaptureController()
    VirtualUser:ClickButton2(Vector2.new())
end)

-- // AUTO JOIN LOGIC (UPDATED) //
local function RunAutoJoin()
    while State.AutoJoin do
        if IsInLobby() then
            local Root = GetRootPart()
            if Root then
                local TpName = "Teleporter1"
                local IsSukuna = State.SelectedMode == "Sukuna"
                
                if IsSukuna then 
                    -- Sukuna has 4 teleporters, let's try to find a valid one or cycle through them
                    -- Defaulting to 1, or iterating if occupied logic was needed, but simpler is better:
                    TpName = "Teleporter1" -- Start check here
                    
                    -- Simple check to see if Teleporter1 exists, if not try others
                    local checkFolder = Workspace.SukunaTeleporters
                    if not checkFolder:FindFirstChild("Teleporter1") then TpName = "Teleporter2" end
                    if not checkFolder:FindFirstChild("Teleporter2") then TpName = "Teleporter3" end
                    
                    -- Or we can just default to Teleporter3 as requested in previous chats, 
                    -- but user said "Sukuna has 4", so let's stick to a valid existing one.
                    -- Let's try Teleporter1 by default.
                else
                    -- Story Logic
                    if State.SelectedStage >= 11 then TpName = "Teleporter5" 
                    elseif State.SelectedStage >= 6 then TpName = "Teleporter3" 
                    else TpName = "Teleporter1" end
                end
                
                local TpFolder = IsSukuna and Workspace.SukunaTeleporters or Workspace.Teleporters
                local TpObj = TpFolder:FindFirstChild(TpName)
                
                -- Fallback if specific one missing
                if not TpObj and IsSukuna then
                     -- Try finding ANY valid teleporter
                     for i = 1, 4 do
                         local t = TpFolder:FindFirstChild("Teleporter" .. i)
                         if t then TpObj = t; TpName = "Teleporter" .. i; break end
                     end
                end
                
                if TpObj then
                    local targetPart = nil
                    if TpObj:FindFirstChild("Teleports") then
                        -- Check for specific Entrance part first (Sukuna uses this)
                        if TpObj.Teleports:FindFirstChild("Entrance") then
                            targetPart = TpObj.Teleports.Entrance
                        elseif TpObj.Teleports:FindFirstChild("TeleportIn") then
                            targetPart = TpObj.Teleports.TeleportIn
                        end
                    end

                    if targetPart then
                        Root.CFrame = targetPart.CFrame
                        task.wait(0.5)
                        SafeNotify("Auto Join", "Teleported to " .. (IsSukuna and "Sukuna " or "Story ") .. TpName)
                        
                        if IsSukuna then 
                            ReplicatedStorage.Remotes.SukunaTeleporters.ChooseStage:FireServer(TpObj, false)
                        else 
                            ReplicatedStorage.Remotes.Teleporters.ChooseStage:FireServer(TpObj, State.SelectedStage, State.SelectedDifficulty, false) 
                        end
                        
                        task.wait(1)
                        
                        if State.AutoStart then
                            SafeNotify("Auto Join", "Starting Game...")
                            if IsSukuna then 
                                ReplicatedStorage.Remotes.SukunaTeleporters.Start:FireServer(TpObj)
                            else 
                                ReplicatedStorage.Remotes.Teleporters.Start:FireServer(TpObj) 
                            end
                            repeat task.wait(1) until IsInGame() or not State.AutoJoin
                        end
                    else
                        SafeNotify("Error", "Could not find Entrance for " .. TpName)
                    end
                end
            end
        end
        task.wait(2)
    end
end

-- // RECORDING HOOK //
local mt = getrawmetatable(game)
local oldNameCall = mt.__namecall
setreadonly(mt, false)

mt.__namecall = function(self, ...)
    local args = {...}
    local method = getnamecallmethod()
    
    if State.IsRecording and (method == "InvokeServer" or method == "FireServer") then
        local remoteName = self.Name 
        
        -- 1. REQUEST
        if remoteName == "RequestTower" then
            State.LastRequestedUnit = args[1]
        end

        -- 2. SPAWN (PLACE)
        if remoteName == "SpawnNewTower" then
            task.spawn(function()
                local UnitUUID = args[1]
                local PositionCFrame = args[2]
                local UnitName = State.LastRequestedUnit or "Unknown"
                
                local Cost = GetUnitCostFromGUI(UnitUUID)
                if Cost == 0 then
                    local moneyBefore = GetMoney()
                    task.wait(0.5)
                    local diff = moneyBefore - GetMoney()
                    if diff > 0 then Cost = diff end
                end
                
                -- ALWAYS INCREMENT for new placements
                local towerNumber = TowerCounter + 1
                
                local recordTime = 0
                if State.RecordingMode == "Hybrid" then recordTime = os.time() - State.GameStart end
                
                local action = {
                    Type = "Place",
                    Time = recordTime,
                    UnitName = UnitName, 
                    UnitID = UnitUUID,   
                    CFrame = {
                        X = PositionCFrame.X, Y = PositionCFrame.Y, Z = PositionCFrame.Z,
                        R00 = PositionCFrame.RightVector.X, R01 = PositionCFrame.RightVector.Y, R02 = PositionCFrame.RightVector.Z,
                        R10 = PositionCFrame.UpVector.X, R11 = PositionCFrame.UpVector.Y, R12 = PositionCFrame.UpVector.Z,
                        R20 = PositionCFrame.LookVector.X, R21 = PositionCFrame.LookVector.Y, R22 = PositionCFrame.LookVector.Z
                    },
                    Cost = Cost,
                    Wave = GetWave(),
                    TowerNumber = towerNumber
                }
                table.insert(State.CurrentMacro, action)
                SafeNotify("Recorded Place", UnitName .. " (#" .. towerNumber .. ")")
                State.LastRequestedUnit = nil
                
                -- Save position immediately
                TowerPositions[towerNumber] = PositionCFrame.Position

                -- WAIT and FORCE REGISTER (Bypassing Name Check)
                local attempts = 0
                while attempts < 50 do
                    for _, t in pairs(Workspace.Towers:GetChildren()) do
                        if t.PrimaryPart and (t.PrimaryPart.Position - PositionCFrame.Position).Magnitude < 1.0 then
                            -- Only register if we haven't mapped THIS instance yet
                            if not TowerInstanceMap[t] then
                                registerNewTower(t, towerNumber) -- FORCE this number
                                return
                            end
                        end
                    end
                    attempts = attempts + 1
                    task.wait(0.1)
                end
            end)
        end

        -- 3. UPGRADE
        if remoteName == "UpgradeTower" then
            task.spawn(function()
                local TowerInstance = args[1]
                local towerNumber = getTowerNumber(TowerInstance)
                
                if towerNumber then
                    local OldMoney = GetMoney()
                    task.wait(0.5)
                    local Cost = OldMoney - GetMoney()
                    
                    local recordTime = 0
                    if State.RecordingMode == "Hybrid" then recordTime = os.time() - State.GameStart end

                    table.insert(State.CurrentMacro, {
                        Type = "Upgrade",
                        Time = recordTime,
                        TowerNumber = towerNumber,
                        Cost = Cost,
                        Wave = GetWave()
                    })
                    SafeNotify("Recorded Upgrade", "Tower #" .. towerNumber)
                else
                    SafeNotify("Warning", "Upgrade missed! Tower lost.")
                end
            end)
        end

        -- 4. SELL
        if remoteName == "SellTower" then
            local TowerInstance = args[1]
            local towerNumber = getTowerNumber(TowerInstance)
            local towerName = nil
            pcall(function() towerName = TowerInstance.Name end)

            task.spawn(function()
                if towerNumber then
                    local recordTime = 0
                    if State.RecordingMode == "Hybrid" then recordTime = os.time() - State.GameStart end

                    table.insert(State.CurrentMacro, {
                        Type = "Sell",
                        Time = recordTime,
                        TowerNumber = towerNumber,
                        Wave = GetWave()
                    })
                    if towerName then TowerIDToNumber[towerName] = nil end
                    TowerNumberToID[towerNumber] = nil
                    TowerInstanceMap[TowerInstance] = nil
                    SafeNotify("Recorded Sell", "Tower #" .. towerNumber)
                end
            end)
        end
        
        -- 5. ABILITIES
        if remoteName == "ChangeTowerMode" or remoteName:find("Domain") or remoteName == "SukunaDomain" or remoteName == "GojoDomain" or remoteName == "MahitoDomain" then
            task.spawn(function()
                local TowerInstance = args[1]
                local towerNumber = getTowerNumber(TowerInstance)
                if towerNumber then
                    local recordTime = 0
                    if State.RecordingMode == "Hybrid" then recordTime = os.time() - State.GameStart end

                    table.insert(State.CurrentMacro, {
                        Type = "Ability",
                        Time = recordTime,
                        Action = remoteName,
                        TowerNumber = towerNumber,
                        Wave = GetWave()
                    })
                    SafeNotify("Recorded Action", remoteName)
                end
            end)
        end
    end
    return oldNameCall(self, ...)
end

-- // PLAYBACK LOGIC //
local function FindTowerByNumber(num)
    -- 1. Try saved UUID
    local id = TowerNumberToID[num] 
    if id then 
        local t = Workspace.Towers:FindFirstChild(id)
        if t then return t end
    end
    
    -- 2. Try Position (Swap Fix)
    local savedPos = TowerPositions[num]
    if savedPos then
        for _, t in pairs(Workspace.Towers:GetChildren()) do
            if t.PrimaryPart and (t.PrimaryPart.Position - savedPos).Magnitude < 1.0 then
                registerNewTower(t, num)
                return t
            end
        end
    end
    return nil
end

local function PlayMacroLoop()
    while State.IsReplaying do
        if IsInLobby() then
            SafeNotify("Macro Loop", "Waiting for game start...")
            while IsInLobby() and State.IsReplaying do task.wait(1) end
            SafeNotify("Macro Loop", "Game Started!")
        else
            local targetMacro = State.SelectedMacroToPlay
            local Actions, Metadata = LoadMacro(targetMacro or "")
            if not Actions then
                SafeNotify("Error", "Macro not found!")
                State.IsReplaying = false
                break
            end
            
            local replayMode = (Metadata and Metadata.recordingMode) or "Index"
            clearTowerTracking()
            SafeNotify("Macro", "Playing: " .. targetMacro)
            
            local StartTime = os.time()
            repeat task.wait(1) until GetWave() >= 1 or not State.IsReplaying
            
            for i, Action in ipairs(Actions) do
                if not State.IsReplaying then break end
                
                -- Wait Logic
                if replayMode == "Hybrid" and Action.Time and Action.Time > 0 then
                    while (os.time() - StartTime) < Action.Time and State.IsReplaying do task.wait(0.1) end
                end
                
                if Action.Wave then 
                    while GetWave() < Action.Wave and State.IsReplaying do task.wait(0.5) end 
                end
                
                if Action.Cost and Action.Cost > 0 then
                    while GetMoney() < Action.Cost and State.IsReplaying do 
                        if IsInLobby() then break end 
                        task.wait(0.2) 
                    end
                end
                
                if not State.IsReplaying then break end

                if Action.Type == "Place" then
                    local cf = CFrame.new(Action.CFrame.X, Action.CFrame.Y, Action.CFrame.Z, Action.CFrame.R00, Action.CFrame.R01, Action.CFrame.R02, Action.CFrame.R10, Action.CFrame.R11, Action.CFrame.R12, Action.CFrame.R20, Action.CFrame.R21, Action.CFrame.R22)
                    
                    if Action.UnitName then 
                        ReplicatedStorage.Functions.RequestTower:InvokeServer(Action.UnitName) 
                        task.wait(0.1) 
                    end
                    
                    ReplicatedStorage.Functions.SpawnNewTower:InvokeServer(Action.UnitID, cf)
                    
                    local num = Action.TowerNumber or (TowerCounter + 1)
                    TowerPositions[num] = cf.Position
                    
                    local found = false
                    local placementStart = tick()
                    
                    while State.IsReplaying do
                        if found then break end
                        if IsInLobby() then break end
                        
                        for _, t in pairs(Workspace.Towers:GetChildren()) do
                            if t.PrimaryPart and (t.PrimaryPart.Position - cf.Position).Magnitude < 3.0 then
                                -- For duplicates: Only register if this instance isn't already claimed
                                if not TowerInstanceMap[t] then
                                    registerNewTower(t, num)
                                    found = true
                                    break
                                end
                            end
                        end
                        
                        task.wait(0.1)
                        if tick() - placementStart > 15 then 
                             SafeNotify("Warning", "Tower check timeout - Moving to next action") 
                             break 
                        end
                    end
                    
                elseif Action.Type == "Upgrade" then
                    local t = FindTowerByNumber(Action.TowerNumber)
                    
                    if t then 
                        ReplicatedStorage.Functions.UpgradeTower:InvokeServer(t) 
                    else
                        SafeNotify("Debug", "Upgrade Fail: Tower #"..Action.TowerNumber.." not found")
                    end
                    
                elseif Action.Type == "Sell" then
                    local t = FindTowerByNumber(Action.TowerNumber)
                    if t then 
                        ReplicatedStorage.Functions.SellTower:InvokeServer(t) 
                        TowerIDToNumber[t.Name] = nil 
                        TowerNumberToID[Action.TowerNumber] = nil 
                        TowerInstanceMap[t] = nil
                        TowerPositions[Action.TowerNumber] = nil
                    end
                    
                elseif Action.Type == "Ability" then
                    local t = FindTowerByNumber(Action.TowerNumber)
                    if t then 
                        if Action.Action == "ChangeTowerMode" then 
                            ReplicatedStorage.Functions.ChangeTowerMode:InvokeServer(t)
                        else 
                            local remote = ReplicatedStorage.Remotes:FindFirstChild(Action.Action)
                            if remote then remote:FireServer(t) end
                        end
                    end
                end
                
                task.wait(0.1)
            end
            
            SafeNotify("Macro", "Macro Finished. Waiting for game end.")
            repeat task.wait(2) until IsInLobby() or not State.IsReplaying
        end
    end
end

-- // UI CONSTRUCTION //
local tabGroups = { TabGroup1 = Window:TabGroup() }
local tabs = {
    Main = tabGroups.TabGroup1:Tab({ Name = "Main", Image = "rbxassetid://13060262529" }),
    Macro = tabGroups.TabGroup1:Tab({ Name = "Macro", Image = "rbxassetid://9405930424" }),
    Settings = tabGroups.TabGroup1:Tab({ Name = "Settings", Image = "rbxassetid://10734950309" })
}

local sections = {
    GameControls = tabs.Main:Section({ Side = "Left" }),
    AutoFeatures = tabs.Main:Section({ Side = "Right" }),
    MacroRecorder = tabs.Macro:Section({ Side = "Left" }),
    ManageMacro = tabs.Macro:Section({ Side = "Right" })
}

Window:Dialog({
    Title = "Device Selection",
    Description = "Are You Mobile or PC?",
    Buttons = {
        {
            Name = "Mobile",
            Callback = function() Window:SetScale(0.5) end,
        },
        {
            Name = "PC",
            Callback = function() Window:SetScale(1) end,
        },
    }
})


-- MACRO RECORDER
sections.MacroRecorder:Header({ Name = "Macro Recorder" })

sections.MacroRecorder:Input({
    Name = "Macro Name",
    Placeholder = "Name",
    AcceptedCharacters = "All",
    Callback = function(input)
        State.MacroName = input
    end,
}, "MacroNameInput")

sections.MacroRecorder:Dropdown({
    Name = "Macro Type",
    Multi = false,
    Required = true,
    Options = {"Index", "Hybrid"},
    Default = "Index",
    Callback = function(Value)
        State.RecordingMode = Value
    end,
}, "MacroTypeConfig")

local RecordingToggle = sections.MacroRecorder:Toggle({
    Name = "Record Macro",
    Default = false,
    Callback = function(value)
        if value then
            if State.MacroName == "" then
                SafeNotify("Error", "Enter name first!")
                return
            end
            State.IsRecording = true
            State.CurrentMacro = {}
            State.GameStart = os.time()
            clearTowerTracking()
            SafeNotify("Recording", "Started recording: " .. State.MacroName)
        else
            State.IsRecording = false
            SaveMacro(State.MacroName, State.CurrentMacro)
            SafeNotify("Saved", "Macro saved successfully.")
        end
    end,
}, "RecordMacroToggle")

-- PLAYBACK SECTION
local MacroDrop = sections.ManageMacro:Dropdown({
    Name = "Select to Play",
    Options = RefreshMacroList(),
    Default = "nil",
    Callback = function(val) State.SelectedMacroToPlay = val end 
})

sections.ManageMacro:Toggle({ 
    Name = "Play Loop", 
    Default = false, 
    Callback = function(val) 
        State.IsReplaying = val 
        if val then task.spawn(PlayMacroLoop) end 
    end 
})

-- DELETE SECTION
local DeleteDrop = sections.ManageMacro:Dropdown({
    Name = "Select to Delete",
    Options = RefreshMacroList(),
    Default = "Select",
    Callback = function(val) State.SelectedMacroToDelete = val end 
})

local function UpdateDropdowns()
    local list = RefreshMacroList()
    MacroDrop:ClearOptions()
    MacroDrop:InsertOptions(list)
    DeleteDrop:ClearOptions()
    DeleteDrop:InsertOptions(list)
end

sections.ManageMacro:Button({ 
    Name = "Refresh Lists", 
    Callback = function() 
        UpdateDropdowns()
        SafeNotify("Refreshed", "Updated macro lists.")
    end 
})

sections.ManageMacro:Button({ 
    Name = "Delete Macro", 
    Callback = function() 
        if not State.SelectedMacroToDelete then 
            SafeNotify("Error", "Select a macro!")
            return 
        end
        Window:Dialog({
            Title = "Delete Macro",
            Description = "Delete " .. State.SelectedMacroToDelete .. "?",
            Buttons = {
                {
                    Name = "Yes",
                    Callback = function()
                        local path = FolderPath .. "/" .. State.SelectedMacroToDelete .. ".json"
                        if isfile(path) then
                            delfile(path)
                            SafeNotify("Success", "Deleted.")
                            UpdateDropdowns()
                        end
                    end,
                },
                {Name = "Cancel"}
            }
        })
    end 
})

-- STORY & MAIN (Consolidated)
sections.GameControls:Header({ Name = "Story Mode Auto Join" })
local stagesList = {} for i = 1, 15 do table.insert(stagesList, "Stage " .. i) end
sections.GameControls:Dropdown({ Name = "Select Mode", Options = {"Story", "Sukuna"}, Default = "Story", Callback = function(v) State.SelectedMode = v end })
sections.GameControls:Dropdown({ Name = "Select Stage", Options = stagesList, Default = "Stage 1", Callback = function(v) State.SelectedStage = tonumber(v:match("%d+")) end })
sections.GameControls:Dropdown({ Name = "Select Difficulty", Options = {"Normal", "HellMode"}, Default = "Normal", Callback = function(v) State.SelectedDifficulty = v end })

sections.GameControls:Toggle({ Name = "Auto Join Story", Default = false, Callback = function(v) State.AutoJoin = v if v then task.spawn(RunAutoJoin) end end })
sections.AutoFeatures:Toggle({ Name = "Auto Start Game", Default = false, Callback = function(v) State.AutoStart = v end })

sections.GameControls:Header({ Name = "Controls" })
sections.GameControls:Toggle({ Name = "Auto Skip", Default = false, Callback = function(v) State.AutoSkip = v if v then task.spawn(function() while State.AutoSkip do if IsInGame() then ReplicatedStorage.Remotes.AutoSkip:FireServer() end task.wait(2) end end) end end })
sections.AutoFeatures:Toggle({ Name = "Auto Replay", Default = false, Callback = function(v) State.AutoReplay = v if v then task.spawn(function() while State.AutoReplay do if IsInGame() then local gui = LocalPlayer.PlayerGui:FindFirstChild("GameGui") if gui and gui:FindFirstChild("EndScreen") and gui.EndScreen.Visible then ReplicatedStorage.Events.Replay:FireServer() task.wait(5) end end task.wait(1) end end) end end })
tabs.Settings:InsertConfigSection("Left")
SafeNotify("Success", "CrazyHub Loaded")
