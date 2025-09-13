-- main.lua (SAFE version) - Config MUST be set outside (getgenv().Config = {...})
local Config = getgenv().Config or {}
local Players = game:GetService("Players")
local Player = Players.LocalPlayer
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService = game:GetService("TeleportService")
local TweenService = game:GetService("TweenService")
local StarterGui = game:GetService("StarterGui")
local CoreGui = game:GetService("CoreGui")
local SoundService = game:GetService("SoundService")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

local TEAM = Config.Team or "Pirates"
local FPSBOOST = Config.FPSBOOST or false
local FPS_MINIMAL = (Config.FPS_MINIMAL == nil) and true or Config.FPS_MINIMAL
local FRUITS = Config.Fruits or {}
local HOP_OLD = Config.HopOldServer or false
local TWEENSPEED = Config.TweenSpeed or 350
local DEBUG = Config.Debug or false
local USE_RESPAWN = (Config.UseRespawn == nil) and true or Config.UseRespawn

local totalFruit = 0
local hopping = false
local hoppingDots = ""
local flying = false
local lastRespawn = 0

local function safeCall(fn, ...)
    local ok, res = pcall(fn, ...)
    return ok, res
end

local function isDescendantOfPlayer(obj)
    if not obj then return false end
    local anc = obj
    while anc and anc ~= workspace do
        if Players:GetPlayerFromCharacter(anc) then return true end
        anc = anc.Parent
    end
    return false
end

local function isUnsafePath(obj)
    if not obj then return true end
    local full = tostring(obj:GetFullName()):lower()
    if full:find("replicatedstorage") or full:find("effectcontainer") or full:find("_worldorigin") or full:find("enemies") or full:find("terrain") then
        return true
    end
    return false
end

-- Auto-select team (safe)
safeCall(function()
    if (TEAM == "Pirates" or TEAM == "Marines")
        and ReplicatedStorage:FindFirstChild("Remotes")
        and ReplicatedStorage.Remotes:FindFirstChild("CommF_") then
        safeCall(function() ReplicatedStorage.Remotes.CommF_:InvokeServer("SetTeam", TEAM) end)
    end
end)

-- Safer FPS boost: only disable emitters and hide decal/texture (no destructive changes)
if FPSBOOST then
    safeCall(function() SoundService.Volume = 0 end)
    safeCall(function() settings().Rendering.QualityLevel = Enum.QualityLevel.Level02 end)
    if FPS_MINIMAL then
        for _, obj in ipairs(workspace:GetDescendants()) do
            if isDescendantOfPlayer(obj) then continue end
            if isUnsafePath(obj) then continue end
            if obj:IsA("ParticleEmitter") or obj:IsA("Trail") or obj:IsA("Beam") then
                pcall(function() obj.Enabled = false end)
                if DEBUG then warn("[FPS] Disabled emitter:", obj:GetFullName()) end
            elseif obj:IsA("Decal") then
                pcall(function() if obj.Transparency ~= nil then obj.Transparency = 1 end end)
                if DEBUG then warn("[FPS] Hid decal:", obj:GetFullName()) end
            elseif obj:IsA("Texture") then
                pcall(function() if obj.Transparency ~= nil then obj.Transparency = 1 end end)
                if DEBUG then warn("[FPS] Hid texture:", obj:GetFullName()) end
            end
        end
    else
        -- Still conservative: don't modify MeshPart/BasePart properties to avoid breaking game scripts
        for _, obj in ipairs(workspace:GetDescendants()) do
            if isDescendantOfPlayer(obj) then continue end
            if isUnsafePath(obj) then continue end
            if obj:IsA("ParticleEmitter") or obj:IsA("Trail") or obj:IsA("Beam") then
                pcall(function() obj.Enabled = false end)
                if DEBUG then warn("[FPS] Disabled emitter:", obj:GetFullName()) end
            end
        end
    end
end

-- Notify load
safeCall(function()
    StarterGui:SetCore("SendNotification", {Title="HuneIPA - Fruit Finder", Text="Load successfully", Duration=4})
end)

-- UI
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "FruitFinderUI"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.Parent = CoreGui

local label = Instance.new("TextLabel")
label.Size = UDim2.new(1,0,0,200)
label.Position = UDim2.new(0,0,0.4,0)
label.BackgroundTransparency = 1
label.TextColor3 = Color3.fromRGB(0,255,0)
label.Font = Enum.Font.SourceSansBold
label.TextSize = 26
label.TextStrokeTransparency = 0
label.TextYAlignment = Enum.TextYAlignment.Top
label.Parent = screenGui

local function UpdateUI(status, fruitName, distance)
    local text = "HunelPA Hub - Fruit Finder\n"
    text = text .. "Player in server: " .. #Players:GetPlayers() .. "/12\n"
    if status == "Collecting" and fruitName then
        text = text .. "Status: Collecting " .. tostring(fruitName):lower() .. " (" .. math.floor(distance) .. "m)\n"
    elseif status == "Hopping" then
        text = text .. "Status: Hopping" .. hoppingDots .. "\n"
    else
        text = text .. "Status: Idle\n"
    end
    text = text .. "JobID: " .. tostring(game.JobId) .. "\n"
    text = text .. "Total fruit: {" .. tostring(totalFruit) .. "}\n"
    label.Text = text
end

spawn(function()
    while task.wait(0.5) do
        if hopping then
            if hoppingDots == "" then hoppingDots="." elseif hoppingDots=="." then hoppingDots=".." elseif hoppingDots==".." then hoppingDots="..." else hoppingDots="" end
        else hoppingDots="" end
    end
end)

-- parse prefix of "Name-Name"
local function serverNameToPrefix(name)
    if type(name) ~= "string" then return name end
    local parts = string.split(name, "-")
    return parts[1] or name
end

-- find fruits: prefer FRUITS, but also accept unknown models with "fruit" in name
local function findFruitsInWorkspace()
    local found = {}
    -- iterate children (lighter than full GetDescendants loop)
    for _, child in ipairs(workspace:GetChildren()) do
        -- skip likely engine/world containers
        local low = tostring(child.Name):lower()
        if low:sub(1,1) == "_" then continue end
        if low:find("enemies") or low:find("effectcontainer") then continue end

        for _, obj in ipairs(child:GetDescendants()) do
            if (obj:IsA("Model") or obj:IsA("Tool")) and obj:FindFirstChild("Handle") then
                if isDescendantOfPlayer(obj) then
                    -- skip player's models
                else
                    local matched = false
                    for _, serverName in ipairs(FRUITS) do
                        local prefix = serverNameToPrefix(serverName)
                        if prefix and string.find(string.lower(obj.Name), string.lower(prefix), 1, true) then
                            matched = true
                            break
                        end
                    end
                    if matched or string.find(string.lower(obj.Name), "fruit", 1, true) then
                        table.insert(found, obj)
                    end
                end
            end
        end
    end
    return found
end

-- safe move to handle (teleport if close, tween if far)
local function safeTweenToTarget(handleCFrame)
    if not Player or not Player.Character then return end
    local hrp = Player.Character:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    local pos = nil
    if typeof(handleCFrame) == "CFrame" then pos = handleCFrame.Position
    elseif typeof(handleCFrame) == "Vector3" then pos = handleCFrame
    else return end
    local target = CFrame.new(pos + Vector3.new(0,3,0))
    local distance = (hrp.Position - pos).Magnitude
    if distance <= 300 then
        pcall(function() hrp.CFrame = target end)
        return
    end
    local tweenInfo = TweenInfo.new(distance / TWEENSPEED, Enum.EasingStyle.Linear)
    local ok, tween = pcall(function() return TweenService:Create(hrp, tweenInfo, {CFrame = target}) end)
    if ok and tween then
        pcall(function() tween:Play(); tween.Completed:Wait() end)
    else
        pcall(function() hrp.CFrame = target end)
    end
end

-- try to store fruits that match FRUITS list
local function storeAllFruitOnce()
    local backpack = Player and Player:FindFirstChild("Backpack")
    local char = Player and Player.Character
    for _, serverName in ipairs(FRUITS) do
        local prefix = serverNameToPrefix(serverName)
        if not prefix then continue end
        local candidates = { prefix .. " Fruit", prefix }
        for _, cname in ipairs(candidates) do
            local obj = (backpack and backpack:FindFirstChild(cname)) or (char and char:FindFirstChild(cname))
            if obj then
                pcall(function()
                    if ReplicatedStorage and ReplicatedStorage:FindFirstChild("Remotes") and ReplicatedStorage.Remotes:FindFirstChild("CommF_") then
                        ReplicatedStorage.Remotes.CommF_:InvokeServer("StoreFruit", serverName, obj)
                    end
                end)
                break
            end
        end
    end
end

-- safe respawn (cooldown)
local function safeRespawn()
    if not USE_RESPAWN then return end
    if tick() - lastRespawn < 4 then return end
    lastRespawn = tick()
    pcall(function()
        if Player and Player.LoadCharacter then
            Player:LoadCharacter()
            local timeout = tick() + 8
            while tick() < timeout do
                if Player.Character and Player.Character:FindFirstChild("HumanoidRootPart") then break end
                task.wait(0.1)
            end
            if DEBUG then warn("[Respawn] Character reloaded") end
        else
            if Player.Character and Player.Character:FindFirstChild("Humanoid") then
                pcall(function() Player.Character:BreakJoints() end)
            end
        end
    end)
end

-- flying while hopping
local function startFlying()
    if flying then return end
    flying = true
    spawn(function()
        while flying do
            if Player and Player.Character and Player.Character:FindFirstChild("HumanoidRootPart") then
                local hrp = Player.Character:FindFirstChild("HumanoidRootPart")
                pcall(function() hrp.CFrame = hrp.CFrame + Vector3.new(0,10,0) end)
            end
            task.wait(0.5)
        end
    end)
end
local function stopFlying() flying = false end

-- Hop server (prefer old & low population if enabled)
local function HopServer()
    hopping = true
    UpdateUI("Hopping")
    if HOP_OLD then
        local ok, res = pcall(function()
            return HttpService:JSONDecode(game:HttpGet("https://games.roblox.com/v1/games/"..game.PlaceId.."/servers/Public?sortOrder=Asc&limit=100"))
        end)
        if ok and type(res) == "table" and res.data then
            for _, s in ipairs(res.data) do
                if type(s.playing) == "number" and s.playing < 6 then
                    local uptime = s.uptime or 0
                    if uptime > 7200 and s.id and tostring(s.id) ~= tostring(game.JobId) then
                        pcall(function() TeleportService:TeleportToPlaceInstance(game.PlaceId, s.id, Player) end)
                        return
                    end
                end
            end
        end
    end
    pcall(function() TeleportService:Teleport(game.PlaceId, Player) end)
end

-- Main loop (1s loop to reduce noise)
task.spawn(function()
    task.wait(5)
    while task.wait(1.0) do
        if not Player or not Player.Character then continue end
        local fruits = findFruitsInWorkspace()
        if #fruits > 0 then
            table.sort(fruits, function(a,b)
                local ah, bh = a:FindFirstChild("Handle"), b:FindFirstChild("Handle")
                if not ah or not bh then return false end
                local hrp = Player.Character:FindFirstChild("HumanoidRootPart")
                if not hrp then return false end
                return (hrp.Position - ah.Position).Magnitude < (hrp.Position - bh.Position).Magnitude
            end)
            local target = fruits[1]
            if not target or not target:FindFirstChild("Handle") then continue end
            local hrp = Player.Character:FindFirstChild("HumanoidRootPart")
            if not hrp then continue end
            local dist = (hrp.Position - target.Handle.Position).Magnitude
            UpdateUI("Collecting", target.Name, dist)
            safeTweenToTarget(target.Handle.CFrame)
            local startTick = tick()
            spawn(function() task.wait(2); startFlying() end)
            while tick() - startTick < 5 do
                storeAllFruitOnce()
                local hrp2 = Player.Character and Player.Character:FindFirstChild("HumanoidRootPart")
                if hrp2 and target and target:FindFirstChild("Handle") then
                    UpdateUI("Collecting", target.Name, (hrp2.Position - target.Handle.Position).Magnitude)
                end
                task.wait(0.5)
            end
            stopFlying()
            totalFruit = totalFruit + 1
            pcall(function() StarterGui:SetCore("SendNotification", {Title = "HuneIPA - Fruit Finder", Text = "Find {"..tostring(totalFruit).."} fruit on this server", Duration = 4}) end)
            local remaining = findFruitsInWorkspace()
            if #remaining > 1 then
                safeRespawn()
                task.wait(2)
            else
                HopServer()
                break
            end
        else
            UpdateUI("Idle")
        end
    end
end)
