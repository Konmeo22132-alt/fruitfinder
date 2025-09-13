-- main.lua (SAFE FPS / safe operations, config must be provided outside via getgenv().Config)
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
local FRUITS = Config.Fruits or {}
local HOP_OLD = Config.HopOldServer or false
local TWEENSPEED = 350

local totalFruit = 0
local hopping = false
local hoppingDots = ""
local flying = false
local lastRespawn = 0

-- safe helpers
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

-- auto team (safe)
safeCall(function()
    if (TEAM == "Pirates" or TEAM == "Marines") and ReplicatedStorage:FindFirstChild("Remotes") and ReplicatedStorage.Remotes:FindFirstChild("CommF_") then
        safeCall(function() ReplicatedStorage.Remotes.CommF_:InvokeServer("SetTeam", TEAM) end)
    end
end)

-- safer FPS boost (do not destroy Texture/Decal; only hide or disable where safe)
if FPSBOOST then
    safeCall(function() SoundService.Volume = 0 end)
    safeCall(function() settings().Rendering.QualityLevel = Enum.QualityLevel.Level02 end)

    for _, obj in ipairs(workspace:GetDescendants()) do
        -- skip player models or unsafe paths
        if isDescendantOfPlayer(obj) then
            -- skip player's character objects
        else
            local okName = true
            if type(obj.Name) == "string" and tostring(obj.Name):sub(1,1) == "_" then okName = false end
            if not okName then continue end
            if isUnsafePath(obj) then continue end

            if obj:IsA("ParticleEmitter") or obj:IsA("Trail") or obj:IsA("Beam") then
                pcall(function() obj.Enabled = false end)
            elseif obj:IsA("Decal") then
                pcall(function() if obj.Transparency ~= nil then obj.Transparency = 1 end end)
            elseif obj:IsA("Texture") then
                pcall(function() if obj.Transparency ~= nil then obj.Transparency = 1 end end)
            elseif obj:IsA("MeshPart") then
                pcall(function()
                    obj.Material = Enum.Material.SmoothPlastic
                    if obj:FindFirstChild("TextureID") ~= nil then
                        -- many MeshPart use TextureID property directly; set safely
                        pcall(function() obj.TextureID = "" end)
                    end
                    obj.Reflectance = 0
                end)
            elseif obj:IsA("BasePart") then
                pcall(function()
                    obj.Material = Enum.Material.SmoothPlastic
                    obj.Reflectance = 0
                end)
            end
        end
    end
end

-- notification
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

-- parse prefix from "Name-Name"
local function serverNameToPrefix(name)
    if type(name) ~= "string" then return name end
    local parts = string.split(name, "-")
    return parts[1] or name
end

-- find fruits: prefer ones from FRUITS; also accept unknown models that contain "fruit"
local function findFruitsInWorkspace()
    local found = {}
    -- iterate workspace children first (lighter)
    for _, child in ipairs(workspace:GetChildren()) do
        -- skip engine/world origin & effect containers & enemies
        local cf = tostring(child.Name):lower()
        if cf:sub(1,1) == "_" then continue end
        if cf:find("enemies") or cf:find("effectcontainer") then continue end

        for _, obj in ipairs(child:GetDescendants()) do
            if (obj:IsA("Model") or obj:IsA("Tool")) and obj:FindFirstChild("Handle") then
                if isDescendantOfPlayer(obj) then
                    -- skip
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

-- move to handle safely
local function safeTweenToTarget(handleCFrame)
    if not Player or not Player.Character then return end
    local hrp = Player.Character:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    local pos = (typeof(handleCFrame) == "CFrame" and handleCFrame.Position) or (typeof(handleCFrame) == "Vector3" and handleCFrame) 
    if not pos then return end
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

-- try store fruits that match FRUITS list
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

-- safe respawn with cooldown
local function safeRespawn()
    if tick() - lastRespawn < 4 then return end
    lastRespawn = tick()
    pcall(function()
        if Player and Player.LoadCharacter then
            Player:LoadCharacter()
            -- wait for HRP briefly
            local timeout = tick() + 8
            while tick() < timeout do
                if Player.Character and Player.Character:FindFirstChild("HumanoidRootPart") then break end
                task.wait(0.1)
            end
        elseif Player.Character and Player.Character:FindFirstChild("Humanoid") then
            pcall(function() Player.Character:BreakJoints() end)
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

-- hop server (prefer old & low population if HOP_OLD true)
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

-- Main loop (lighter frequency)
task.spawn(function()
    task.wait(5)
    while task.wait(1.0) do  -- slower to reduce stress on client
        if not Player or not Player.Character then continue end
        local fruits = findFruitsInWorkspace()
        if #fruits > 0 then
            table.sort(fruits, function(a,b)
                local ah = a:FindFirstChild("Handle") local bh = b:FindFirstChild("Handle")
                if not ah or not bh then return false end
                local hrp = Player.Character and Player.Character:FindFirstChild("HumanoidRootPart")
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
            pcall(function() StarterGui:SetCore("SendNotification", {Title = "HuneIPA - Fruit Finder", Text = "Find {"..tostring(totalFruit).." } fruit on this server", Duration = 4}) end)
            -- if still multiple fruits -> safe respawn and continue
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
