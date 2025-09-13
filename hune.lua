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

local TEAM = Config.Team or "Pirates"
local FPSBOOST = Config.FPSBOOST or false
local FRUITS = Config.Fruits or {}
local TWEENSPEED = 350

local totalFruit = 0
local hopping = false
local hoppingDots = ""
local flying = false

local function isDescendantOfPlayer(obj)
    if not obj then return false end
    local ancestor = obj
    while ancestor and ancestor ~= workspace do
        local pl = Players:GetPlayerFromCharacter(ancestor)
        if pl then return true end
        ancestor = ancestor.Parent
    end
    return false
end

pcall(function()
    if TEAM == "Pirates" or TEAM == "Marines" then
        if ReplicatedStorage and ReplicatedStorage:FindFirstChild("Remotes") and ReplicatedStorage.Remotes:FindFirstChild("CommF_") then
            pcall(function()
                ReplicatedStorage.Remotes.CommF_:InvokeServer("SetTeam", TEAM)
            end)
        end
    end
end)

if FPSBOOST then
    pcall(function()
        pcall(function() SoundService.Volume = 0 end)
        if settings and settings().Rendering then
            pcall(function() settings().Rendering.QualityLevel = Enum.QualityLevel.Level02 end)
        end
        for _,obj in pairs(workspace:GetDescendants()) do
            if isDescendantOfPlayer(obj) then
            else
                if obj:IsA("Decal") or obj:IsA("Texture") then
                    pcall(function() obj:Destroy() end)
                elseif obj:IsA("ParticleEmitter") or obj:IsA("Trail") or obj:IsA("Beam") then
                    pcall(function() obj.Enabled = false end)
                elseif obj:IsA("BasePart") then
                    pcall(function()
                        obj.Material = Enum.Material.SmoothPlastic
                        if obj:IsA("MeshPart") then
                            obj.TextureID = ""
                        end
                        obj.Reflectance = 0
                    end)
                end
            end
        end
    end)
end

pcall(function()
    StarterGui:SetCore("SendNotification", {Title = "HuneIPA - Fruit Finder", Text = "Load successly", Duration = 5})
end)

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
        else
            hoppingDots = ""
        end
    end
end)

local function serverNameToPrefix(serverName)
    if type(serverName) ~= "string" then return serverName end
    local prefix = serverName:match("^(.*)%-(.-)$")
    if prefix and prefix ~= "" then return prefix end
    return serverName
end

local function findFruitsInWorkspace()
    local found = {}
    for _,obj in pairs(workspace:GetDescendants()) do
        if obj:IsA("Model") and obj:FindFirstChild("Handle") then
            for _,serverName in ipairs(FRUITS) do
                local prefix = serverNameToPrefix(serverName)
                if prefix and string.find(string.lower(obj.Name), string.lower(prefix), 1, true) then
                    table.insert(found, obj)
                    break
                end
            end
        end
    end
    return found
end

local function safeTweenToTarget(targetCFrame)
    if not Player or not Player.Character then return end
    local hrp = Player.Character:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    local pos = nil
    if typeof(targetCFrame) == "CFrame" then pos = targetCFrame.Position elseif typeof(targetCFrame) == "Vector3" then pos = targetCFrame else return end
    local target = CFrame.new(pos + Vector3.new(0,3,0))
    local distance = (hrp.Position - pos).Magnitude
    if distance <= 300 then
        pcall(function() hrp.CFrame = target end)
        return
    end
    local tweenInfo = TweenInfo.new(distance / TWEENSPEED, Enum.EasingStyle.Linear)
    local ok, tween = pcall(function() return TweenService:Create(hrp, tweenInfo, {CFrame = target}) end)
    if ok and tween then
        pcall(function()
            tween:Play()
            tween.Completed:Wait()
        end)
    else
        pcall(function() hrp.CFrame = target end)
    end
end

local function storeAllFruitOnce()
    local backpack = Player and Player:FindFirstChild("Backpack")
    local char = Player and Player.Character
    for _, serverName in ipairs(FRUITS) do
        local prefix = serverNameToPrefix(serverName)
        local candidates = {}
        table.insert(candidates, prefix .. " Fruit")
        table.insert(candidates, prefix)
        for _,cname in ipairs(candidates) do
            local obj = (backpack and backpack:FindFirstChild(cname)) or (char and char:FindFirstChild(cname))
            if obj then
                pcall(function()
                    ReplicatedStorage.Remotes.CommF_:InvokeServer("StoreFruit", serverName, obj)
                end)
                break
            end
        end
    end
end

local function startFlying()
    if flying then return end
    flying = true
    spawn(function()
        while flying do
            if Player and Player.Character then
                local hrp = Player.Character:FindFirstChild("HumanoidRootPart")
                if hrp then
                    pcall(function() hrp.CFrame = hrp.CFrame + Vector3.new(0,10,0) end)
                end
            end
            task.wait(0.5)
        end
    end)
end

local function stopFlying()
    flying = false
end

local function HopServer()
    pcall(function() TeleportService:Teleport(game.PlaceId, Player) end)
end

task.spawn(function()
    task.wait(5)
    while task.wait(0.5) do
        if not Player or not Player.Character then continue end
        local fruitsFound = findFruitsInWorkspace()
        if #fruitsFound > 0 then
            for _,fruitModel in ipairs(fruitsFound) do
                if not Player or not Player.Character then break end
                local hrp = Player.Character:FindFirstChild("HumanoidRootPart")
                if not hrp then break end
                local dist = (hrp.Position - fruitModel.Handle.Position).Magnitude
                UpdateUI("Collecting", fruitModel.Name, dist)
                safeTweenToTarget(fruitModel.Handle.CFrame)
                local startTick = tick()
                spawn(function()
                    task.wait(2)
                    startFlying()
                end)
                while tick() - startTick < 5 do
                    storeAllFruitOnce()
                    task.wait(0.5)
                end
                totalFruit = totalFruit + 1
                pcall(function()
                    StarterGui:SetCore("SendNotification", {
                        Title = "HuneIPA - Fruit Finder",
                        Text = "Find {" .. tostring(totalFruit) .. "} fruit on this server",
                        Duration = 5
                    })
                end)
                hopping = true
                UpdateUI("Hopping")
                task.wait(1)
                HopServer()
                stopFlying()
                hopping = false
                break
            end
        else
            UpdateUI("Idle")
        end
    end
end)
