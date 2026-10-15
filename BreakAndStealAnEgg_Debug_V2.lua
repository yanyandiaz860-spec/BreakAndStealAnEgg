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
local state = { running = true, farming = false, breaking = false, attempts = 0, logs = {} }
-- Save original location for manual return only; never return automatically.
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

local function eggRarityRank(egg)
    local r = egg:GetAttribute("Rarity") or egg:GetAttribute("EggRarity")
    if not r then
        local value = egg:FindFirstChild("Rarity")
        if value and value:IsA("StringValue") then r = value.Value end
    end
    for i, label in ipairs(RARITIES) do
        if tostring(r):lower() == label:lower() then return i end
    end
    return nil -- Never pretend a zone number is a confirmed rarity.
end

local function bestEgg()
    local builds = getZoneBuilds()
    if not builds then return nil end
    local speed = getPlayerSpeed()
    local candidates, bestScore = {}, -math.huge

    for _, zone in ipairs(builds:GetChildren()) do
        local number = tonumber(zone.Name:match("^Zone(%d+)$"))
        local folder = number and zone:FindFirstChild("Eggs")
        local gate = number and ZONE_SPEED[number]
        if folder and (not speed or not gate or speed >= gate) then
            for _, egg in ipairs(folder:GetChildren()) do
                if worldCFrame(egg) then
                    local rarity = eggRarityRank(egg)
                    -- Prefer confirmed rarities. Otherwise prefer highest zone
                    -- as a fallback only: it does NOT establish egg rarity.
                    local score = rarity and (10000 + rarity) or number
                    if score > bestScore then
                        candidates, bestScore = {{egg = egg, rarity = rarity, zone = number}}, score
                    elseif score == bestScore then
                        table.insert(candidates, {egg = egg, rarity = rarity, zone = number})
                    end
                end
            end
        end
    end
    if #candidates == 0 then return nil end
    local selected = candidates[math.random(#candidates)]
    return selected.egg, selected.rarity, selected.zone
end

local function powerOf(tool)
    for _, key in ipairs({"Power", "BreakPower", "Damage"}) do
        local value = tool:GetAttribute(key)
        if tonumber(value) then return tonumber(value) end
        local child = tool:FindFirstChild(key)
        if child and (child:IsA("NumberValue") or child:IsA("IntValue")) then
            return child.Value
        end
    end
    return nil -- Unknown, NOT 0. Server break power cannot be assumed.
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
    table.sort(tools, function(a, b)
        local pa, pb = powerOf(a), powerOf(b)
        if pa and pb then return pa > pb end
        if pa then return true end
        if pb then return false end
        return a.Parent == char and b.Parent ~= char
    end)
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

local function nearbyCollectionPrompt(egg, origin)
    -- Do not indiscriminately activate other nearby prompts (base, shop, etc.).
    local function suitable(prompt)
        if not prompt.Enabled then return false end
        local description = (prompt.Name .. " " .. prompt.ActionText .. " " .. prompt.ObjectText):lower()
        return description:find("collect", 1, true)
            or description:find("grab", 1, true)
            or description:find("pick up", 1, true)
            or description:find("pickup", 1, true)
    end
    if egg.Parent then
        for _, desc in ipairs(egg:GetDescendants()) do
            if desc:IsA("ProximityPrompt") and suitable(desc) then return desc end
        end
    end
    local closest, nearest = nil, 9
    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj:IsA("ProximityPrompt") and suitable(obj) then
            local parent = obj.Parent
            local parentModel = parent and parent:FindFirstAncestorOfClass("Model")
            local position = parent and (parent:IsA("BasePart") and parent.Position
                or (parentModel and parentModel:GetPivot().Position))
            if position and (position - origin).Magnitude < nearest then
                closest, nearest = obj, (position - origin).Magnitude
            end
        end
    end
    return closest
end

local function collectPrompt(prompt)
    if type(fireproximityprompt) ~= "function" then
        return false, "Delta does not expose fireproximityprompt"
    end
    local ok, err = pcall(function() fireproximityprompt(prompt) end)
    return ok, err
end

-- Delta-friendly debug interface: visible logs without requiring a console.
local gui = Instance.new("ScreenGui")
gui.Name = "HighestRarityEggFarmDebug"
gui.ResetOnSpawn = false
gui.Parent = playerGui
state.gui = gui

local frame = Instance.new("Frame")
frame.Size = UDim2.fromOffset(330, 345)
frame.Position = UDim2.new(0, 12, 0.23, 0)
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
    label.TextSize = 13
    label.Font = Enum.Font.Gotham
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.TextTruncate = Enum.TextTruncate.AtEnd
    label.Parent = frame
    return label
end

textLabel("Egg Farm | V2: no auto-return / no auto-sell", 7, 25)
local status = textLabel("Idle. Farm OFF by default.", 115, 23)
local detail = textLabel("Target: none | Pickaxe: none", 139, 23)
local output = Instance.new("ScrollingFrame")
output.Name = "DebugLog"
output.Size = UDim2.new(1, -20, 0, 130)
output.Position = UDim2.fromOffset(10, 166)
output.BackgroundColor3 = Color3.fromRGB(12, 15, 23)
output.BorderSizePixel = 0
output.ScrollBarThickness = 4
output.AutomaticCanvasSize = Enum.AutomaticSize.Y
output.CanvasSize = UDim2.fromOffset(0, 0)
output.Parent = frame
Instance.new("UICorner", output).CornerRadius = UDim.new(0, 6)
local layout = Instance.new("UIListLayout")
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Padding = UDim.new(0, 2)
layout.Parent = output

local function log(message, level)
    local line = string.format("[%s] %s", os.date("%H:%M:%S"), tostring(message))
    if level == "ERROR" then warn("[EGG DEBUG] " .. line)
    else print("[EGG DEBUG] " .. line) end
    if not state.running then return end
    local label = Instance.new("TextLabel")
    label.BackgroundTransparency = 1
    label.Size = UDim2.new(1, -8, 0, 30)
    label.AutomaticSize = Enum.AutomaticSize.Y
    label.TextWrapped = true
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.TextYAlignment = Enum.TextYAlignment.Top
    label.TextSize = 11
    label.Font = Enum.Font.Code
    label.TextColor3 = level == "ERROR" and Color3.fromRGB(255, 140, 140) or Color3.fromRGB(188, 221, 200)
    label.Text = line
    label.Parent = output
    table.insert(state.logs, label)
    if #state.logs > 32 then
        local oldest = table.remove(state.logs, 1)
        if oldest then oldest:Destroy() end
    end
    task.defer(function()
        if output.Parent then
            output.CanvasPosition = Vector2.new(0, layout.AbsoluteContentSize.Y)
        end
    end)
end

local function addToggle(name, x, property)
    local button = Instance.new("TextButton")
    button.Size = UDim2.new(0.5, -15, 0, 34)
    button.Position = UDim2.fromOffset(x, 38)
    button.BackgroundColor3 = Color3.fromRGB(64, 70, 90)
    button.TextColor3 = Color3.new(1, 1, 1)
    button.Font = Enum.Font.GothamBold
    button.TextSize = 12
    button.Parent = frame
    Instance.new("UICorner", button).CornerRadius = UDim.new(0, 6)
    local function update()
        button.Text = name .. ": " .. (state[property] and "ON" or "OFF")
    end
    button.MouseButton1Click:Connect(function()
        state[property] = not state[property]
        update()
        log(name .. " = " .. tostring(state[property]))
    end)
    update()
    return update
end
local refreshFarm = addToggle("Auto Farm", 10, "farming")
local refreshBreak = addToggle("Auto Break", 170, "breaking")
task.spawn(function()
    while state.running do
        refreshFarm()
        refreshBreak()
        task.wait(0.5)
    end
end)

local stopButton = Instance.new("TextButton")
stopButton.Size = UDim2.new(1, -20, 0, 31)
stopButton.Position = UDim2.fromOffset(10, 304)
stopButton.BackgroundColor3 = Color3.fromRGB(135, 49, 49)
stopButton.TextColor3 = Color3.new(1, 1, 1)
stopButton.Font = Enum.Font.GothamBold
stopButton.TextSize = 13
stopButton.Text = "STOP SCRIPT / CLEAN UP"
stopButton.Parent = frame
Instance.new("UICorner", stopButton).CornerRadius = UDim.new(0, 6)
stopButton.MouseButton1Click:Connect(function()
    log("Manual stop and cleanup")
    state.farming = false
    state.running = false
    if gui.Parent then gui:Destroy() end
end)
log("Loaded. Farm is OFF; no actions until enabled.")
log("Zone # is NOT confirmed rarity; unknown power is NOT zero.")
log("No automatic return. Auto Break starts OFF for safe diagnosis.")

local function runEgg(egg, rank, zone)
    if not egg or not egg.Parent then return end
    state.attempts = state.attempts + 1
    local label = rank and (RARITIES[rank] .. " (confirmed)")
        or ("Zone " .. tostring(zone) .. " (rarity unknown)")
    log("Attempt #" .. state.attempts .. " on " .. egg:GetFullName())
    status.Text = "Target: " .. label .. " | " .. egg.Name
    if not approachEgg(egg) then
        log("No character root / target position", "ERROR")
        state.farming = false
        return
    end
    local eggCf = worldCFrame(egg)
    if not eggCf then
        log("Egg position not found", "ERROR")
        state.farming = false
        return
    end
    local position = eggCf.Position
    local tool = equipBestPickaxe()
    detail.Text = "Pickaxe: " .. (tool and tool.Name or "NONE") .. " | power: " ..
        (tool and (tostring(powerOf(tool) or "unknown")) or "unknown")
    log("Selected " .. label .. "; tool=" .. (tool and tool.Name or "none") ..
        "; observed power=" .. (tool and tostring(powerOf(tool) or "unknown") or "unknown"))
    if not tool then
        log("No pickaxe detected; check equipped tool", "ERROR")
        state.farming = false
        return
    end
    local initialHP = healthOf(egg)
    log("Initial visible egg HP: " .. (initialHP and tostring(initialHP) or "unknown"))
    if not state.breaking then
        log("Auto Break OFF: inspect target; pausing Auto Farm")
        status.Text = "PAUSED — auto break disabled"
        state.farming = false
        return
    end

    local deadline = os.clock() + 45
    local vanished, hpDecreased = false, false
    local prompt
    local lastPositionCheck = 0
    while state.running and state.farming and os.clock() < deadline do
        if os.clock() - lastPositionCheck > 1.0 then
            lastPositionCheck = os.clock()
            local root = characterRoot()
            if not root then
                state.farming = false
                log("Character lost while targeting egg; farm paused", "ERROR")
                return
            end
            local distance = (root.Position - position).Magnitude
            if distance > 35 then
                state.farming = false
                log(string.format("Character moved %.0f studs away. Possible server snapback; farm paused", distance), "ERROR")
                return
            end
        end
        local hp = egg.Parent and healthOf(egg) or nil
        if initialHP and hp and hp < initialHP then hpDecreased = true end
        if not egg.Parent or (hp and hp <= 0) then
            vanished = true
            break
        end
        prompt = nearbyCollectionPrompt(egg, position)
        if prompt then
            log("Collection-style prompt appeared near target")
            break
        end
        tool = equipBestPickaxe() or tool
        pcall(function() tool:Activate() end)
        task.wait(0.2)
    end
    if not state.running or not state.farming then return end

    log("Break result: egg gone/HP<=0=" .. tostring(vanished)
        .. "; measured HP decrease=" .. tostring(hpDecreased))
    if vanished or prompt then
        for _ = 1, 16 do
            if not state.running or not state.farming then return end
            prompt = nearbyCollectionPrompt(egg, position)
            if prompt then break end
            task.wait(0.25)
        end
    end
    if prompt then
        local ok, err = collectPrompt(prompt)
        log("Prompt request: " .. (ok and "sent (collection NOT confirmed)" or ("FAILED: " .. tostring(err))), ok and nil or "ERROR")
    elseif vanished then
        log("Egg disappeared, but no matching collection prompt found")
    else
        log("45s timeout: no verified break / collection; remaining near egg", "ERROR")
    end

    -- Intentionally pause here. Do not return to base or change targets unless
    -- we have evidence of actual pickup/carrying, which is not exposed yet.
    state.farming = false
    status.Text = "PAUSED — inspect egg/collection"
    log("PAUSED at egg. Check whether animal was collected; no auto-return.")
end

task.spawn(function()
    while state.running do
        if state.farming then
            local egg, rank, zone = bestEgg()
            if egg then
                local ok, err = pcall(runEgg, egg, rank, zone)
                if not ok then
                    state.farming = false
                    log("runEgg failed: " .. tostring(err), "ERROR")
                end
            else
                status.Text = "No eligible eggs found"
                if not state.lastMissing or os.clock() - state.lastMissing > 8 then
                    state.lastMissing = os.clock()
                    log("No eggs; check zone access / streaming / Build path", "ERROR")
                end
                task.wait(1.5)
            end
        else
            task.wait(0.3)
        end
        task.wait(0.25)
    end
end)
