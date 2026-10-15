-- Break and Steal an Egg | V5 - Speed 500 + Break Input Diagnostics
-- Auto Farm and all teleport logic REMOVED. No auto sell.
-- WalkSpeed and Tool:Activate are client-side requests; game/server rules can override them.
-- No client-side override of server-authoritative break damage is claimed.
-- Experimental: not verified inside Break and Steal an Egg / Delta.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Stop any old V1-V3 workers/GUI, then stop the previous V4 if re-executed.
local oldFarm = rawget(_G, "BSAE_HighestRarity")
if type(oldFarm) == "table" then
    oldFarm.running = false
    oldFarm.farming = false
    oldFarm.breaking = false
    if oldFarm.gui then pcall(function() oldFarm.gui:Destroy() end) end
end
local previous = rawget(_G, "BSAE_SpeedBreak")
if type(previous) == "table" and type(previous.cleanup) == "function" then
    pcall(previous.cleanup)
end

local state = {
    running = true, speedOn = false, breakOn = false,
    speed = 32, minSpeed = 8, maxSpeed = 500, breakMode = 2, -- 1=Tool, 2=Screen tap, 3=Both
    inputAvailable = nil, lastInputError = nil,
    minimized = false, logs = {}, connections = {},
    lastHumanoid = nil, originalSpeed = nil, busy = false,
}
_G.BSAE_SpeedBreak = state

local function humanoid()
    local c = player.Character
    return c and c:FindFirstChildOfClass("Humanoid")
end
local function root()
    local c = player.Character
    return c and c:FindFirstChild("HumanoidRootPart")
end
local function clampSpeed(value)
    return math.clamp(math.floor((tonumber(value) or state.speed) + 0.5), state.minSpeed, state.maxSpeed)
end

local function positionOf(item)
    if item:IsA("BasePart") then return item.Position end
    if item:IsA("Model") then
        local ok, pivot = pcall(function() return item:GetPivot() end)
        if ok then return pivot.Position end
    end
    return nil
end
local function nearbyEgg()
    local r = root()
    local builds = workspace:FindFirstChild("Build")
    local zones = builds and builds:FindFirstChild("ZoneBuilds")
    if not r or not zones then return nil, nil end
    local chosen, bestDist = nil, 18
    for _, zone in ipairs(zones:GetChildren()) do
        local eggs = zone:FindFirstChild("Eggs")
        if eggs then
            for _, item in ipairs(eggs:GetChildren()) do
                -- Prefer a visible egg; avoid 'Nest' placeholders unless no egg exists nearby.
                if not item.Name:lower():find("nest", 1, true) then
                    local pos = positionOf(item)
                    if pos then
                        local dist = (r.Position - pos).Magnitude
                        if dist < bestDist then
                            chosen, bestDist = item, dist
                        end
                    end
                end
            end
        end
    end
    return chosen, bestDist
end
local function readValue(instance, names)
    if not instance then return nil end
    for _, key in ipairs(names) do
        local n = tonumber(instance:GetAttribute(key))
        if n then return n end
        local child = instance:FindFirstChild(key, true)
        if child and (child:IsA("NumberValue") or child:IsA("IntValue")) then
            return child.Value
        end
    end
    return nil
end
local function eggHP(egg)
    return readValue(egg, {"Health", "HP", "HitPoints", "Durability"})
end
local function pickaxePower(tool)
    return readValue(tool, {"BreakPower", "Power", "Damage"})
end
local function equippedPickaxe()
    local c = player.Character
    if not c then return nil end
    for _, item in ipairs(c:GetChildren()) do
        if item:IsA("Tool") and item.Name:lower():find("pickaxe", 1, true) then return item end
    end
    local pack, h = player:FindFirstChildOfClass("Backpack"), humanoid()
    if pack and h then
        for _, item in ipairs(pack:GetChildren()) do
            if item:IsA("Tool") and item.Name:lower():find("pickaxe", 1, true) then
                pcall(function() h:EquipTool(item) end)
                return item
            end
        end
    end
    return nil
end

local gui = Instance.new("ScreenGui")
gui.Name = "EggSpeedBreakV5"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = playerGui
state.gui = gui

local frame = Instance.new("Frame")
frame.Name = "Panel"
frame.Size = UDim2.fromOffset(350, 360)
frame.Position = UDim2.new(0, 18, 0.22, 0)
frame.BackgroundColor3 = Color3.fromRGB(23, 27, 39)
frame.BorderSizePixel = 0
frame.Parent = gui
Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 10)

local function button(parent, text, x, y, w, h)
    local b = Instance.new("TextButton")
    b.BackgroundColor3 = Color3.fromRGB(58, 71, 96)
    b.TextColor3 = Color3.fromRGB(245, 248, 255)
    b.Font = Enum.Font.GothamBold
    b.TextSize = 13
    b.Text = text
    b.Size = UDim2.fromOffset(w, h)
    b.Position = UDim2.fromOffset(x, y)
    b.Parent = parent
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
    return b
end
local function label(parent, text, x, y, w, h, size)
    local l = Instance.new("TextLabel")
    l.BackgroundTransparency = 1
    l.TextColor3 = Color3.fromRGB(228, 234, 247)
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.TextTruncate = Enum.TextTruncate.AtEnd
    l.Font = Enum.Font.Gotham
    l.TextSize = size or 12
    l.Text = text
    l.Position = UDim2.fromOffset(x, y)
    l.Size = UDim2.fromOffset(w, h)
    l.Parent = parent
    return l
end

local header = Instance.new("Frame")
header.Size = UDim2.new(1, 0, 0, 40)
header.BackgroundTransparency = 1
header.Active = true
header.Parent = frame
label(header, "Egg Tools | Speed + Break V5", 12, 8, 240, 24, 13)
local minimize = button(header, "−", 266, 5, 34, 30)
local close = button(header, "×", 306, 5, 34, 30)
close.BackgroundColor3 = Color3.fromRGB(150, 62, 65)

local body = Instance.new("Frame")
body.Size = UDim2.new(1, 0, 1, -40)
body.Position = UDim2.fromOffset(0, 40)
body.BackgroundTransparency = 1
body.Parent = frame

label(body, "SPEED BOOSTER (WalkSpeed)", 12, 5, 326, 19, 12)
local speedToggle = button(body, "Speed: OFF", 12, 29, 111, 36)
local minus = button(body, "−", 132, 29, 40, 36)
local speedBox = Instance.new("TextBox")
speedBox.Size = UDim2.fromOffset(70, 36)
speedBox.Position = UDim2.fromOffset(179, 29)
speedBox.BackgroundColor3 = Color3.fromRGB(36, 42, 60)
speedBox.TextColor3 = Color3.new(1, 1, 1)
speedBox.Font = Enum.Font.GothamBold
speedBox.TextSize = 15
speedBox.ClearTextOnFocus = false
speedBox.Text = tostring(state.speed)
speedBox.Parent = body
Instance.new("UICorner", speedBox).CornerRadius = UDim.new(0, 6)
local plus = button(body, "+", 257, 29, 40, 36)
label(body, "Range 8–500; +/− changes by 10", 12, 71, 323, 18, 11)

label(body, "BREAKING (nearby only; no teleport)", 12, 98, 326, 18, 12)
local breakToggle = button(body, "Auto Break: OFF", 12, 122, 205, 35)
local methodButton = button(body, "Mode: Screen", 224, 122, 114, 35)
local targetLabel = label(body, "Target: walk beside an egg", 12, 168, 326, 18, 12)
local hpLabel = label(body, "Egg HP: unknown | Pickaxe power: unknown", 12, 190, 326, 18, 12)
local timingLabel = label(body, "Attack timing: idle (server damage unchanged)", 12, 212, 326, 18, 11)

local logs = Instance.new("ScrollingFrame")
logs.Size = UDim2.fromOffset(326, 73)
logs.Position = UDim2.fromOffset(12, 237)
logs.BackgroundColor3 = Color3.fromRGB(11, 14, 23)
logs.BorderSizePixel = 0
logs.ScrollBarThickness = 4
logs.CanvasSize = UDim2.fromOffset(0, 0)
logs.AutomaticCanvasSize = Enum.AutomaticSize.Y
logs.Parent = body
Instance.new("UICorner", logs).CornerRadius = UDim.new(0, 6)
local list = Instance.new("UIListLayout")
list.SortOrder = Enum.SortOrder.LayoutOrder
list.Parent = logs

local function log(msg, isError)
    local text = "[" .. os.date("%H:%M:%S") .. "] " .. tostring(msg)
    if isError then warn("[Egg V5] " .. text) else print("[Egg V5] " .. text) end
    if not state.running then return end
    local l = Instance.new("TextLabel")
    l.Size = UDim2.new(1, -6, 0, 18)
    l.AutomaticSize = Enum.AutomaticSize.Y
    l.TextWrapped = true
    l.BackgroundTransparency = 1
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.TextYAlignment = Enum.TextYAlignment.Top
    l.Font = Enum.Font.Code
    l.TextSize = 11
    l.TextColor3 = isError and Color3.fromRGB(255, 150, 154) or Color3.fromRGB(176, 232, 201)
    l.Text = text
    l.Parent = logs
    table.insert(state.logs, l)
    if #state.logs > 18 then
        local oldest = table.remove(state.logs, 1)
        oldest:Destroy()
    end
    task.defer(function()
        if logs.Parent then logs.CanvasPosition = Vector2.new(0, list.AbsoluteContentSize.Y) end
    end)
end

local function setMinimized(value)
    state.minimized = value
    body.Visible = not value
    frame.Size = UDim2.fromOffset(350, value and 40 or 360)
    minimize.Text = value and "+" or "−"
end
minimize.MouseButton1Click:Connect(function() setMinimized(not state.minimized) end)

-- Drag from the header, supports touch and mouse (works while minimized).
local dragging, dragStart, frameStart, dragInput = false, nil, nil, nil
local dragStartConnection = header.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dragging, dragStart, frameStart = true, input.Position, frame.Position
    end
end)
local dragEndConnection = UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dragging = false
    end
end)
local dragMoveConnection = UserInputService.InputChanged:Connect(function(input)
    if not dragging or not dragStart or not frameStart then return end
    if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
        local d = input.Position - dragStart
        frame.Position = UDim2.new(frameStart.X.Scale, frameStart.X.Offset + d.X,
            frameStart.Y.Scale, frameStart.Y.Offset + d.Y)
    end
end)
state.connections = {dragStartConnection, dragEndConnection, dragMoveConnection}

local function restoreSpeed()
    if state.lastHumanoid and state.lastHumanoid.Parent and state.originalSpeed then
        pcall(function() state.lastHumanoid.WalkSpeed = state.originalSpeed end)
    end
    state.lastHumanoid = nil
    state.originalSpeed = nil
end
local function updateSpeedUI()
    speedToggle.Text = "Speed: " .. (state.speedOn and "ON" or "OFF")
    speedBox.Text = tostring(state.speed)
end
local function applySpeed()
    local h = humanoid()
    if not h then return end
    if state.lastHumanoid ~= h then
        restoreSpeed()
        state.lastHumanoid = h
        state.originalSpeed = h.WalkSpeed
    end
    if state.speedOn then
        pcall(function() h.WalkSpeed = state.speed end)
    end
end
speedToggle.MouseButton1Click:Connect(function()
    state.speedOn = not state.speedOn
    if state.speedOn then applySpeed() else restoreSpeed() end
    updateSpeedUI()
    log("Speed booster " .. (state.speedOn and "ON" or "OFF"))
end)
minus.MouseButton1Click:Connect(function()
    state.speed = clampSpeed(state.speed - 10)
    updateSpeedUI()
    if state.speedOn then applySpeed() end
end)
plus.MouseButton1Click:Connect(function()
    state.speed = clampSpeed(state.speed + 10)
    updateSpeedUI()
    if state.speedOn then applySpeed() end
end)
speedBox.FocusLost:Connect(function()
    state.speed = clampSpeed(speedBox.Text)
    updateSpeedUI()
    if state.speedOn then applySpeed() end
end)

breakToggle.MouseButton1Click:Connect(function()
    state.breakOn = not state.breakOn
    breakToggle.Text = "Auto Break: " .. (state.breakOn and "ON" or "OFF")
    log("Auto Break " .. (state.breakOn and "ON" or "OFF"))
end)

local function attackInterval(hp, power)
    -- Modest cadence only; not a break-power multiplier.
    if hp and power and power > 0 and hp / power > 100 then return 0.42 end
    if hp and hp >= 10000 then return 0.45 end
    return 0.55
end

local modeNames = {"Tool", "Screen", "Both"}
methodButton.MouseButton1Click:Connect(function()
    state.breakMode = state.breakMode % 3 + 1
    methodButton.Text = "Mode: " .. modeNames[state.breakMode]
    log("Break mode: " .. modeNames[state.breakMode])
end)

local function tapScreenCenter()
    -- This is an input simulation, NOT a server damage call.
    -- It may be unsupported by an executor or ignored by the game.
    local camera = workspace.CurrentCamera
    if not camera then return false, "No camera" end
    local viewport = camera.ViewportSize
    local x, y = math.floor(viewport.X / 2), math.floor(viewport.Y / 2)
    local ok, err = pcall(function()
        local vim = game:GetService("VirtualInputManager")
        vim:SendMouseButtonEvent(x, y, 0, true, game, 0)
        task.wait(0.045)
        vim:SendMouseButtonEvent(x, y, 0, false, game, 0)
    end)
    return ok, err
end

local function tryBreak(tool)
    local worked = false
    local errorText = nil
    if state.breakMode == 1 or state.breakMode == 3 then
        if not tool then return false, "No pickaxe equipped" end
        local ok, err = pcall(function() tool:Activate() end)
        worked = worked or ok
        if not ok then errorText = tostring(err) end
    end
    if state.breakMode == 2 or state.breakMode == 3 then
        local ok, err = tapScreenCenter()
        worked = worked or ok
        if not ok then errorText = tostring(err) end
    end
    return worked, errorText
end

local function cleanup()
    if not state.running then return end
    state.running, state.breakOn, state.speedOn = false, false, false
    restoreSpeed()
    for _, c in ipairs(state.connections) do pcall(function() c:Disconnect() end) end
    if gui.Parent then gui:Destroy() end
    if rawget(_G, "BSAE_SpeedBreak") == state then _G.BSAE_SpeedBreak = nil end
end
state.cleanup = cleanup
close.MouseButton1Click:Connect(cleanup)

log("V5 ready: max speed 500; no Auto Farm, teleport, or auto-sell.")
log("Mode: Screen simulates a center-screen click if supported; aim at egg.")
log("Game/server may ignore simulated input. No artificial damage power.")

-- Speed maintenance (normal Humanoid property; server may override).
task.spawn(function()
    while state.running do
        if state.speedOn then applySpeed() end
        task.wait(0.6)
    end
end)

-- Breaking assist: character must already be near an egg and face/aim at it.
-- If server/game does not accept these client actions, there is no claimed damage.
task.spawn(function()
    local idleLogAt = 0
    while state.running do
        if not state.breakOn then
            task.wait(0.35)
        else
            local egg, dist = nearbyEgg()
            if not egg then
                targetLabel.Text = "Target: no egg within 18 studs"
                timingLabel.Text = "Walk to an egg; aim toward its center"
                task.wait(0.5)
            else
                local tool = equippedPickaxe()
                local hp = eggHP(egg)
                local power = pickaxePower(tool)
                local interval = attackInterval(hp, power)
                targetLabel.Text = "Target: " .. egg.Name .. " (" .. math.floor(dist) .. " studs)"
                hpLabel.Text = "Egg HP: " .. tostring(hp or "unknown") .. " | Power: " .. tostring(power or "unknown")
                timingLabel.Text = string.format("%s every %.2fs | aim at egg", modeNames[state.breakMode], interval)

                if not tool then
                    log("No pickaxe found. Equip the pickaxe before testing.", true)
                    state.breakOn = false
                    breakToggle.Text = "Auto Break: OFF"
                else
                    local firstHP = hp
                    local hits = 0
                    local observedHPDecrease = false
                    local began = os.clock()
                    local eggName = egg.Name
                    local fail = nil
                    while state.running and state.breakOn and egg.Parent and os.clock() - began < 10 do
                        local r, pos = root(), positionOf(egg)
                        if not r or not pos or (r.Position - pos).Magnitude > 18 then break end
                        local currentHP = eggHP(egg)
                        if firstHP and currentHP and currentHP < firstHP then
                            observedHPDecrease = true
                        end
                        local ok, err = tryBreak(tool)
                        if not ok then
                            fail = err or "Break input not supported"
                            break
                        end
                        hits = hits + 1
                        task.wait(interval)
                    end
                    local removed = egg.Parent == nil
                    log(string.format("%s: %d inputs, HP lowered=%s, removed=%s",
                        eggName, hits, tostring(observedHPDecrease), tostring(removed)))
                    if fail then
                        log("Input failed: " .. fail, true)
                        state.breakOn = false
                        breakToggle.Text = "Auto Break: OFF"
                    elseif not observedHPDecrease and not removed then
                        log("No VERIFIED damage; try another Mode or game's AutoSwing.", true)
                        -- Pause to avoid repeating unverified actions indefinitely.
                        state.breakOn = false
                        breakToggle.Text = "Auto Break: OFF"
                    else
                        log("Observed an egg change; keep testing to confirm collection.")
                    end
                    task.wait(0.3)
                end
            end
        end
    end
end)
