-- Break and Steal an Egg: Highest-Rarity Farm (experimental)
-- No auto-sell. Does not modify server-side Pickaxe Power.
-- Uses known Build.ZoneBuilds.ZoneN.Eggs structure from ValueHat's public script.

local Players = game:GetService("Players")
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

if _G.BSAE_HighestRarity then
    _G.BSAE_HighestRarity.running = false
    if _G.BSAE_HighestRarity.gui then
        _G.BSAE_HighestRarity.gui:Destroy()
    end
end
local state = { running = true, farming = false, breaking = true }
_G.BSAE_HighestRarity = state

local RARITIES = {
    "Common", "Uncommon", "Rare", "Epic", "Legendary",
    "Mythic", "Divine", "Cosmic", "Secret"
}
local ZONE_SPEED = { 5, 1000, 50000, 750000, 12000000,
    150000000, 1000000000, 5000000000, 25000000000 }
local PICKAXE_POWER = {
    Wooden = 1, Stone = 4, Iron = 15, Golden = 60, Diamond = 250,
    Strawberry = 1000, Cactus = 4000, Lightning = 15000,
    Candy = 60000, Rainbow = 250000, Crystal = 1e6, Demon = 4e6,
    Hacker = 15e6, UFO = 60e6, Secret = 250e6,
    Cool = 1e9, Galaxy = 5e9, Celestial = 25e9,
}

local function characterRoot()
    local char = player.Character
    return char and char:FindFirstChild("HumanoidRootPart")
end

local function getPlayerSpeed()
    local stats = player:FindFirstChild("leaderstats")
    local value = (stats and stats:FindFirstChild("Speed"))
        or player:FindFirstChild("Speed")
    local n = value and tonumber(value.Value)
    if not n then n = tonumber(player:GetAttribute("Speed")) end
    return n -- unknown speed means no automatic speed-gate filtering
end

local function worldCFrame(obj)
    if obj:IsA("BasePart") then return obj.CFrame end
    if obj:IsA("Model") then return obj:GetPivot() end
end

local function getZoneBuilds()
    local build = workspace:FindFirstChild("Build")
    return build and build:FindFirstChild("ZoneBuilds")
end

local function eggRarityRank(egg, zoneIndex)
    local r = egg:GetAttribute("Rarity") or egg:GetAttribute("EggRarity")
    if not r then
        local value = egg:FindFirstChild("Rarity")
        if value and value:IsA("StringValue") then r = value.Value end
    end
    for i, label in ipairs(RARITIES) do
        if tostring(r):lower() == label:lower() then return i end
    end
    return zoneIndex -- zone fallback: zone 9 = Secret
end

local function bestEgg()
    local builds = getZoneBuilds()
    if not builds then return nil end
    local speed = getPlayerSpeed()
    local candidates, bestRank = {}, -math.huge

    for _, zone in ipairs(builds:GetChildren()) do
        local number = tonumber(zone.Name:match("^Zone(%d+)$"))
        local folder = number and zone:FindFirstChild("Eggs")
        local gate = number and ZONE_SPEED[number]
        if folder and (not speed or not gate or speed >= gate) then
            for _, egg in ipairs(folder:GetChildren()) do
                local cf = worldCFrame(egg)
                if cf then
                    local rank = eggRarityRank(egg, number)
                    if rank > bestRank then
                        candidates, bestRank = { egg }, rank
                    elseif rank == bestRank then
                        table.insert(candidates, egg)
                    end
                end
            end
        end
    end

    if #candidates == 0 then return nil end
    return candidates[math.random(#candidates)], bestRank
end

local function powerOf(tool)
    for _, key in ipairs({"Power", "BreakPower", "Damage"}) do
        local v = tool:GetAttribute(key)
        if tonumber(v) then return tonumber(v) end
        local child = tool:FindFirstChild(key)
        if child and child:IsA("NumberValue") then return child.Value end
    end
    for name, power in pairs(PICKAXE_POWER) do
        if tool.Name:lower():find(name:lower(), 1, true) then return power end
    end
    return 0
end

local function equipBestPickaxe()
    local char = player.Character
    if not char then return nil end
    local humanoid = char:FindFirstChildOfClass("Humanoid")
    if not humanoid then return nil end

    local tools = {}
    local backpack = player:FindFirstChildOfClass("Backpack")
    for _, container in ipairs({char, backpack}) do
        if container then
            for _, child in ipairs(container:GetChildren()) do
                if child:IsA("Tool") and child.Name:lower():find("pickaxe") then
                    table.insert(tools, child)
                end
            end
        end
    end
    table.sort(tools, function(a, b) return powerOf(a) > powerOf(b) end)
    local best = tools[1]
    if best and best.Parent ~= char then
        pcall(function() humanoid:EquipTool(best) end)
    end
    return best
end

local function approachEgg(egg)
    local root = characterRoot()
    local cf = worldCFrame(egg)
    if not root or not cf then return false end
    root.CFrame = CFrame.new(cf.Position + Vector3.new(0, 3, 4), cf.Position)
    return true
end

local function healthOf(egg)
    for _, key in ipairs({"Health", "HP", "Durability", "HitPoints"}) do
        local attr = egg:GetAttribute(key)
        if type(attr) == "number" then return attr end
        local obj = egg:FindFirstChild(key, true)
        if obj and obj:IsA("NumberValue") then return obj.Value end
    end
    return nil
end

local function nearbyPrompt(egg, origin)
    -- Pet collection prompts can appear after the shell vanishes.
    local targetPrompt = egg.Parent and egg:FindFirstChildWhichIsA("ProximityPrompt", true)
    if targetPrompt and targetPrompt.Enabled then return targetPrompt end
    for _, d in ipairs(workspace:GetDescendants()) do
        if d:IsA("ProximityPrompt") and d.Enabled then
            local parent = d.Parent
            local position = parent and (parent:IsA("BasePart") and parent.Position
                or (parent:IsA("Model") and parent:GetPivot().Position))
            if position and (position - origin).Magnitude <= 9 then
                return d
            end
        end
    end
end

local function collectPrompt(prompt)
    if type(fireproximityprompt) ~= "function" then
        warn("[Egg Farm] This environment has no fireproximityprompt function.")
        return false
    end
    local ok = pcall(function() fireproximityprompt(prompt) end)
    return ok
end

local function returnToBase()
    local build = workspace:FindFirstChild("Build")
    local parts = build and build:FindFirstChild("Parts")
    local spot = parts and parts:GetChildren()[4] -- from the linked ValueHat script
    local cf = spot and worldCFrame(spot)
    local root = characterRoot()
    if root and cf then root.CFrame = cf * CFrame.new(0, 3, 0) end
end

-- Simple draggable-free, mobile-friendly controls.
local gui = Instance.new("ScreenGui")
gui.Name = "HighestRarityEggFarm"
gui.ResetOnSpawn = false
gui.Parent = playerGui
state.gui = gui

local frame = Instance.new("Frame")
frame.Size = UDim2.fromOffset(280, 160)
frame.Position = UDim2.new(0, 15, 0.38, 0)
frame.BackgroundColor3 = Color3.fromRGB(24, 26, 37)
frame.Parent = gui
Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 10)

local function textLabel(message, top, height)
    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, -20, 0, height)
    label.Position = UDim2.fromOffset(10, top)
    label.BackgroundTransparency = 1
    label.Text = message
    label.TextColor3 = Color3.new(1, 1, 1)
    label.TextSize = 14
    label.Font = Enum.Font.Gotham
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Parent = frame
    return label
end

textLabel("🥚 Highest-Rarity Egg Farm", 8, 24)
local status = textLabel("Idle · No auto-sell", 129, 25)
local function addToggle(name, top, property)
    local button = Instance.new("TextButton")
    button.Size = UDim2.new(1, -20, 0, 36)
    button.Position = UDim2.fromOffset(10, top)
    button.BackgroundColor3 = Color3.fromRGB(64, 70, 90)
    button.TextColor3 = Color3.new(1, 1, 1)
    button.Font = Enum.Font.GothamBold
    button.TextSize = 14
    button.Parent = frame
    Instance.new("UICorner", button).CornerRadius = UDim.new(0, 6)
    local function update()
        button.Text = name .. ": " .. (state[property] and "ON" or "OFF")
    end
    button.MouseButton1Click:Connect(function()
        state[property] = not state[property]
        update()
    end)
    update()
end
addToggle("Auto Farm + Collect", 40, "farming")
addToggle("Auto Break", 83, "breaking")

local function runEgg(egg, rank)
    if not approachEgg(egg) then return end
    local position = worldCFrame(egg).Position
    local label = RARITIES[rank] or ("Zone rank " .. tostring(rank))
    status.Text = "Target: " .. label .. " | " .. egg.Name

    local interval = math.max(0.11, 0.33 - rank * 0.025)
    local deadline = os.clock() + (state.breaking and (12 + rank * 6) or 2)
    local tool = equipBestPickaxe()
    while state.running and state.farming and egg.Parent and os.clock() < deadline do
        if healthOf(egg) and healthOf(egg) <= 0 then break end
        if state.breaking then
            tool = equipBestPickaxe() or tool
            if tool then pcall(function() tool:Activate() end) end
        end
        task.wait(interval)
    end

    -- Give the pet/prompt a moment to spawn, then collect it if exposed.
    for _ = 1, 12 do
        if not state.running or not state.farming then return end
        local prompt = nearbyPrompt(egg, position)
        if prompt then
            if collectPrompt(prompt) then
                task.wait(0.45)
                returnToBase()
            end
            return
        end
        task.wait(0.2)
    end
end

task.spawn(function()
    while state.running do
        if state.farming then
            local egg, rank = bestEgg()
            if egg then
                local ok, err = pcall(runEgg, egg, rank)
                if not ok then warn("[Egg Farm]", err) end
            else
                status.Text = "No eligible eggs found"
                task.wait(1.5)
            end
        else
            status.Text = "Idle · No auto-sell"
            task.wait(0.25)
        end
        task.wait(0.25)
    end
end)
