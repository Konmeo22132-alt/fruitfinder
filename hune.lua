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

local TEAM = Config.Team or "Pirates"
local FPSBOOST = Config.FPSBOOST or false
local FRUITS = Config.Fruits or {}
local HOP_OLD = Config.HopOldServer or false
local TWEENSPEED = 350

local totalFruit = 0
local hopping = false
local hoppingDots = ""
local flying = false

-- safe helpers
local function isDescendantOfPlayer(obj)
    if not obj then return false end
    local anc = obj
    while anc and anc ~= workspace do
        if Players:GetPlayerFromCharacter(anc) then return true end
        anc = anc.Parent
    end
    return false
end

local function safeSet(fn, ...)
    local ok, res = pcall(fn, ...)
    return ok, res
end

-- auto join team (safe)
pcall(function()
    if TEAM == "Pirates" or TEAM == "Marines" then
        if ReplicatedStorage:FindFirstChild("Remotes") and ReplicatedStorage.Remotes:FindFirstChild("CommF_") then
            pcall(function()
                ReplicatedStorage.Remotes.CommF_:InvokeServer("SetTeam", TEAM)
            end)
        end
    end
end)

-- FPS boost (an toàn — chỉ thay đổi thứ rõ ràng)
if FPSBOOST then
    pcall(function() SoundService.Volume = 0 end)
    pcall(function() settings().Rendering.QualityLevel = Enum.QualityLevel.Level02 end)
    for _, obj in pairs(workspace:GetDescendants()) do
        -- skip player-owned objects & engine/world origin objects (bắt đầu bằng "_")
        if isDescendantOfPlayer(obj) then continue end
        if type(obj.Name) == "string" and tostring(obj.Name):sub(1,1) == "_" then continue end

        if obj:IsA("Decal") or obj:IsA("Texture") then
            pcall(function() obj:Destroy() end)
        elseif obj:IsA("ParticleEmitter") or obj:IsA("Trail") or obj:IsA("Beam") then
            pcall(function() obj.Enabled = false end)
        elseif obj:IsA("MeshPart") then
            pcall(function()
                obj.TextureID = ""
                obj.Material = Enum.Material.SmoothPlastic
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

-- thông báo load
pcall(function()
    StarterGui:SetCore("SendNotification", {Title="HuneIPA - Fruit Finder", Text="Load successly", Duration=5})
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
    if status == "Collecting" then
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
            if hoppingDots == "" then hoppingDots = "."
            elseif hoppingDots == "." then hoppingDots = ".."
            elseif hoppingDots == ".." then hoppingDots = "..."
            else hoppingDots = "" end
        else hoppingDots = "" end
    end
end)

-- helpers để parse FRUITS (FRUITS chứa "Name-Name")
local function serverNameToPrefix(serverName)
    if type(serverName) ~= "string" then return serverName end
    local parts = string.split(serverName, "-")
    return parts[1] or serverName
end

-- tìm fruit: ưu tiên trái trong FRUITS, nhưng cũng chấp nhận model có "fruit" trong tên (dự phòng)
local function findFruitsInWorkspace()
    local found = {}
    for _, obj in ipairs(workspace:GetDescendants()) do
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
    return found
end

-- tween hoặc teleport an toàn
local function safeTweenToTarget(handleCFrame)
    if not Player or not Player.Character then return end
    local hrp = Player.Character:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    local pos = nil
    if typeof(handleCFrame) == "CFrame" then pos = handleCFrame.Position
    elseif typeof(handleCFrame) == "Vector3" then pos = handleCFrame
    else return end
    local targetCFrame = CFrame.new(pos + Vector3.new(0,3,0))
    local distance = (hrp.Position - pos).Magnitude
    if distance <= 300 then
        pcall(function() hrp.CFrame = targetCFrame end)
        return
    end
    local tweenInfo = TweenInfo.new(distance / TWEENSPEED, Enum.EasingStyle.Linear)
    local ok, tween = pcall(function() return TweenService:Create(hrp, tweenInfo, {CFrame = targetCFrame}) end)
    if ok and tween then
        pcall(function()
            tween:Play()
            tween.Completed:Wait()
        end)
    else
        pcall(function() hrp.CFrame = targetCFrame end)
    end
end

-- store fruit (thử store cho những fruit có trong FRUITS)
local function storeAllFruitOnce()
    local backpack = Player:FindFirstChild("Backpack")
    local char = Player.Character
    for _, serverName in ipairs(FRUITS) do
        local prefix = serverNameToPrefix(serverName)
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

-- respawn an toàn
local function safeRespawn()
    pcall(function()
        if Player and Player.LoadCharacter then
            Player:LoadCharacter()
            -- chờ HRP mới
            local timeout = tick() + 10
            while tick() < timeout do
                if Player.Character and Player.Character:FindFirstChild("HumanoidRootPart") then break end
                task.wait(0.1)
            end
        else
            -- fallback: BreakJoints (ít dùng)
            if Player.Character and Player.Character:FindFirstChild("Humanoid") then
                pcall(function() Player.Character:BreakJoints() end)
            end
        end
    end)
end

-- fly up while hopping
local function startFlying()
    if flying then return end
    flying = true
    spawn(function()
        while flying do
            if Player and Player.Character then
                local hrp = Player.Character:FindFirstChild("HumanoidRootPart")
                if hrp then pcall(function() hrp.CFrame = hrp.CFrame + Vector3.new(0,10,0) end) end
            end
            task.wait(0.5)
        end
    end)
end
local function stopFlying() flying = false end

-- hop server, ưu tiên server >2h & <6 player khi bật
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
                    local uptime = s.uptime or s.playing -- fallback
                    if uptime and uptime > 7200 and s.id and tostring(s.id) ~= tostring(game.JobId) then
                        pcall(function()
                            TeleportService:TeleportToPlaceInstance(game.PlaceId, s.id, Player)
                        end)
                        return
                    end
                end
            end
        end
    end
    -- fallback normal hop
    pcall(function() TeleportService:Teleport(game.PlaceId, Player) end)
end

-- main loop
spawn(function()
    task.wait(5)
    while task.wait(0.5) do
        if not Player or not Player.Character then continue end
        local fruits = findFruitsInWorkspace()
        if #fruits > 0 then
            -- lấy quả gần nhất
            table.sort(fruits, function(a,b)
                local ah = a:FindFirstChild("Handle")
                local bh = b:FindFirstChild("Handle")
                if not ah or not bh then return false end
                local hrp = Player.Character and Player.Character:FindFirstChild("HumanoidRootPart")
                if not hrp then return false end
                return (hrp.Position - ah.Position).Magnitude < (hrp.Position - bh.Position).Magnitude
            end)
            local target = fruits[1]
            if not target or not target:FindFirstChild("Handle") then
                continue
            end
            local hrp = Player.Character and Player.Character:FindFirstChild("HumanoidRootPart")
            if not hrp then continue end
            local dist = (hrp.Position - target.Handle.Position).Magnitude
            UpdateUI("Collecting", target.Name, dist)
            safeTweenToTarget(target.Handle.CFrame)
            -- bắt đầu store, sau 2s bật fly
            local startTick = tick()
            spawn(function() task.wait(2) startFlying() end)
            while tick() - startTick < 5 do
                storeAllFruitOnce()
                local hrp2 = Player.Character and Player.Character:FindFirstChild("HumanoidRootPart")
                if hrp2 and target and target:FindFirstChild("Handle") then
                    local nd = (hrp2.Position - target.Handle.Position).Magnitude
                    UpdateUI("Collecting", target.Name, nd)
                end
                task.wait(0.5)
            end
            stopFlying()
            totalFruit = totalFruit + 1
            pcall(function()
                StarterGui:SetCore("SendNotification", {Title="HuneIPA - Fruit Finder", Text="Find {"..tostring(totalFruit).."} fruit on this server", Duration=4})
            end)
            -- kiểm tra còn fruit khác không
            local remaining = findFruitsInWorkspace()
            if #remaining > 1 then
                -- respawn an toàn và tiếp tục
                safeRespawn()
                task.wait(2)
            else
                -- hop server
                HopServer()
                break
            end
        else
            UpdateUI("Idle")
        end
    end
end)
