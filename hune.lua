loadstring(game:HttpGet("https://raw.githubusercontent.com/Konmeo22132-alt/dead_rails/refs/heads/main/autorejoin.lua"))()

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
local UserInputService = game:GetService("UserInputService")

local TEAM = Config.Team or "Pirates"
local FPSBOOST = Config.FPSBOOST or false
local OLD_SERVER = (Config.OldServer == nil) and false or Config.OldServer
local HOPDELAY = (Config.HopDelay == nil) and 0.1 or tonumber(Config.HopDelay)
local FRUITS = Config.Fruits or {}
local TWEENSPEED = (Config.TweenSpeed == nil) and 350 or tonumber(Config.TweenSpeed)
local USE_RESPAWN = (Config.UseRespawn == nil) and true or Config.UseRespawn
local DEBUG = Config.Debug or false

local totalFruit = 0
local hopping = false
local hoppingDots = ""
local flying = false
local lastRespawn = 0

repeat task.wait() until game:IsLoaded()

local function safePcall(fn, ...)
    local ok, res = pcall(fn, ...)
    return ok, res
end

local function getPlayer()
    return Players.LocalPlayer
end

local function normalizeString(s)
    if type(s) ~= "string" then return tostring(s) end
    return string.lower(s)
end

local function parsePrefix(name)
    if type(name) ~= "string" then return tostring(name) end
    local parts = string.split(name, "-")
    return parts[1] or name
end

local function buildLookupFromConfig()
    local lookup = {}
    for _, entry in ipairs(FRUITS) do
        if type(entry) == "string" then
            local serverName = entry
            local pref = parsePrefix(serverName)
            lookup[normalizeString(pref)] = serverName
            lookup[normalizeString(serverName)] = serverName
        elseif type(entry) == "table" then
            local display = entry[1]
            local serverName = entry[2] or entry[1] or entry[3]
            if serverName then
                local pref = parsePrefix(serverName)
                lookup[normalizeString(pref)] = serverName
                if display then
                    lookup[normalizeString(display)] = serverName
                end
            end
        end
    end
    return lookup
end

local FruitLookup = buildLookupFromConfig()

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "HuneIPA_FruitFinder_UI_v1"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.Parent = CoreGui

local container = Instance.new("Frame")
container.Name = "FruitFinderUI"
container.Size = UDim2.new(0, 400, 0, 200)
container.Position = UDim2.new(0.5, -200, 0.4, 0)
container.BackgroundTransparency = 1
container.BorderSizePixel = 2
container.BorderColor3 = Color3.fromRGB(0, 255, 0)
container.Parent = screenGui

local bg = Instance.new("Frame")
bg.Size = UDim2.new(1, -4, 1, -4)
bg.Position = UDim2.new(0, 2, 0, 2)
bg.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
bg.BackgroundTransparency = 0.25
bg.BorderSizePixel = 0
bg.Parent = container

local label = Instance.new("TextLabel")
label.Size = UDim2.new(1, -10, 1, -30)
label.Position = UDim2.new(0, 5, 0, 25)
label.BackgroundTransparency = 1
label.TextColor3 = Color3.fromRGB(0, 255, 0)
label.Font = Enum.Font.SourceSansBold
label.TextSize = 20
label.TextYAlignment = Enum.TextYAlignment.Top
label.TextXAlignment = Enum.TextXAlignment.Left
label.RichText = false
label.Text = "HuneIPA - Fruit Finder\nLoading..."
label.Parent = container

local toggleButton = Instance.new("TextButton")
toggleButton.Size = UDim2.new(0, 100, 0, 25)
toggleButton.Position = UDim2.new(0.5, -50, 0, 0)
toggleButton.BackgroundColor3 = Color3.fromRGB(0, 255, 0)
toggleButton.TextColor3 = Color3.fromRGB(0, 0, 0)
toggleButton.Text = "Toggle UI"
toggleButton.Font = Enum.Font.SourceSansBold
toggleButton.TextSize = 18
toggleButton.Parent = container

toggleButton.MouseButton1Click:Connect(function()
    container.Visible = not container.Visible
end)

local function updateUI(status, fruitShortName, distance)
    local text = "HuneIPA | Fruit Finder\n"
    text = text .. "Player in server: " .. tostring(#Players:GetPlayers()) .. "/12\n"
    if status == "Collecting" and fruitShortName then
        text = text .. "Status: Collecting " .. tostring(fruitShortName) .. " (" .. tostring(math.floor(distance)) .. "m)\n"
    elseif status == "Storing" then
        text = text .. "Status: Storing\n"
    elseif status == "Hopping" then
        text = text .. "Status: Hopping" .. hoppingDots .. "\n"
    else
        text = text .. "Status: Idle\n"
    end
    text = text .. "JobID: " .. tostring(game.JobId) .. "\n"
    text = text .. "Total fruit: {" .. tostring(totalFruit) .. "}\n"
    label.Text = text
end

local function updateHoppingDotsLoop()
    while true do
        if hopping then
            if hoppingDots == "" then hoppingDots = "." elseif hoppingDots == "." then hoppingDots = ".." elseif hoppingDots == ".." then hoppingDots = "..." else hoppingDots = "" end
        else
            hoppingDots = ""
        end
        task.wait(0.5)
    end
end
spawn(updateHoppingDotsLoop)

local function notify(title, text, duration)
    safePcall(function()
        StarterGui:SetCore("SendNotification", {Title = title or "HuneIPA - Fruit Finder", Text = text or "", Duration = duration or 4})
    end)
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

local function gatherCandidates()
    local list = {}
    for _, child in ipairs(workspace:GetChildren()) do
        if child and (child:IsA("Model") or child:IsA("Tool")) then
            local handle = child:FindFirstChild("Handle")
            if handle and not isPlayerDescendant(child) then
                table.insert(list, child)
            end
        end
    end
    return list
end

local function matchConfigName(name)
    if not name then return false, nil end
    local lname = normalizeString(name)
    for k, v in pairs(FruitLookup) do
        if k and lname:find(k, 1, true) then
            return true, v
        end
    end
    return false, nil
end

local function isFruitModel(obj)
    if not obj or not obj.Name then return false, nil end
    local ok, serverName = matchConfigName(obj.Name)
    if ok then return true, serverName end
    local lname = normalizeString(obj.Name)
    if lname:find("fruit", 1, true) then
        return true, obj.Name
    end
    return false, nil
end

local function findAllFruits()
    local results = {}
    local cand = gatherCandidates()
    for _, obj in ipairs(cand) do
        local ok, sname = isFruitModel(obj)
        if ok then
            table.insert(results, {Model = obj, ServerName = sname})
            if DEBUG then warn("[FruitFinder] Candidate:", obj:GetFullName(), sname) end
        end
    end
    return results
end

local function getNearest(fruits)
    if not fruits or #fruits == 0 then return nil end
    local pl = getPlayer()
    if not pl or not pl.Character or not pl.Character:FindFirstChild("HumanoidRootPart") then
        return fruits[1]
    end
    local hrp = pl.Character.HumanoidRootPart
    local best = nil
    local bestDist = math.huge
    for _, entry in ipairs(fruits) do
        local m = entry.Model
        if m and m:FindFirstChild("Handle") then
            local d = (hrp.Position - m.Handle.Position).Magnitude
            if d < bestDist then
                bestDist = d
                best = entry
            end
        end
    end
    return best
end

local function createTweenToCFrame(hrp, targetCFrame, speed)
    if not hrp or not targetCFrame then return nil end
    local pos = targetCFrame.Position
    local dist = (hrp.Position - pos).Magnitude
    local ttime = dist / (speed or TWEENSPEED)
    if ttime <= 0 then ttime = 0.01 end
    local info = TweenInfo.new(ttime, Enum.EasingStyle.Linear)
    local ok, tween = pcall(function() return TweenService:Create(hrp, info, {CFrame = CFrame.new(pos + Vector3.new(0,3,0)}) end)
    if ok then return tween end
    return nil
end

local function playTweenAndTrack(hrp, targetCFrame, speed, nameForUI)
    if not hrp or not targetCFrame then return end
    local tween = createTweenToCFrame(hrp, targetCFrame, speed)
    if tween then
        safePcall(function() tween:Play() end)
        while tween.PlaybackState == Enum.PlaybackState.Playing do
            local pos = targetCFrame.Position
            local distNow = (hrp.Position - pos).Magnitude
            updateUI("Collecting", nameForUI or "Fruit", distNow)
            task.wait(0.1)
        end
    else
        safePcall(function() hrp.CFrame = targetCFrame + Vector3.new(0,3,0) end)
    end
end

local function tweenToModel(model, nameForUI)
    local pl = getPlayer()
    if not pl or not pl.Character then return end
    local hrp = pl.Character:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    if not model or not model:FindFirstChild("Handle") then return end
    local targetCF = model.Handle.CFrame
    playTweenAndTrack(hrp, targetCF, TWEENSPEED, nameForUI)
end

local function storeByServerName(serverName)
    local pl = getPlayer()
    if not pl then return end
    local backpack = pl:FindFirstChild("Backpack")
    local char = pl.Character
    if not backpack and not char then return end
    local pref = parsePrefix(serverName or "")
    if not pref then return end
    local names = { pref .. " Fruit", pref }
    for _, nm in ipairs(names) do
        local obj = backpack and backpack:FindFirstChild(nm)
        if obj then
            safePcall(function()
                if ReplicatedStorage and ReplicatedStorage:FindFirstChild("Remotes") and ReplicatedStorage.Remotes:FindFirstChild("CommF_") then
                    ReplicatedStorage.Remotes.CommF_:InvokeServer("StoreFruit", serverName, obj)
                end
            end)
            return
        end
    end
    for _, nm in ipairs(names) do
        local obj = char and char:FindFirstChild(nm)
        if obj then
            safePcall(function()
                if ReplicatedStorage and ReplicatedStorage:FindFirstChild("Remotes") and ReplicatedStorage.Remotes:FindFirstChild("CommF_") then
                    ReplicatedStorage.Remotes.CommF_:InvokeServer("StoreFruit", serverName, obj)
                end
            end)
            return
        end
    end
end

local function storeAny()
    local pl = getPlayer()
    if not pl then return end
    local backpack = pl:FindFirstChild("Backpack")
    local char = pl.Character
    if backpack then
        for _, obj in ipairs(backpack:GetChildren()) do
            if type(obj.Name) == "string" and normalizeString(obj.Name):find("fruit") then
                safePcall(function()
                    if ReplicatedStorage and ReplicatedStorage:FindFirstChild("Remotes") and ReplicatedStorage.Remotes:FindFirstChild("CommF_") then
                        ReplicatedStorage.Remotes.CommF_:InvokeServer("StoreFruit", obj.Name, obj)
                    end
                end)
            end
        end
    end
    if char then
        for _, obj in ipairs(char:GetChildren()) do
            if type(obj.Name) == "string" and normalizeString(obj.Name):find("fruit") then
                safePcall(function()
                    if ReplicatedStorage and ReplicatedStorage:FindFirstChild("Remotes") and ReplicatedStorage.Remotes:FindFirstChild("CommF_") then
                        ReplicatedStorage.Remotes.CommF_:InvokeServer("StoreFruit", obj.Name, obj)
                    end
                end)
            end
        end
    end
end

local function storeAllFromConfig()
    for _, sname in ipairs(FRUITS) do
        storeByServerName(sname)
    end
end

local function startFlyUpLoop()
    if flying then return end
    flying = true
    spawn(function()
        while flying do
            local pl = getPlayer()
            if pl and pl.Character and pl.Character:FindFirstChild("HumanoidRootPart") then
                local hrp = pl.Character.HumanoidRootPart
                safePcall(function() hrp.CFrame = hrp.CFrame + Vector3.new(0, 10, 0) end)
            end
            task.wait(0.5)
        end
    end)
end

local function stopFlyUpLoop()
    flying = false
end

local function safeRespawnCharacter()
    if not USE_RESPAWN then return end
    if tick() - lastRespawn < 4 then return end
    lastRespawn = tick()
    local pl = getPlayer()
    if not pl then return end
    safePcall(function()
        if pl.LoadCharacter then
            pl:LoadCharacter()
            local t0 = tick()
            while tick() - t0 < 10 do
                if pl.Character and pl.Character:FindFirstChild("HumanoidRootPart") then break end
                task.wait(0.1)
            end
            return
        else
            if pl.Character and pl.Character:FindFirstChild("Humanoid") then
                safePcall(function() pl.Character:BreakJoints() end)
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
    local ok2, data = pcall(function() return HttpService:JSONDecode(raw) end)
    if ok2 then return data end
    return nil
end

local function hopOldServerLogic()
    hopping = true
    updateUI("Hopping")
    local cursor = nil
    for page = 1, 10 do
        local data = apiListServers(cursor)
        if data and data.data then
            for _, s in ipairs(data.data) do
                local playing = tonumber(s.playing) or 0
                local maxp = tonumber(s.maxPlayers) or 0
                local id = s.id
                local uptime = s.uptime or 0
                if id and tostring(id) ~= tostring(game.JobId) and playing < maxp and playing < 6 and uptime > 7200 then
                    local ok = safePcall(function() TeleportService:TeleportToPlaceInstance(game.PlaceId, id, getPlayer()) end)
                    if not ok then
                        notify("HuneIPA - Fruit Finder", "Hop server failed, retry in 1 second", 3)
                        task.wait(1)
                    else
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
    local ok = safePcall(function() TeleportService:Teleport(game.PlaceId, getPlayer()) end)
    if not ok then
        notify("HuneIPA - Fruit Finder", "Hop server failed, retry in 1 second", 3)
        task.wait(1)
    end
end

local function hopLowPlayersLogic()
    hopping = true
    updateUI("Hopping")
    if HOPDELAY and tonumber(HOPDELAY) and tonumber(HOPDELAY) > 0 then
        task.wait(tonumber(HOPDELAY))
    end
    local cursor = nil
    local bestServer = nil
    local bestPlayers = math.huge
    for page = 1, 10 do
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
                    local ok = safePcall(function() TeleportService:TeleportToPlaceInstance(game.PlaceId, id, getPlayer()) end)
                    if not ok then
                        notify("HuneIPA - Fruit Finder", "Hop server failed, retry in 1 second", 3)
                        task.wait(1)
                    else
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
        local ok = safePcall(function() TeleportService:TeleportToPlaceInstance(game.PlaceId, bestServer, getPlayer()) end)
        if not ok then
            notify("HuneIPA - Fruit Finder", "Hop server failed, retry in 1 second", 3)
            task.wait(1)
        end
        return
    end
    local ok = safePcall(function() TeleportService:Teleport(game.PlaceId, getPlayer()) end)
    if not ok then
        notify("HuneIPA - Fruit Finder", "Hop server failed, retry in 1 second", 3)
        task.wait(1)
    end
end

local function HopServer()
    if OLD_SERVER then
        hopOldServerLogic()
    else
        hopLowPlayersLogic()
    end
end

local function autoJoinTeamImmediate()
    if (TEAM == "Pirates" or TEAM == "Marines") and ReplicatedStorage and ReplicatedStorage:FindFirstChild("Remotes") and ReplicatedStorage.Remotes:FindFirstChild("CommF_") then
        local ok, res = pcall(function() ReplicatedStorage.Remotes.CommF_:InvokeServer("SetTeam", TEAM) end)
        task.wait(0.15)
        if not ok then
            notify("HuneIPA - Fruit Finder", "Join team failed", 4)
        end
    end
end

local function applyFpsBoost()
    if not FPSBOOST then return end
    safePcall(function() SoundService.Volume = 0 end)
    safePcall(function()
        if settings and settings().Rendering then
            settings().Rendering.QualityLevel = Enum.QualityLevel.Level02
        end
    end)
    for _, obj in ipairs(workspace:GetDescendants()) do
        if isPlayerDescendant(obj) then
        else
            safePcall(function()
                if obj:IsA("ParticleEmitter") or obj:IsA("Trail") or obj:IsA("Beam") then
                    obj.Enabled = false
                end
            end)
        end
    end
    for _, obj in ipairs(workspace:GetDescendants()) do
        if isPlayerDescendant(obj) then
        else
            safePcall(function()
                if obj:IsA("Decal") or obj:IsA("Texture") then
                    if obj.Transparency ~= nil then
                        obj.Transparency = 1
                    end
                end
            end)
        end
    end
    for _, obj in ipairs(workspace:GetDescendants()) do
        if isPlayerDescendant(obj) then
        else
            safePcall(function()
                if obj:IsA("MeshPart") then
                    obj.Material = Enum.Material.SmoothPlastic
                    if obj.TextureID ~= nil then
                        pcall(function() obj.TextureID = "" end)
                    end
                    obj.Reflectance = 0
                elseif obj:IsA("BasePart") then
                    obj.Material = Enum.Material.SmoothPlastic
                    obj.Reflectance = 0
                end
            end)
        end
    end
end

local function prepareStartup()
    updateUI("Idle")
    notify("HuneIPA - Fruit Finder", "Load successfully", 4)
end

prepareStartup()
autoJoinTeamImmediate()
applyFpsBoost()
task.wait(5)

local function mainLoop()
    while true do
        local pl = getPlayer()
        if not pl or not pl.Character or not pl.Character:FindFirstChild("HumanoidRootPart") then
            task.wait(0.5)
        end
        local fruits = findAllFruits()
        if fruits and #fruits > 0 then
            local nearest = getNearest(fruits)
            if nearest and nearest.Model and nearest.Model:FindFirstChild("Handle") then
                local model = nearest.Model
                local serverName = nearest.ServerName or model.Name
                local hrp = pl and pl.Character and pl.Character:FindFirstChild("HumanoidRootPart")
                if hrp then
                    local distNow = (hrp.Position - model.Handle.Position).Magnitude
                    updateUI("Collecting", serverName, distNow)
                end
                tweenToModel(model, serverName)
                notify("HuneIPA - Fruit Finder", "Collecting " .. tostring(serverName), 3)
                local collecting = true
                spawn(function()
                    while collecting do
                        local pl2 = getPlayer()
                        if pl2 and pl2.Character and pl2.Character:FindFirstChild("HumanoidRootPart") and model and model:FindFirstChild("Handle") then
                            local nowDist = (pl2.Character.HumanoidRootPart.Position - model.Handle.Position).Magnitude
                            updateUI("Collecting", serverName, nowDist)
                        end
                        task.wait(0.1)
                    end
                end)
                spawn(function() task.wait(2); startFlyUpLoop() end)
                local startTick = tick()
                while tick() - startTick < 5 do
                    storeAllFromConfig()
                    storeAny()
                    task.wait(0.5)
                end
                collecting = false
                stopFlyUpLoop()
                totalFruit = totalFruit + 1
                notify("HuneIPA - Fruit Finder", "Find {" .. tostring(totalFruit) .. "} fruit on this server", 4)
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
        task.wait(0.3)
    end
end

spawn(mainLoop)
