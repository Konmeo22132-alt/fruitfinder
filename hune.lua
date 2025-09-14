local Config = getgenv().Config or {}
local Players = game:GetService("Players")
local Player = Players.LocalPlayer
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService = game:GetService("TeleportService")
local TweenService = game:GetService("TweenService")
local StarterGui = game:GetService("StarterGui")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local TEAM = Config.Team or "Pirates"
local FPSBOOST = Config.FPSBOOST or false
local OLD_SERVER = (Config.OldServer == nil) and false or Config.OldServer
local HOPDELAY = tonumber(Config.HopDelay) or 0.1
local FRUITS = Config.Fruits or {}
local TWEENSPEED = tonumber(Config.TweenSpeed) or 350
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

local function waitForCharacter(timeout)
    local pl = getPlayer()
    local t0 = tick()
    local limit = timeout or 12
    while tick() - t0 < limit do
        if pl and pl.Character and pl.Character:FindFirstChild("HumanoidRootPart") then
            return true
        end
        task.wait(0.1)
    end
    return false
end

local function autoJoinTeam()
    local pl = getPlayer()
    if not pl then return end
    if not ReplicatedStorage then return end
    if (TEAM == "Pirates" or TEAM == "Marines") and ReplicatedStorage:FindFirstChild("Remotes") and ReplicatedStorage.Remotes:FindFirstChild("CommF_") then
        safePcall(function() ReplicatedStorage.Remotes.CommF_:InvokeServer("SetTeam", TEAM) end)
    end
end

local function applyFpsBoost()
    if not FPSBOOST then return end
    safePcall(function() game:GetService("SoundService").Volume = 0 end)
    safePcall(function()
        if settings and settings().Rendering then
            settings().Rendering.QualityLevel = Enum.QualityLevel.Level02
        end
    end)
    for _, obj in ipairs(workspace:GetDescendants()) do
        safePcall(function()
            if obj:IsA("ParticleEmitter") or obj:IsA("Trail") or obj:IsA("Beam") then
                obj.Enabled = false
            end
        end)
    end
    for _, obj in ipairs(workspace:GetDescendants()) do
        safePcall(function()
            if obj:IsA("Decal") or obj:IsA("Texture") then
                if obj.Transparency ~= nil then
                    obj.Transparency = 1
                end
            end
        end)
    end
    for _, obj in ipairs(workspace:GetDescendants()) do
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

local function notify(title, text, duration)
    safePcall(function()
        StarterGui:SetCore("SendNotification", {Title = title or "Fruit Finder", Text = text or "", Duration = duration or 4})
    end)
end

local function normalizeServerName(s)
    if type(s) ~= "string" then return tostring(s) end
    local low = string.lower(s)
    return low
end

local function parsePrefix(serverName)
    if type(serverName) ~= "string" then return tostring(serverName) end
    local parts = string.split(serverName, "-")
    return parts[1] or serverName
end

local function buildFruitLookup()
    local lookup = {}
    for _, v in ipairs(FRUITS) do
        if type(v) == "string" then
            local serverName = v
            local pref = parsePrefix(serverName)
            lookup[string.lower(pref)] = serverName
            lookup[string.lower(serverName)] = serverName
        elseif type(v) == "table" then
            local display = v[1] or v[2] or v[3]
            local serverName = v[2] or v[1] or v[3]
            if serverName then
                local pref = parsePrefix(serverName)
                lookup[string.lower(pref)] = serverName
                if display then lookup[string.lower(display)] = serverName end
            end
        end
    end
    return lookup
end

local FruitLookup = buildFruitLookup()

local CoreGui = game:GetService("CoreGui")
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "FruitFinderUI"
screenGui.IgnoreGuiInset = true
screenGui.ResetOnSpawn = false
screenGui.Parent = CoreGui

local label = Instance.new("TextLabel")
label.Size = UDim2.new(1, 0, 0, 180)
label.Position = UDim2.new(0, 0, 0.4, 0)
label.BackgroundTransparency = 1
label.TextColor3 = Color3.fromRGB(0, 255, 0)
label.Font = Enum.Font.SourceSansBold
label.TextSize = 26
label.TextStrokeTransparency = 0
label.TextYAlignment = Enum.TextYAlignment.Top
label.TextXAlignment = Enum.TextXAlignment.Left
label.RichText = false
label.Text = "HuneIPA - Fruit Finder\nLoading..."
label.Parent = screenGui

local function updateUI(status, fruitShort, distance)
    local text = "HuneIPA Hub - Fruit Finder\n"
    local playersInServer = #Players:GetPlayers()
    text = text .. "Player in server: " .. tostring(playersInServer) .. "/12\n"
    if status == "Collecting" and fruitShort then
        text = text .. "Status: Collecting " .. tostring(fruitShort) .. " (" .. math.floor(distance) .. "m)\n"
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

spawn(function()
    while task.wait(0.5) do
        if hopping then
            if hoppingDots == "" then hoppingDots = "." elseif hoppingDots == "." then hoppingDots = ".." elseif hoppingDots == ".." then hoppingDots = "..." else hoppingDots = "" end
        else
            hoppingDots = ""
        end
    end
end)

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

local function gatherCandidateFruitModels()
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

local function isMatchFromConfig(name)
    if not name then return false end
    local lname = string.lower(name)
    for k, v in pairs(FruitLookup) do
        if k and lname:find(k, 1, true) then
            return true, FruitLookup[k]
        end
    end
    return false, nil
end

local function isFruitModel(obj)
    if not obj or not obj.Name then return false, nil end
    local ok, serverName = isMatchFromConfig(obj.Name)
    if ok then return true, serverName end
    local lname = string.lower(obj.Name)
    if lname:find("fruit", 1, true) then
        return true, obj.Name
    end
    return false, nil
end

local function findAllFruits()
    local results = {}
    local candidates = gatherCandidateFruitModels()
    for _, obj in ipairs(candidates) do
        local ok, sname = isFruitModel(obj)
        if ok then
            table.insert(results, {Model = obj, ServerName = sname})
            if DEBUG then warn("[FruitFinder] Candidate:", obj:GetFullName(), sname) end
        end
    end
    return results
end

local function getNearestFruit(fruits)
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

local function createTween(hrp, targetCFrame, speed)
    if not hrp or not targetCFrame then return nil end
    local pos = targetCFrame.Position
    local dist = (hrp.Position - pos).Magnitude
    local ttime = dist / (speed or TWEENSPEED)
    if ttime <= 0 then ttime = 0.01 end
    local info = TweenInfo.new(ttime, Enum.EasingStyle.Linear)
    local ok, tween = pcall(function() return TweenService:Create(hrp, info, {CFrame = CFrame.new(pos + Vector3.new(0,3,0))}) end)
    if ok then
        return tween
    end
    return nil
end

local function tweenToHandle(model)
    local pl = getPlayer()
    if not pl or not pl.Character then return end
    local hrp = pl.Character:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    if not model or not model:FindFirstChild("Handle") then return end
    local targetCFrame = model.Handle.CFrame
    local tween = createTween(hrp, targetCFrame, TWEENSPEED)
    if tween then
        safePcall(function() tween:Play() end)
    else
        safePcall(function() hrp.CFrame = targetCFrame + Vector3.new(0,3,0) end)
    end
    return tween
end

local function storeFruitByServerName(serverName)
    local pl = getPlayer()
    if not pl then return end
    local backpack = pl:FindFirstChild("Backpack")
    local char = pl.Character
    if not backpack and not char then return end
    local prefix = parsePrefix(serverName or "")
    if not prefix then return end
    local candidates = { prefix .. " Fruit", prefix }
    for _, cname in ipairs(candidates) do
        local obj = backpack and backpack:FindFirstChild(cname)
        if obj then
            pcall(function()
                if ReplicatedStorage and ReplicatedStorage:FindFirstChild("Remotes") and ReplicatedStorage.Remotes:FindFirstChild("CommF_") then
                    ReplicatedStorage.Remotes.CommF_:InvokeServer("StoreFruit", serverName, obj)
                end
            end)
            return
        end
    end
    for _, cname in ipairs(candidates) do
        local obj = char and char:FindFirstChild(cname)
        if obj then
            pcall(function()
                if ReplicatedStorage and ReplicatedStorage:FindFirstChild("Remotes") and ReplicatedStorage.Remotes:FindFirstChild("CommF_") then
                    ReplicatedStorage.Remotes.CommF_:InvokeServer("StoreFruit", serverName, obj)
                end
            end)
            return
        end
    end
end

local function storeAnyFruit()
    local pl = getPlayer()
    if not pl then return end
    local backpack = pl:FindFirstChild("Backpack")
    local char = pl.Character
    if backpack then
        for _, obj in ipairs(backpack:GetChildren()) do
            if type(obj.Name) == "string" and string.lower(obj.Name):find("fruit") then
                pcall(function()
                    if ReplicatedStorage and ReplicatedStorage:FindFirstChild("Remotes") and ReplicatedStorage.Remotes:FindFirstChild("CommF_") then
                        ReplicatedStorage.Remotes.CommF_:InvokeServer("StoreFruit", obj.Name, obj)
                    end
                end)
            end
        end
    end
    if char then
        for _, obj in ipairs(char:GetChildren()) do
            if type(obj.Name) == "string" and string.lower(obj.Name):find("fruit") then
                pcall(function()
                    if ReplicatedStorage and ReplicatedStorage:FindFirstChild("Remotes") and ReplicatedStorage.Remotes:FindFirstChild("CommF_") then
                        ReplicatedStorage.Remotes.CommF_:InvokeServer("StoreFruit", obj.Name, obj)
                    end
                end)
            end
        end
    end
end

local function storeAllFruitsFromConfig()
    for _, serverName in ipairs(ServerList or FRUITS) do
        storeFruitByServerName(serverName)
    end
end

local function startFlyUp()
    if flying then return end
    flying = true
    spawn(function()
        while flying do
            local pl = getPlayer()
            if pl and pl.Character and pl.Character:FindFirstChild("HumanoidRootPart") then
                local hrp = pl.Character.HumanoidRootPart
                pcall(function() hrp.CFrame = hrp.CFrame + Vector3.new(0, 10, 0) end)
            end
            task.wait(0.5)
        end
    end)
end

local function stopFlyUp()
    flying = false
end

local function safeRespawn()
    if not USE_RESPAWN then return end
    if tick() - lastRespawn < 4 then return end
    lastRespawn = tick()
    local pl = getPlayer()
    if not pl then return end
    pcall(function()
        if pl.LoadCharacter then
            pl:LoadCharacter()
            local ok = waitForCharacter(10)
            return ok
        else
            if pl.Character and pl.Character:FindFirstChild("Humanoid") then
                pcall(function() pl.Character:BreakJoints() end)
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

local function hopPreferOldServer()
    hopping = true
    updateUI("Hopping")
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
    updateUI("Hopping")
    local cursor = nil
    local bestServer = nil
    local bestPlayers = math.huge
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
    if OLD_SERVER then
        hopPreferOldServer()
    else
        if HOPDELAY and tonumber(HOPDELAY) then
            if tonumber(HOPDELAY) > 0 then task.wait(tonumber(HOPDELAY)) end
        end
        hopPreferLowPlayers()
    end
end

local function prepareStartup()
    updateUI("Idle")
    notify("HuneIPA - Fruit Finder", "Load successfully", 4)
    waitForCharacter(12)
end

prepareStartup()
autoJoinTeam()
applyFpsBoost()

task.wait(5)

local function mainLoop()
    while true do
        if not Player or not Player.Character or not Player.Character:FindFirstChild("HumanoidRootPart") then
            waitForCharacter(12)
            task.wait(1)
        end
        local found = findAllFruits()
        if found and #found > 0 then
            local nearestEntry = getNearestFruit(found)
            if nearestEntry and nearestEntry.Model and nearestEntry.Model:FindFirstChild("Handle") then
                local fruitModel = nearestEntry.Model
                local serverName = nearestEntry.ServerName or nearestEntry.Model.Name
                local hrp = Player.Character and Player.Character:FindFirstChild("HumanoidRootPart")
                if hrp then
                    local distNow = (hrp.Position - fruitModel.Handle.Position).Magnitude
                    updateUI("Collecting", serverName, distNow)
                end
                local tween = tweenToHandle(fruitModel)
                notify("HuneIPA - Fruit Finder", "Collecting " .. tostring(serverName), 3)
                local collecting = true
                local uiThread = spawn(function()
                    while collecting do
                        if Player and Player.Character and Player.Character:FindFirstChild("HumanoidRootPart") and fruitModel and fruitModel:FindFirstChild("Handle") then
                            local nowDist = (Player.Character.HumanoidRootPart.Position - fruitModel.Handle.Position).Magnitude
                            updateUI("Collecting", serverName, nowDist)
                        end
                        task.wait(0.1)
                    end
                end)
                spawn(function()
                    task.wait(2)
                    startFlyUp()
                end)
                local startTick = tick()
                while tick() - startTick < 5 do
                    storeAllFruitsFromConfig()
                    storeAnyFruit()
                    task.wait(0.5)
                end
                collecting = false
                stopFlyUp()
                totalFruit = totalFruit + 1
                notify("HuneIPA - Fruit Finder", "Find {" .. tostring(totalFruit) .. "} fruit on this server", 4)
                local remaining = findAllFruits()
                if remaining and #remaining > 1 then
                    safeRespawn()
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
end

local ok, err = pcall(mainLoop)
if not ok then
    warn("FruitFinder main loop error:", err)
localal
