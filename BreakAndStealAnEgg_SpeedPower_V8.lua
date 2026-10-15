-- Break and Steal an Egg | V8: Split Controls and Results panels
-- For Delta / Roblox Lua executors. Experimental and UNVERIFIED in live game.
-- IMPORTANT: this changes only locally-visible numeric stats on YOUR equipped tool.
-- Roblox server may ignore/reject all such edits; actual damage is server-authoritative.
-- Do not confuse a changed client display with a confirmed 250B damage hit.
-- No teleports, auto farm, remote invocation, auto sell, or simulated AutoSwing.
-- Use the game's built-in AutoSwing. Disable/re-enable this experiment to restore stats.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Shut down previous versions if they are still present.
local old = rawget(_G, "BSAE_HighestRarity")
if type(old) == "table" then
    old.running, old.breaking, old.farming = false, false, false
    if old.gui then pcall(function() old.gui:Destroy() end) end
end
old = rawget(_G, "BSAE_SpeedBreak")
if type(old) == "table" and type(old.cleanup) == "function" then
    pcall(old.cleanup)
end
old = rawget(_G, "BSAE_SpeedPowerV8")
if type(old) == "table" and type(old.cleanup) == "function" then
    pcall(old.cleanup)
end
old = rawget(_G, "BSAE_SpeedPowerV7")
if type(old) == "table" and type(old.cleanup) == "function" then
    pcall(old.cleanup)
end

local state = {
    running = true, speedOn = false, speed = 32,
    maxSpeed = 500, minSpeed = 8, appliedSpeed = nil,
    humanoid = nil, originalSpeed = nil,
    snapbacks = 0, lastSnapback = -100,
    powerOn = false, targetPower = 250e9, targetIndex = 8,
    editedTool = nil, originals = {},
    logs = {}, connections = {}, minimized = false, resultsMinimized = false,
    lastPowerMessage = "Power test not run",
}
_G.BSAE_SpeedPowerV8 = state
-- Keep compatibility with the V4-V6 cleanup mechanism.
_G.BSAE_SpeedBreak = state

local PRESETS = {
    {"4M", 4e6}, {"10M", 10e6}, {"100M", 100e6},
    {"1B", 1e9}, {"10B", 10e9}, {"50B", 50e9},
    {"100B", 100e9}, {"250B", 250e9}
}

local function fmt(n)
    if type(n) ~= "number" then return "unknown" end
    if n >= 1e15 then return string.format("%.2fQa", n / 1e15) end
    if n >= 1e12 then return string.format("%.2fT", n / 1e12) end
    if n >= 1e9 then return string.format("%.2fB", n / 1e9) end
    if n >= 1e6 then return string.format("%.2fM", n / 1e6) end
    if n >= 1e3 then return string.format("%.2fK", n / 1e3) end
    return tostring(math.floor(n + 0.5))
end
local function parsePower(str)
    str = tostring(str or ""):gsub("%s", "")
    local num, unit = str:match("^(%d+%.?%d*)(%a*)$")
    local scalar = ({k=1e3, m=1e6, b=1e9, t=1e12, qa=1e15})[(unit or ""):lower()]
    local n = tonumber(num)
    if not n or not scalar then return nil end
    local result = n * scalar
    if result < 4e6 or result > 250e9 then return nil end
    return result
end
local function getHumanoid()
    local character = player.Character
    return character and character:FindFirstChildOfClass("Humanoid")
end
local function getRoot()
    local character = player.Character
    return character and character:FindFirstChild("HumanoidRootPart")
end
local function equippedPickaxe()
    local character = player.Character
    if not character then return nil end
    for _, child in ipairs(character:GetChildren()) do
        if child:IsA("Tool") and child.Name:lower():find("pickaxe", 1, true) then
            return child
        end
    end
    -- Unlike earlier versions, do NOT auto-equip a tool from Backpack.
    return nil
end
local function nearbyEgg()
    local root = getRoot()
    local build = workspace:FindFirstChild("Build")
    local zones = build and build:FindFirstChild("ZoneBuilds")
    if not root or not zones then return nil end
    local chosen, distance = nil, 22
    for _, zone in ipairs(zones:GetChildren()) do
        local eggs = zone:FindFirstChild("Eggs")
        if eggs then
            for _, egg in ipairs(eggs:GetChildren()) do
                if not egg.Name:lower():find("nest", 1, true) then
                    local pos = nil
                    if egg:IsA("BasePart") then
                        pos = egg.Position
                    elseif egg:IsA("Model") then
                        local ok, pivot = pcall(function() return egg:GetPivot() end)
                        if ok then pos = pivot.Position end
                    end
                    if pos then
                        local d = (root.Position - pos).Magnitude
                        if d < distance then chosen, distance = egg, d end
                    end
                end
            end
        end
    end
    return chosen, distance
end
local function readNumber(instance, keys)
    if not instance then return nil end
    for _, key in ipairs(keys) do
        local n = instance:GetAttribute(key)
        if type(n) == "number" then return n end
        local child = instance:FindFirstChild(key, true)
        if child and (child:IsA("IntValue") or child:IsA("NumberValue")) then
            return child.Value
        end
    end
    return nil
end

-- Split UI: one controls panel plus an independent results/debug window.
local gui = Instance.new("ScreenGui")
gui.Name = "BSAE_SpeedPower_V8"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = playerGui
state.gui = gui

local function corner(instance, radius)
    Instance.new("UICorner", instance).CornerRadius = UDim.new(0, radius or 9)
end
local function makePanel(name, width, height, position)
    local frame = Instance.new("Frame")
    frame.Name = name
    frame.Size = UDim2.fromOffset(width, height)
    frame.Position = position
    frame.BackgroundColor3 = Color3.fromRGB(23, 27, 39)
    frame.BorderSizePixel = 0
    frame.Active = true
    frame.Parent = gui
    corner(frame, 11)
    return frame
end
local panel = makePanel("Controls", 354, 270, UDim2.new(0, 14, 0.17, 0))
local resultsPanel = makePanel("Results", 354, 387, UDim2.new(1, -370, 0.17, 0))

local function button(parent, name, x, y, w, h)
    local b = Instance.new("TextButton")
    b.Size = UDim2.fromOffset(w, h)
    b.Position = UDim2.fromOffset(x, y)
    b.Text = name
    b.Font = Enum.Font.GothamBold
    b.TextSize = 13
    b.TextColor3 = Color3.fromRGB(245, 248, 255)
    b.BackgroundColor3 = Color3.fromRGB(57, 72, 99)
    b.Parent = parent
    corner(b, 6)
    return b
end
local function label(parent, message, x, y, w, h, size)
    local t = Instance.new("TextLabel")
    t.Size = UDim2.fromOffset(w, h)
    t.Position = UDim2.fromOffset(x, y)
    t.BackgroundTransparency = 1
    t.Font = Enum.Font.Gotham
    t.TextSize = size or 12
    t.TextXAlignment = Enum.TextXAlignment.Left
    t.TextColor3 = Color3.fromRGB(228, 234, 247)
    t.TextTruncate = Enum.TextTruncate.AtEnd
    t.Text = message
    t.Parent = parent
    return t
end
local function textbox(parent, message, x, y, w, h)
    local t = Instance.new("TextBox")
    t.Size = UDim2.fromOffset(w, h)
    t.Position = UDim2.fromOffset(x, y)
    t.BackgroundColor3 = Color3.fromRGB(35, 43, 61)
    t.TextColor3 = Color3.new(1, 1, 1)
    t.Font = Enum.Font.GothamBold
    t.TextSize = 14
    t.ClearTextOnFocus = false
    t.Text = message
    t.Parent = parent
    corner(t, 6)
    return t
end
local function makeHeader(parent)
    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(1, 0, 0, 40)
    frame.BackgroundTransparency = 1
    frame.Active = true
    frame.Parent = parent
    return frame
end
local header = makeHeader(panel)
label(header, "Egg Tools V8 | Controls", 12, 7, 248, 26, 13)
local minimizeBtn = button(header, "−", 270, 5, 34, 29)
local closeBtn = button(header, "×", 310, 5, 34, 29)
closeBtn.BackgroundColor3 = Color3.fromRGB(150, 61, 65)
local body = Instance.new("Frame")
body.Position = UDim2.fromOffset(0, 40)
body.Size = UDim2.new(1, 0, 1, -40)
body.BackgroundTransparency = 1
body.Parent = panel

label(body, "SPEED BOOSTER (8 - 500)", 12, 5, 330, 18, 12)
local speedBtn = button(body, "Speed: OFF", 12, 29, 113, 36)
local speedMinus = button(body, "−", 133, 29, 41, 36)
local speedBox = textbox(body, "32", 182, 29, 69, 36)
local speedPlus = button(body, "+", 259, 29, 40, 36)
label(body, "Gradual acceleration; server may limit speed", 12, 70, 329, 17, 10)

label(body, "LOCAL POWER TEST (4M - 250B)", 12, 96, 330, 18, 12)
local powerBtn = button(body, "Test: OFF", 12, 119, 113, 36)
local powerMinus = button(body, "−", 133, 119, 41, 36)
local powerBox = textbox(body, "250B", 182, 119, 69, 36)
local powerPlus = button(body, "+", 259, 119, 40, 36)
local resultsShowBtn = button(body, "Hide Results", 12, 173, 144, 35)
local resultsHint = label(body, "Results open in a separate draggable window", 165, 176, 176, 30, 10)
resultsHint.TextWrapped = true

local resultsHeader = makeHeader(resultsPanel)
label(resultsHeader, "LIVE RESULTS | V8", 12, 7, 240, 26, 13)
local resultsMinBtn = button(resultsHeader, "−", 270, 5, 34, 29)
local clearBtn = button(resultsHeader, "Clear", 307, 5, 42, 29)
clearBtn.TextSize = 10
local resultsBody = Instance.new("Frame")
resultsBody.Position = UDim2.fromOffset(0, 40)
resultsBody.Size = UDim2.new(1, 0, 1, -40)
resultsBody.BackgroundTransparency = 1
resultsBody.Parent = resultsPanel
local speedStatus = label(resultsBody, "Speed: OFF | WalkSpeed: —", 12, 5, 330, 19, 11)
local powerStatus = label(resultsBody, "Requested 250B | Test OFF", 12, 29, 330, 19, 11)
local pickaxeLabel = label(resultsBody, "Equipped: none", 12, 53, 330, 19, 11)
local statsLabel = label(resultsBody, "Local stat: unknown", 12, 76, 330, 19, 11)
local eggLabel = label(resultsBody, "Nearby egg: none", 12, 100, 330, 19, 11)
local hpLabel = label(resultsBody, "Egg HP: unknown", 12, 123, 330, 19, 11)
local testMessage = label(resultsBody, "Actual damage NOT confirmed", 12, 146, 330, 19, 11)
testMessage.TextColor3 = Color3.fromRGB(255, 198, 116)
local logFrame = Instance.new("ScrollingFrame")
logFrame.Position = UDim2.fromOffset(12, 178)
logFrame.Size = UDim2.fromOffset(330, 157)
logFrame.BackgroundColor3 = Color3.fromRGB(11, 14, 23)
logFrame.BorderSizePixel = 0
logFrame.ScrollBarThickness = 5
logFrame.ScrollingDirection = Enum.ScrollingDirection.Y
logFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
logFrame.CanvasSize = UDim2.fromOffset(0, 0)
logFrame.Parent = resultsBody
corner(logFrame, 6)
local logLayout = Instance.new("UIListLayout")
logLayout.SortOrder = Enum.SortOrder.LayoutOrder
logLayout.Parent = logFrame

local function log(message, bad)
    local line = "[" .. os.date("%H:%M:%S") .. "] " .. tostring(message)
    if bad then warn("[Egg V8] " .. line) else print("[Egg V8] " .. line) end
    if not state.running then return end
    local item = Instance.new("TextLabel")
    item.Size = UDim2.new(1, -10, 0, 20)
    item.AutomaticSize = Enum.AutomaticSize.Y
    item.TextWrapped = true
    item.Text = line
    item.Font = Enum.Font.Code
    item.TextSize = 11
    item.TextColor3 = bad and Color3.fromRGB(255, 158, 154) or Color3.fromRGB(172, 230, 199)
    item.TextXAlignment = Enum.TextXAlignment.Left
    item.TextYAlignment = Enum.TextYAlignment.Top
    item.BackgroundTransparency = 1
    item.Parent = logFrame
    table.insert(state.logs, item)
    if #state.logs > 40 then table.remove(state.logs, 1):Destroy() end
    task.defer(function()
        if logFrame.Parent then
            logFrame.CanvasPosition = Vector2.new(0, math.max(0, logLayout.AbsoluteContentSize.Y - logFrame.AbsoluteSize.Y))
        end
    end)
end
clearBtn.MouseButton1Click:Connect(function()
    for _, item in ipairs(state.logs) do
        if item.Parent then item:Destroy() end
    end
    state.logs = {}
    log("Logs cleared")
end)
local function showResults(visible)
    resultsPanel.Visible = visible
    resultsShowBtn.Text = visible and "Hide Results" or "Show Results"
end
resultsShowBtn.MouseButton1Click:Connect(function()
    showResults(not resultsPanel.Visible)
end)
resultsMinBtn.MouseButton1Click:Connect(function()
    state.resultsMinimized = not state.resultsMinimized
    resultsBody.Visible = not state.resultsMinimized
    resultsPanel.Size = UDim2.fromOffset(354, state.resultsMinimized and 40 or 387)
    resultsMinBtn.Text = state.resultsMinimized and "+" or "−"
end)

-- Power test changes existing numeric Attributes / NumberValue / IntValue locally.
-- Never generates new fake stats, never calls server remotes, and always records originals.
local NAMES = {power=true, breakpower=true, damage=true, strength=true, breakingpower=true,
    swingdamage=true, pickaxepower=true, basepower=true, basedamage=true}
local function statName(key)
    return tostring(key):lower():gsub("[^%a]", "")
end
local function restorePower()
    for i = #state.originals, 1, -1 do
        local e = state.originals[i]
        pcall(function()
            if e.kind == "Attribute" then e.object:SetAttribute(e.key, e.value)
            elseif e.object.Parent then e.object.Value = e.value end
        end)
    end
    state.originals = {}
    state.editedTool = nil
end
local function experiment(tool)
    restorePower()
    if not tool then
        state.lastPowerMessage = "Equip a pickaxe first"
        return false, state.lastPowerMessage
    end
    local changed = 0
    local found = {}
    for key, value in pairs(tool:GetAttributes()) do
        if NAMES[statName(key)] and type(value) == "number" then
            local ok = pcall(function() tool:SetAttribute(key, state.targetPower) end)
            if ok then
                table.insert(state.originals, {kind="Attribute", object=tool, key=key, value=value})
                table.insert(found, key .. "=" .. fmt(value))
                changed = changed + 1
            end
        end
    end
    -- Scan only the equipped tool's value instances, never global game scripts/remotes.
    for _, item in ipairs(tool:GetDescendants()) do
        if (item:IsA("NumberValue") or item:IsA("IntValue")) and NAMES[statName(item.Name)] then
            local oldValue = item.Value
            local ok = pcall(function() item.Value = state.targetPower end)
            if ok then
                table.insert(state.originals, {kind="Value", object=item, value=oldValue})
                table.insert(found, item.Name .. "=" .. fmt(oldValue))
                changed = changed + 1
            end
        end
    end
    if changed == 0 then
        state.lastPowerMessage = "No editable damage stat found on tool"
        return false, "No matching numeric damage stat on equipped Tool"
    end
    state.editedTool = tool
    state.lastPowerMessage = "Local stat changed; actual damage unverified"
    log("Local test: " .. changed .. " stat(s) set to " .. fmt(state.targetPower))
    log("Original values: " .. table.concat(found, ", "))
    log("Check EGG HP per swing; changed local stat != server damage.", true)
    return true, "Local override attempted"
end
local function powerUI()
    powerBtn.Text = state.powerOn and "Test: ON" or "Test: OFF"
    powerBox.Text = fmt(state.targetPower):gsub("%.00", "")
    powerStatus.Text = "Requested " .. fmt(state.targetPower) .. " | Test " .. (state.powerOn and "ON" or "OFF")
end
local function updatePower(raw)
    local parsed = parsePower(raw)
    if not parsed then
        log("Enter power 4M - 250B (example: 250B)", true)
        powerUI()
        return
    end
    state.targetPower = parsed
    for idx, preset in ipairs(PRESETS) do
        if preset[2] == parsed then state.targetIndex = idx; break end
    end
    powerUI()
    if state.powerOn then
        local ok, msg = experiment(equippedPickaxe())
        if not ok then state.powerOn = false; powerUI(); log(msg, true) end
    end
end
powerMinus.MouseButton1Click:Connect(function()
    state.targetIndex = math.max(1, state.targetIndex - 1)
    updatePower(PRESETS[state.targetIndex][1])
end)
powerPlus.MouseButton1Click:Connect(function()
    state.targetIndex = math.min(#PRESETS, state.targetIndex + 1)
    updatePower(PRESETS[state.targetIndex][1])
end)
powerBox.FocusLost:Connect(function() updatePower(powerBox.Text) end)
powerBtn.MouseButton1Click:Connect(function()
    if state.powerOn then
        state.powerOn = false
        restorePower()
        state.lastPowerMessage = "Power test OFF. No damage override active"
        log("Power test OFF. Original local values restored.")
    else
        local ok, msg = experiment(equippedPickaxe())
        state.powerOn = ok
        if not ok then log(msg, true) end
    end
    powerUI()
end)

-- Speed, preserves working V6 approach (client WalkSpeed, gradual ramp-up).
local function restoreSpeed()
    if state.humanoid and state.humanoid.Parent and state.originalSpeed then
        pcall(function() state.humanoid.WalkSpeed = state.originalSpeed end)
    end
    state.humanoid, state.originalSpeed, state.appliedSpeed = nil, nil, nil
end
local function updateSpeedUI()
    speedBtn.Text = state.speedOn and "Speed: ON" or "Speed: OFF"
    speedBox.Text = tostring(state.speed)
end
local function applySpeed()
    local h = getHumanoid()
    if not h then return end
    if h ~= state.humanoid then
        restoreSpeed()
        state.humanoid, state.originalSpeed = h, h.WalkSpeed
    end
    if state.speedOn then
        local current = state.appliedSpeed or state.originalSpeed or 16
        state.appliedSpeed = math.min(state.speed, current + 12)
        pcall(function() h.WalkSpeed = state.appliedSpeed end)
    end
end
local function setSpeed(v)
    state.speed = math.clamp(math.floor((tonumber(v) or state.speed) + 0.5), state.minSpeed, state.maxSpeed)
    if state.speedOn then
        state.appliedSpeed = math.min(state.appliedSpeed or state.speed, state.speed)
        applySpeed()
    end
    updateSpeedUI()
end
speedPlus.MouseButton1Click:Connect(function() setSpeed(state.speed + 10) end)
speedMinus.MouseButton1Click:Connect(function() setSpeed(state.speed - 10) end)
speedBox.FocusLost:Connect(function() setSpeed(speedBox.Text) end)
speedBtn.MouseButton1Click:Connect(function()
    state.speedOn = not state.speedOn
    if state.speedOn then
        state.snapbacks = 0
        state.appliedSpeed = nil
        applySpeed()
    else
        restoreSpeed()
    end
    updateSpeedUI()
    log("Speed " .. (state.speedOn and "ON" or "OFF") .. " (target " .. state.speed .. ")")
end)

local function cleanup()
    if not state.running then return end
    state.running = false
    state.powerOn, state.speedOn = false, false
    restorePower()
    restoreSpeed()
    for _, c in ipairs(state.connections) do pcall(function() c:Disconnect() end) end
    if gui.Parent then gui:Destroy() end
    if rawget(_G, "BSAE_SpeedPowerV8") == state then _G.BSAE_SpeedPowerV8 = nil end
    if rawget(_G, "BSAE_SpeedBreak") == state then _G.BSAE_SpeedBreak = nil end
end
state.cleanup = cleanup
closeBtn.MouseButton1Click:Connect(cleanup)
minimizeBtn.MouseButton1Click:Connect(function()
    state.minimized = not state.minimized
    body.Visible = not state.minimized
    panel.Size = UDim2.fromOffset(354, state.minimized and 40 or 270)
    minimizeBtn.Text = state.minimized and "+" or "−"
end)
-- Both windows can be dragged independently on touch or mouse.
local function enableDrag(frame, dragHeader)
    local dragging, dragStart, frameStart, dragInput = false, nil, nil, nil
    state.connections[#state.connections + 1] = dragHeader.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging, dragStart, frameStart, dragInput = true, input.Position, frame.Position, input
        end
    end)
    state.connections[#state.connections + 1] = UserInputService.InputEnded:Connect(function(input)
        if input == dragInput or (dragInput and input.UserInputType == dragInput.UserInputType) then
            dragging, dragInput = false, nil
        end
    end)
    state.connections[#state.connections + 1] = UserInputService.InputChanged:Connect(function(input)
        if not dragging or not dragStart or not frameStart then return end
        if input.UserInputType ~= Enum.UserInputType.MouseMovement and input ~= dragInput then return end
        local delta = input.Position - dragStart
        frame.Position = UDim2.new(frameStart.X.Scale, frameStart.X.Offset + delta.X,
            frameStart.Y.Scale, frameStart.Y.Offset + delta.Y)
    end)
end
enableDrag(panel, header)
enableDrag(resultsPanel, resultsHeader)

log("V8 loaded: controls and live results are now separate windows.")
log("Power test 250B is experimental; local stat edits may be ignored by server.")
log("Use native AutoSwing; watch egg HP in game to verify real damage.")

-- Speed upkeep and observed speed status.
task.spawn(function()
    while state.running do
        if state.speedOn then applySpeed() end
        local h = getHumanoid()
        if h then
            speedStatus.Text = string.format("Speed target %d | Applied %s | Actual %.0f",
                state.speed, fmt(state.appliedSpeed), h.WalkSpeed)
        else speedStatus.Text = "Speed: waiting for character" end
        task.wait(0.6)
    end
end)
-- Monitor tool and nearby egg. No attacks or remote calls are made.
task.spawn(function()
    while state.running do
        local tool = equippedPickaxe()
        if state.powerOn and tool ~= state.editedTool then
            local ok, msg = experiment(tool)
            if not ok then state.powerOn = false; powerUI(); log(msg, true) end
        end
        pickaxeLabel.Text = "Equipped: " .. (tool and tool.Name or "none (equip manually)")
        testMessage.Text = state.lastPowerMessage
        if state.powerOn then
            statsLabel.Text = "Local test " .. fmt(state.targetPower) .. " | SERVER NOT VERIFIED"
        else
            statsLabel.Text = "Local stat: " .. fmt(readNumber(tool, {"Power", "BreakPower", "Damage", "Strength"}))
        end
        local egg, dist = nearbyEgg()
        eggLabel.Text = egg and string.format("Nearby egg: %s (%.0f studs)", egg.Name, dist) or "Nearby egg: none within 22 studs"
        local hp = readNumber(egg, {"Health", "HP", "HitPoints", "Durability"})
        hpLabel.Text = "Client-visible egg HP: " .. fmt(hp)
        task.wait(0.8)
    end
end)
-- Heuristic rubber-band detection adapted from V6; conservative backoff.
task.spawn(function()
    local samples = {}
    local previousPos, previousT, previousRoot = nil, nil, nil
    while state.running do
        task.wait(0.12)
        local r = getRoot()
        if not state.speedOn or not r or r ~= previousRoot then
            samples = {}
            previousPos, previousT, previousRoot = r and r.Position or nil, os.clock(), r
        else
            local now = os.clock()
            local p = r.Position
            local dt = math.max(0.03, now - (previousT or now))
            local jump = previousPos and (p - previousPos).Magnitude or 0
            local returned = false
            for _, sample in ipairs(samples) do
                if now - sample.t > 0.9 and now - sample.t < 3.2
                   and (p - sample.p).Magnitude < 18
                   and previousPos and (previousPos - sample.p).Magnitude > 48 then
                    returned = true
                    break
                end
            end
            local largeJump = jump > math.max(48, (state.appliedSpeed or state.speed) * dt * 1.8)
            if largeJump and returned and now - state.lastSnapback > 1.5 then
                state.lastSnapback = now
                state.snapbacks = state.snapbacks + 1
                setSpeed(math.max(16, math.floor(state.speed * 0.65)))
                log(string.format("Possible snapback (%.0f studs); speed reduced to %d", jump, state.speed), true)
                samples = {}
                if state.snapbacks >= 3 then
                    state.speedOn = false
                    restoreSpeed()
                    updateSpeedUI()
                    log("Speed OFF after 3 possible corrections; test 30-60.", true)
                end
            end
            samples[#samples+1] = {p=p, t=now}
            while #samples > 0 and now - samples[1].t > 3.2 do
                table.remove(samples, 1)
            end
            previousPos, previousT = p, now
        end
    end
end)
