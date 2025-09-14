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
local TWEENSPEED = Config.TweenSpeed or 350
local DEBUG = Config.Debug or false
local USE_RESPAWN = Config.UseRespawn == nil and true or Config.UseRespawn

local totalFruit = 0
local hopping = false
local hoppingDots = ""
local flying = false
local lastRespawn = 0

local function safePcall(fn, ...)
    return pcall(fn, ...)
end

local function isPlayerDescendant(obj)
    if not obj then return false end
    local cur = obj
    while cur and cur ~= workspace do
        if Players:GetPlayerFromCharacter(cur) then
            return true
        end
        cur = cur.Parent
    end
    return false
end

local function splitServerName(name)
    if type(name) ~= "string" then return tostring(name) end
    local parts = string.split(name, "-")
    return parts[1] or name
end

local function buildPrefixMap()
    local map = {}
    for _, v in ipairs(FRUITS) do
        if type(v) == "string" then
            local pref = splitServerName(v)
            map[pref:lower()] = v
        elseif type(v) == "table" then
            local display = v[1] or v[2] or v[3]
            local server = v[2] or v[1]
            local pref = splitServerName(server or display)
            map[pref:lower()] = server or display
        end
    end
    return map
end

local PrefixMap = buildPrefixMap()

local function autoSelectTeam()
    safePcall(function()
        if (TEAM == "Pirates" or TEAM == "Marines") and ReplicatedStorage and ReplicatedStorage:FindFirstChild("Remotes") and ReplicatedStorage.Remotes:FindFirstChild("CommF_") then
            safePcall(function() ReplicatedStorage.Remotes.CommF_:InvokeServer("SetTeam", TEAM) end)
        end
    end)
end

local function safeFPSBoost()
    if not FPSBOOST then return end
    safePcall(function()
        pcall(function() SoundService.Volume = 0 end)
        pcall(function() settings().Rendering.QualityLevel = Enum.QualityLevel.Level02 end)
    end)
    for _, obj in ipairs(workspace:GetDescendants()) do
        if isPlayerDescendant(obj) then
            continue
        end
        local name = tostring(obj.Name):lower()
        if name:sub(1,1) == "_" then
            continue
        end
        if obj:IsA("ParticleEmitter") or obj:IsA("Trail") or obj:IsA("Beam") then
            pcall(function() obj.Enabled = false end)
            if DEBUG then warn("FPS: disabled emitter", obj:GetFullName()) end
        elseif obj:IsA("Decal") then
            pcall(function() if obj.Transparency ~= nil then obj.Transparency = 1 end end)
            if DEBUG then warn("FPS: hid decal", obj:GetFullName()) end
        elseif obj:IsA("Texture") then
            pcall(function() if obj.Transparency ~= nil then obj.Transparency = 1 end end)
            if DEBUG then warn("FPS: hid texture", obj:GetFullName()) end
        elseif obj:IsA("MeshPart") then
            pcall(function()
                obj.Material = Enum.Material.SmoothPlastic
                if obj.TextureID ~= nil then
                    pcall(function() obj.TextureID = "" end)
                end
                obj.Reflectance = 0
            end)
            if DEBUG then warn("FPS: adjusted meshpart", obj:GetFullName()) end
        elseif obj:IsA("BasePart") then
            pcall(function() obj.Material = Enum.Material.SmoothPlastic; obj.Reflectance = 0 end)
        end
    end
end

local function sendNotification(t, m, d)
    safePcall(function()
        StarterGui:SetCore("SendNotification", {Title = t or "Fruit Finder", Text = m or "", Duration = d or 4})
    end)
end

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

local function setUI(status, fruitName, distance)
    local text = "HunelPA Hub - Fruit Finder\n"
    text = text .. "Players in server: " .. tostring(#Players:GetPlayers()) .. "/12\n"
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
            if hoppingDots == "" then hoppingDots = "." elseif hoppingDots == "." then hoppingDots = ".." elseif hoppingDots == ".." then hoppingDots = "..." else hoppingDots = "" end
        else
            hoppingDots = ""
        end
    end
end)

local function findAllFruits()
    local found = {}
    local seen = {}
    for _, obj in ipairs(workspace:GetDescendants()) do
        if not obj then continue end
        if (obj:IsA("Model") or obj:IsA("Tool")) and obj:FindFirstChild("Handle") then
            if isPlayerDescendant(obj) then continue end
            local nm = tostring(obj.Name)
            local lnm = nm:lower()
            local matched = false
            for pref, serverName in pairs(PrefixMap) do
                if pref and lnm:find(pref, 1, true) then
                    matched = true
                    break
                end
            end
            if matched or lnm:find("fruit", 1, true) then
                if not seen[obj] then
                    table.insert(found, obj)
                    seen[obj] = true
                    if DEBUG then warn("Found fruit candidate:", nm, obj:GetFullName()) end
                end
            end
        end
    end
    return found
end

local function getNearestFruit(list)
    if not list or #list == 0 then return nil end
    if not Player or not Player.Character or not Player.Character:FindFirstChild("HumanoidRootPart") then return list[1] end
    local hrp = Player.Character.HumanoidRootPart
    local nearest = nil
    local nd = math.huge
    for _, f in ipairs(list) do
        if f and f:IsDescendantOf(workspace) and f:FindFirstChild("Handle") then
            local dist = (hrp.Position - f.Handle.Position).Magnitude
            if dist < nd then
                nd = dist
                nearest = f
            end
        end
    end
    return nearest
end

local function teleportOrTweenTo(cframe)
    if not Player or not Player.Character then return end
    local hrp = Player.Character:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    local pos = (typeof(cframe) == "CFrame" and cframe.Position) or (typeof(cframe) == "Vector3" and cframe) or nil
    if not pos then return end
    local dist = (hrp.Position - pos).Magnitude
    local target = CFrame.new(pos + Vector3.new(0,3,0))
    if dist <= 300 then
        pcall(function() hrp.CFrame = target end)
        return
    end
    local tweenInfo = TweenInfo.new(dist / TWEENSPEED, Enum.EasingStyle.Linear)
    local ok, tween = pcall(function() return TweenService:Create(hrp, tweenInfo, {CFrame = target}) end)
    if ok and tween then
        pcall(function() tween:Play(); tween.Completed:Wait() end)
    else
        pcall(function() hrp.CFrame = target end)
    end
end

local function storeAllKnownFruitsOnce()
    local backpack = Player and Player:FindFirstChild("Backpack")
    local char = Player and Player.Character
    for _, serverName in ipairs(FRUITS) do
        local prefix = splitServerName(serverName)
        if not prefix then continue end
        local candidates = { prefix .. " Fruit", prefix }
        for _, cname in ipairs(candidates) do
            local obj = (backpack and backpack:FindFirstChild(cname)) or (char and char:FindFirstChild(cname))
            if obj then
                safePcall(function()
                    if ReplicatedStorage and ReplicatedStorage:FindFirstChild("Remotes") and ReplicatedStorage.Remotes:FindFirstChild("CommF_") then
                        ReplicatedStorage.Remotes.CommF_:InvokeServer("StoreFruit", serverName, obj)
                    end
                end)
                break
            end
        end
    end
end

local function storeAnyFruitOnce()
    local backpack = Player and Player:FindFirstChild("Backpack")
    local char = Player and Player.Character
    for _, obj in ipairs((backpack and backpack:GetChildren()) or {}) do
        if type(obj.Name) == "string" and obj.Name:lower():find("fruit") then
            safePcall(function()
                if ReplicatedStorage and ReplicatedStorage:FindFirstChild("Remotes") and ReplicatedStorage.Remotes:FindFirstChild("CommF_") then
                    ReplicatedStorage.Remotes.CommF_:InvokeServer("StoreFruit", obj.Name, obj)
                end
            end)
        end
    end
    for _, obj in ipairs((char and char:GetChildren()) or {}) do
        if type(obj.Name) == "string" and obj.Name:lower():find("fruit") then
            safePcall(function()
                if ReplicatedStorage and ReplicatedStorage:FindFirstChild("Remotes") and ReplicatedStorage.Remotes:FindFirstChild("CommF_") then
                    ReplicatedStorage.Remotes.CommF_:InvokeServer("StoreFruit", obj.Name, obj)
                end
            end)
        end
    end
end

local function startFlyUpDelayed()
    spawn(function()
        task.wait(2)
        startFlying = true
    end)
end

local function startFlyingLoop()
    if flying then return end
    flying = true
    spawn(function()
        while flying do
            if Player and Player.Character and Player.Character:FindFirstChild("HumanoidRootPart") then
                pcall(function() Player.Character.HumanoidRootPart.CFrame = Player.Character.HumanoidRootPart.CFrame + Vector3.new(0,10,0) end)
            end
            task.wait(0.5)
        end
    end)
end

local function stopFlyingLoop()
    flying = false
end

local function safeRespawnCharacter()
    if not USE_RESPAWN then return end
    if tick() - lastRespawn < 4 then return end
    lastRespawn = tick()
    safePcall(function()
        if Player and Player.LoadCharacter then
            Player:LoadCharacter()
            local timeout = tick() + 8
            while tick() < timeout do
                if Player and Player.Character and Player.Character:FindFirstChild("HumanoidRootPart") then break end
                task.wait(0.1)
            end
        else
            if Player and Player.Character and Player.Character:FindFirstChild("Humanoid") then
                pcall(function() Player.Character:BreakJoints() end)
            end
        end
    end)
end

local function apiListServers(cursor)
    local place = tostring(game.PlaceId)
    local base = "https://games.roblox.com/v1/games/" .. place .. "/servers/Public?sortOrder=Asc&limit=100"
    local url = base .. (cursor and "&cursor=" .. tostring(cursor) or "")
    local ok, raw = pcall(function() return game:HttpGet(url) end)
    if not ok or not raw then return nil end
    local success, json = pcall(function() return HttpService:JSONDecode(raw) end)
    if success then return json end
    return nil
end

local function hopPreferOldLow()
    hopping = true
    setUI("Hopping")
    local cursor = nil
    for page = 1, 6 do
        local data = apiListServers(cursor)
        if data and data.data then
            for _, s in ipairs(data.data) do
                local playing = tonumber(s.playing) or 0
                local maxp = tonumber(s.maxPlayers) or 0
                local id = s.id
                local uptime = s.uptime or 0
                if id and tostring(id) ~= tostring(game.JobId) and playing < maxp and playing < 6 and uptime > 7200 then
                    pcall(function() TeleportService:TeleportToPlaceInstance(game.PlaceId, id, Player) end)
                    return
                end
            end
            cursor = data.nextPageCursor
            if not cursor then break end
            task.wait(0.2)
        else
            break
        end
    end
    pcall(function() TeleportService:Teleport(game.PlaceId, Player) end)
end

local function hopPreferLowPlayers()
    hopping = true
    setUI("Hopping")
    local bestServer = nil
    local bestPlayers = math.huge
    local cursor = nil
    for page = 1, 6 do
        local data = apiListServers(cursor)
        if data and data.data then
            for _, s in ipairs(data.data) do
                local playing = tonumber(s.playing) or 0
                local maxp = tonumber(s.maxPlayers) or 0
                local id = s.id
                if id and tostring(id) ~= tostring(game.JobId) and playing < maxp then
                    if playing < bestPlayers then
                        bestPlayers = playing
                        bestServer = id
                    end
                    if playing == 0 then
                        pcall(function() TeleportService:TeleportToPlaceInstance(game.PlaceId, id, Player) end)
                        return
                    end
                end
            end
            cursor = data.nextPageCursor
            if not cursor then break end
            task.wait(0.2)
        else
            break
        end
    end
    if bestServer then
        pcall(function() TeleportService:TeleportToPlaceInstance(game.PlaceId, bestServer, Player) end)
        return
    end
    pcall(function() TeleportService:Teleport(game.PlaceId, Player) end)
end

local function HopServer()
    if HOP_OLD then
        hopPreferOldLow()
    else
        hopPreferLowPlayers()
    end
end

local function waitForCharacter()
    if Player and Player.Character and Player.Character:FindFirstChild("HumanoidRootPart") then return end
    local connection
    local done = false
    local function onCharAdded(char)
        connection:Disconnect()
        done = true
    end
    connection = Player.CharacterAdded:Connect(onCharAdded)
    local timeout = tick() + 12
    while not done and tick() < timeout do
        task.wait(0.1)
    end
    if Player and Player.Character and Player.Character:FindFirstChild("HumanoidRootPart") then return end
end

local function init()
    autoSelectTeam()
    safeFPSBoost()
    sendNotification("HuneIPA - Fruit Finder", "Load successfully", 4)
end

init()

task.spawn(function()
    waitForCharacter()
    task.wait(1)
    while true do
        if not Player or not Player.Character then
            waitForCharacter()
            task.wait(1)
        end
        local fruits = findAllFruits()
        if fruits and #fruits > 0 then
            local target = getNearestFruit(fruits)
            if target and target:FindFirstChild("Handle") and Player and Player.Character and Player.Character:FindFirstChild("HumanoidRootPart") then
                local hrp = Player.Character.HumanoidRootPart
                local dist = (hrp.Position - target.Handle.Position).Magnitude
                setUI("Collecting", target.Name, dist)
                teleportOrTweenTo(target.Handle.CFrame)
                spawn(function() task.wait(2); startFlyingLoop() end)
                local startTime = tick()
                while tick() - startTime < 5 do
                    storeAllKnownFruitsOnce()
                    storeAnyFruitOnce()
                    local hrp2 = Player.Character and Player.Character:FindFirstChild("HumanoidRootPart")
                    if hrp2 and target and target:FindFirstChild("Handle") then
                        setUI("Collecting", target.Name, (hrp2.Position - target.Handle.Position).Magnitude)
                    end
                    task.wait(0.5)
                end
                stopFlyingLoop()
                totalFruit = totalFruit + 1
                safePcall(function() StarterGui:SetCore("SendNotification", {Title = "HuneIPA - Fruit Finder", Text = "Find {"..tostring(totalFruit).."} fruit on this server", Duration = 4}) end)
                local remaining = findAllFruits()
                if remaining and #remaining > 1 then
                    safeRespawnCharacter()
                    task.wait(2)
                else
                    HopServer()
                    break
                end
            else
                HopServer()
                break
            end
        else
            HopServer()
            break
        end
        task.wait(0.2)
    end
end)
