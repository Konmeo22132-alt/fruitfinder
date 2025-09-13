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
local HopOldServer = Config.HopOldServer or false
local TWEENSPEED = 350

local totalFruit = 0
local hopping = false
local hoppingDots = ""
local flying = false

-- chọn team
pcall(function()
    if TEAM == "Pirates" or TEAM == "Marines" then
        if ReplicatedStorage:FindFirstChild("Remotes") and ReplicatedStorage.Remotes:FindFirstChild("CommF_") then
            ReplicatedStorage.Remotes.CommF_:InvokeServer("SetTeam", TEAM)
        end
    end
end)

-- fps boost
if FPSBOOST then
    pcall(function() SoundService.Volume = 0 end)
    pcall(function() settings().Rendering.QualityLevel = Enum.QualityLevel.Level02 end)
    for _,obj in pairs(workspace:GetDescendants()) do
        if obj:IsA("Decal") or obj:IsA("Texture") then
            pcall(function() obj:Destroy() end)
        elseif obj:IsA("ParticleEmitter") or obj:IsA("Trail") or obj:IsA("Beam") then
            pcall(function() obj.Enabled = false end)
        elseif obj:IsA("BasePart") then
            pcall(function()
                obj.Material = Enum.Material.SmoothPlastic
                if obj:IsA("MeshPart") then obj.TextureID = "" end
                obj.Reflectance = 0
            end)
        end
    end
end

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
    local text = "HuneIPA Hub - Fruit Finder\n"
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
            if hoppingDots == "" then hoppingDots="."
            elseif hoppingDots=="." then hoppingDots=".."
            elseif hoppingDots==".." then hoppingDots="..."
            else hoppingDots="" end
        else hoppingDots="" end
    end
end)

-- tìm fruit
local function serverNameToPrefix(name)
    if not name then return nil end
    return string.split(name,"-")[1]
end

local function findFruitsInWorkspace()
    local found = {}
    for _,obj in pairs(workspace:GetChildren()) do
        if obj:IsA("Model") and obj:FindFirstChild("Handle") then
            local ok = false
            for _,serverName in ipairs(FRUITS) do
                local prefix = serverNameToPrefix(serverName)
                if prefix and string.find(string.lower(obj.Name), string.lower(prefix)) then
                    ok = true break
                end
            end
            if ok or string.find(string.lower(obj.Name),"fruit") then
                table.insert(found,obj)
            end
        end
    end
    return found
end

-- tween / teleport
local function safeTweenToTarget(target)
    local hrp = Player.Character and Player.Character:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    local pos = target.Position
    local dist = (hrp.Position - pos).Magnitude
    if dist <= 300 then
        hrp.CFrame = CFrame.new(pos+Vector3.new(0,3,0))
        return
    end
    local tweenInfo = TweenInfo.new(dist/TWEENSPEED, Enum.EasingStyle.Linear)
    local tween = TweenService:Create(hrp, tweenInfo, {CFrame=CFrame.new(pos+Vector3.new(0,3,0))})
    tween:Play()
    tween.Completed:Wait()
end

-- store
local function storeAllFruitOnce()
    local backpack = Player:FindFirstChild("Backpack")
    local char = Player.Character
    for _,serverName in ipairs(FRUITS) do
        local prefix = serverNameToPrefix(serverName)
        local obj = (backpack and backpack:FindFirstChild(prefix.." Fruit")) or (char and char:FindFirstChild(prefix.." Fruit"))
        if obj then
            ReplicatedStorage.Remotes.CommF_:InvokeServer("StoreFruit", serverName, obj)
        end
    end
end

-- fly lên
local function startFlying()
    if flying then return end
    flying = true
    spawn(function()
        while flying do
            local hrp = Player.Character and Player.Character:FindFirstChild("HumanoidRootPart")
            if hrp then hrp.CFrame = hrp.CFrame + Vector3.new(0,10,0) end
            task.wait(0.5)
        end
    end)
end
local function stopFlying() flying=false end

-- hop server (ưu tiên server >2h dưới 6 player nếu bật)
local function HopServer()
    if HopOldServer then
        pcall(function()
            local servers = HttpService:JSONDecode(game:HttpGet(
                "https://games.roblox.com/v1/games/"..game.PlaceId.."/servers/Public?sortOrder=Asc&limit=100"))
            for _,s in pairs(servers.data) do
                if s.playing < 6 and s.uptime and s.uptime > 7200 then
                    TeleportService:TeleportToPlaceInstance(game.PlaceId, s.id, Player)
                    return
                end
            end
        end)
    end
    TeleportService:Teleport(game.PlaceId, Player)
end

-- main loop
task.spawn(function()
    task.wait(5)
    while task.wait(0.5) do
        if not Player.Character then continue end
        local fruits = findFruitsInWorkspace()
        if #fruits > 0 then
            for _,fruit in ipairs(fruits) do
                local hrp = Player.Character:FindFirstChild("HumanoidRootPart")
                if not hrp then break end
                local dist = (hrp.Position - fruit.Handle.Position).Magnitude
                UpdateUI("Collecting", fruit.Name, dist)
                safeTweenToTarget(fruit.Handle.CFrame)
                local startTick = tick()
                spawn(function() task.wait(2) startFlying() end)
                while tick()-startTick < 5 do
                    storeAllFruitOnce()
                    UpdateUI("Collecting", fruit.Name, (hrp.Position-fruit.Handle.Position).Magnitude)
                    task.wait(0.5)
                end
                totalFruit+=1
                StarterGui:SetCore("SendNotification",{Title="HuneIPA - Fruit Finder",Text="Find {"..totalFruit.."} fruit on this server",Duration=5})
                hopping=true
                UpdateUI("Hopping")
                task.wait(1)
                HopServer()
                stopFlying()
                hopping=false
                break
            end
        else
            UpdateUI("Idle")
        end
    end
end)
