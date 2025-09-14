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
local HOP_OLD = Config.HopOldServer or false
local FRUITS = Config.Fruits or {}
local TWEENSPEED = Config.TweenSpeed or 350
local DEBUG = Config.Debug or false
local USE_RESPAWN = (Config.UseRespawn == nil) and true or Config.UseRespawn

local totalFruit = 0
local hopping = false
local hoppingDots = ""
local flying = false
local lastRespawn = 0

local function safePcall(fn, ...)
    local ok, res = pcall(fn, ...)
    return ok, res
end

local function getPlayer()
    return Players.LocalPlayer
end

local function isDescendantOfPlayer(obj)
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

local function toLower(s)
    if type(s) ~= "string" then return tostring(s) end
    return string.lower(s)
end

local function splitServerName(name)
    if type(name) ~= "string" then return tostring(name) end
    local parts = string.split(name, "-")
    return parts[1] or name
end

local function buildFruitMaps()
    local displayToServer = {}
    local prefixToServer = {}
    local serverList = {}
    for i, v in ipairs(FRUITS) do
        if type(v) == "string" then
            local serverName = v
            table.insert(serverList, serverName)
            local pref = splitServerName(serverName)
            prefixToServer[toLower(pref)] = serverName
            displayToServer[toLower(serverName)] = serverName
        elseif type(v) == "table" then
            local display = v[1] or v[2] or v[3]
            local serverName = v[2] or v[1] or v[3]
            table.insert(serverList, serverName)
            prefixToServer[toLower(splitServerName(serverName))] = serverName
            if display then displayToServer[toLower(display)] = serverName end
        end
    end
    return displayToServer, prefixToServer, serverList
end

local DisplayToServerMap, PrefixToServerMap, ServerList = buildFruitMaps()

local function notify(title, text, duration)
    safePcall(function()
        StarterGui:SetCore("SendNotification", {Title = title or "Fruit Finder", Text = text or "", Duration = duration or 4})
    end)
end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "FruitFinderUI"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.Parent = CoreGui

local label = Instance.new("TextLabel")
label.Size = UDim2.new(1, 0, 0, 200)
label.Position = UDim2.new(0, 0, 0.4, 0)
label.BackgroundTransparency = 1
label.TextColor3 = Color3.fromRGB(0, 255, 0)
label.Font = Enum.Font.SourceSansBold
label.TextSize = 26
label.TextStrokeTransparency = 0
label.TextYAlignment = Enum.TextYAlignment.Top
label.Parent = screenGui

local function updateUiText(status, fruitShortName, distance)
    local text = "HunelPA Hub - Fruit Finder\n"
    text = text .. "Players in server: " .. tostring(#Players:GetPlayers()) .. "/12\n"
    if status == "Collecting" and fruitShortName then
        text = text .. "Status: Collecting " .. tostring(fruitShortName) .. " (" .. math.floor(distance) .. "m)\n"
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

local function autoJoinTeam()
    safePcall(function()
        if (TEAM == "Pirates" or TEAM == "Marines") and ReplicatedStorage and ReplicatedStorage:FindFirstChild("Remotes") and ReplicatedStorage.Remotes:FindFirstChild("CommF_") then
            safePcall(function()
                ReplicatedStorage.Remotes.CommF_:InvokeServer("SetTeam", TEAM)
            end)
        end
    end)
end

local function fpsDisableEmitters()
    for _, obj in ipairs(workspace:GetDescendants()) do
        if isDescendantOfPlayer(obj) then
            -- skip
        else
            if obj:IsA("ParticleEmitter") or obj:IsA("Trail") or obj:IsA("Beam") then
                pcall(function() obj.Enabled = false end)
                if DEBUG then warn("Disabled emitter:", obj:GetFullName()) end
            end
        end
    end
end

local function fpsHideDecals()
    for _, obj in ipairs(workspace:GetDescendants()) do
        if isDescendantOfPlayer(obj) then
            -- skip
        else
            if obj:IsA("Decal") then
                pcall(function() obj.Transparency = 1 end)
                if DEBUG then warn("Set decal transparency:", obj:GetFullName()) end
            end
            if obj:IsA("Texture") then
                pcall(function() obj.Transparency = 1 end)
                if DEBUG then warn("Set texture transparency:", obj:GetFullName()) end
            end
        end
    end
end

local function fpsAdjustMeshParts()
    for _, obj in ipairs(workspace:GetDescendants()) do
        if isDescendantOfPlayer(obj) then
            -- skip
        else
            if obj:IsA("MeshPart") then
                pcall(function()
                    obj.Material = Enum.Material.SmoothPlastic
                    if obj.TextureID ~= nil then
                        pcall(function() obj.TextureID = "" end)
                    end
                    obj.Reflectance = 0
                end)
                if DEBUG then warn("Adjusted meshpart:", obj:GetFullName()) end
            end
        end
    end
end

local function applyFpsBoostAll()
    if not FPSBOOST then return end
    pcall(function() SoundService.Volume = 0 end)
    pcall(function() settings().Rendering.QualityLevel = Enum.QualityLevel.Level02 end)
    fpsDisableEmitters()
    fpsHideDecals()
    fpsAdjustMeshParts()
end

local function buildCandidateList()
    local candidates = {}
    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj and (obj:IsA("Model") or obj:IsA("Tool")) and obj:FindFirstChild("Handle") then
            if isDescendantOfPlayer(obj) then
                -- skip
            else
                table.insert(candidates, obj)
            end
        end
    end
    return candidates
end

local function matchFruitByList(obj)
    if not obj or not obj.Name then return false end
    local nm = toLower(obj.Name)
    for _, serverName in ipairs(ServerList) do
        local prefix = splitServerName(serverName)
        if prefix and nm:find(toLower(prefix), 1, true) then
            return true, serverName
        end
    end
    for pref, serverName in pairs(PrefixToServerMap) do
        if pref and nm:find(pref, 1, true) then
            return true, serverName
        end
    end
    return false, nil
end

local function isFruitModel(obj)
    if not obj or not obj.Name then return false end
    local nm = toLower(obj.Name)
    if nm:find("fruit", 1, true) then
        return true
    end
    local ok, serverName = matchFruitByList(obj)
    if ok then return true end
    return false
end

local function findAllFruitsFromWorkspace()
    local list = {}
    local cand = buildCandidateList()
    for _, obj in ipairs(cand) do
        if isFruitModel(obj) then
            table.insert(list, obj)
            if DEBUG then warn("Detected fruit:", obj:GetFullName()) end
        end
    end
    return list
end

local function distanceBetween(a, b)
    if not a or not b then return math.huge end
    return (a.Position - b.Position).Magnitude
end

local function getNearestFruitFromList(list)
    if not list or #list == 0 then return nil end
    local hrp = Player and Player.Character and Player.Character:FindFirstChild("HumanoidRootPart")
    if not hrp then return list[1] end
    local nearest = nil
    local nd = math.huge
    for _, obj in ipairs(list) do
        if obj and obj:FindFirstChild("Handle") then
            local d = distanceBetween(hrp, obj.Handle)
            if d < nd then
                nd = d
                nearest = obj
            end
        end
    end
    return nearest
end

local function createTweenToPos(part, pos, speed)
    if not part or not pos then return nil end
    local dist = (part.Position - pos).Magnitude
    local ttime = dist / (speed or TWEENSPEED)
    local info = TweenInfo.new(ttime, Enum.EasingStyle.Linear)
    local ok, tween = pcall(function() return TweenService:Create(part, info, {CFrame = CFrame.new(pos)}) end)
    if ok then return tween end
    return nil
end

local function tweenHrpto(targetCFrame)
    if not Player or not Player.Character then return end
    local hrp = Player.Character:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    local pos = (typeof(targetCFrame) == "CFrame" and targetCFrame.Position) or (typeof(targetCFrame) == "Vector3" and targetCFrame)
    if not pos then return end
    local desired = CFrame.new(pos + Vector3.new(0, 3, 0))
    local ok, tween = pcall(function()
        local dist = (hrp.Position - pos).Magnitude
        local info = TweenInfo.new(dist / TWEENSPEED, Enum.EasingStyle.Linear)
        return TweenService:Create(hrp, info, {CFrame = desired})
    end)
    if ok and tween then
        safePcall(function() tween:Play() end)
    else
        pcall(function() hrp.CFrame = desired end)
    end
end

local function startTweenToHandleAndKeep(targHandleCFrame)
    tweenHrpto(targHandleCFrame)
end

local function storeKnownFruitsOnce()
    local back = Player and Player:FindFirstChild("Backpack")
    local char = Player and Player.Character
    for _, serverName in ipairs(ServerList) do
        local prefix = splitServerName(serverName)
        if prefix then
            local names = { prefix .. " Fruit", prefix }
            for _, nm in ipairs(names) do
                local obj = (back and back:FindFirstChild(nm)) or (char and char:FindFirstChild(nm))
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
end

local function storeAnyFruitOnce()
    local back = Player and Player:FindFirstChild("Backpack")
    local char = Player and Player.Character
    for _, obj in ipairs((back and back:GetChildren()) or {}) do
        if type(obj.Name) == "string" and toLower(obj.Name):find("fruit") then
            pcall(function()
                if ReplicatedStorage and ReplicatedStorage:FindFirstChild("Remotes") and ReplicatedStorage.Remotes:FindFirstChild("CommF_") then
                    ReplicatedStorage.Remotes.CommF_:InvokeServer("StoreFruit", obj.Name, obj)
                end
            end)
        end
    end
    for _, obj in ipairs((char and char:GetChildren()) or {}) do
        if type(obj.Name) == "string" and toLower(obj.Name):find("fruit") then
            pcall(function()
                if ReplicatedStorage and ReplicatedStorage:FindFirstChild("Remotes") and ReplicatedStorage.Remotes:FindFirstChild("CommF_") then
                    ReplicatedStorage.Remotes.CommF_:InvokeServer("StoreFruit", obj.Name, obj)
                end
            end)
        end
    end
end

local function flyUpLoop()
    if flying then return end
    flying = true
    spawn(function()
        while flying do
            if Player and Player.Character and Player.Character:FindFirstChild("HumanoidRootPart") then
                pcall(function()
                    Player.Character.HumanoidRootPart.CFrame = Player.Character.HumanoidRootPart.CFrame + Vector3.new(0, 10, 0)
                end)
            end
            task.wait(0.5)
        end
    end)
end

local function stopFlyLoop()
    flying = false
end

local function safeRespawnCharacter()
    if not USE_RESPAWN then return end
    if tick() - lastRespawn < 4 then return end
    lastRespawn = tick()
    pcall(function()
        if Player and Player.LoadCharacter then
            Player:LoadCharacter()
            local to = tick() + 10
            while tick() < to do
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
    local ok2, json = pcall(function() return HttpService:JSONDecode(raw) end)
    if ok2 then return json end
    return nil
end

local function hopToPreferOldServers()
    hopping = true
    updateUiText("Hopping")
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

local function hopToPreferLowPlayers()
    hopping = true
    updateUiText("Hopping")
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
    if HOP_OLD then
        hopToPreferOldServers()
    else
        hopToPreferLowPlayers()
    end
end

local function waitForCharacterSpawn(timeout)
    local t0 = tick()
    local limit = (timeout or 12)
    while tick() - t0 < limit do
        if Player and Player.Character and Player.Character:FindFirstChild("HumanoidRootPart") then
            return true
        end
        task.wait(0.1)
    end
    return false
end

local function initAll()
    autoJoinTeam()
    applyFpsBoostAll()
    notify("HuneIPA - Fruit Finder", "Load successfully", 4)
end

initAll()

task.spawn(function()
    waitForCharacterSpawn(12)
    task.wait(1)
    while true do
        if not Player or not Player.Character then
            waitForCharacterSpawn(12)
            task.wait(1)
        end
        local fruits = findAllFruitsFromWorkspace()
        if fruits and #fruits > 0 then
            local nearest = getNearestFruitFromList(fruits)
            if nearest and nearest:FindFirstChild("Handle") and Player and Player.Character and Player.Character:FindFirstChild("HumanoidRootPart") then
                local hrp = Player.Character.HumanoidRootPart
                local dist = (hrp.Position - nearest.Handle.Position).Magnitude
                updateUiText("Collecting", nearest.Name, dist)
                startTweenToHandleAndKeep(nearest.Handle.CFrame)
                local collecting = true
                local uiUpdater = spawn(function()
                    while collecting do
                        local hrp2 = Player and Player.Character and Player.Character:FindFirstChild("HumanoidRootPart")
                        if hrp2 and nearest and nearest:FindFirstChild("Handle") then
                            local nowDist = (hrp2.Position - nearest.Handle.Position).Magnitude
                            updateUiText("Collecting", nearest.Name, nowDist)
                        end
                        task.wait(0.1)
                    end
                end)
                spawn(function() task.wait(2); flyUpLoop() end)
                local startTick = tick()
                while tick() - startTick < 5 do
                    storeKnownFruitsOnce()
                    storeAnyFruitOnce()
                    task.wait(0.5)
                end
                collecting = false
                stopFlyLoop()
                totalFruit = totalFruit + 1
                pcall(function() StarterGui:SetCore("SendNotification", {Title = "HuneIPA - Fruit Finder", Text = "Find {"..tostring(totalFruit).."} fruit on this server", Duration = 4}) end)
                local remaining = findAllFruitsFromWorkspace()
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
