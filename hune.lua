local Players = game:GetService("Players")
local Player = Players.LocalPlayer
local Workspace = game:GetService("Workspace")
local StarterGui = game:GetService("StarterGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CoreGui = game:GetService("CoreGui")
local TeleportService = game:GetService("TeleportService")
local TweenService = game:GetService("TweenService")

local Config = getgenv().Config or {}
local Team = Config.Team or "Pirates"
local FPSBOOST = Config.FPSBOOST or false
local FruitList = Config.Fruits or {}

local hopping = false
local hoppingDots = ""
local totalFruit = 0
local TweenSpeed = 350

pcall(function()
    if Team == "Pirates" then
        ReplicatedStorage.Remotes.CommF_:InvokeServer("SetTeam","Pirates")
    elseif Team == "Marines" then
        ReplicatedStorage.Remotes.CommF_:InvokeServer("SetTeam","Marines")
    end
end)

if FPSBOOST then
    settings().Rendering.QualityLevel = Enum.QualityLevel.Level02
    for _, obj in pairs(workspace:GetDescendants()) do
        if obj:IsA("Decal") or obj:IsA("Texture") then
            obj:Destroy()
        elseif obj:IsA("BasePart") then
            obj.Material = Enum.Material.SmoothPlastic
            obj.Color = obj.Color
        end
    end
    task.wait(5)
    StarterGui:SetCore("SendNotification", {
        Title = "HuneIPA - Fruit Finder",
        Text = "Load successly",
        Duration = 5
    })
end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "FruitFinderUI"
screenGui.IgnoreGuiInset = true
screenGui.ResetOnSpawn = false
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

local function UpdateUI(status, fruitName, distance)
    local text = "HunelPA Hub - Fruit Finder\n"
    text = text .. "Player in server: " .. #Players:GetPlayers() .. "/12\n"
    if status == "Collecting" then
        text = text .. "Status: Collecting " .. fruitName:lower() .. " fruit (" .. math.floor(distance) .. "m)\n"
    elseif status == "Hopping" then
        text = text .. "Status: Hopping" .. hoppingDots .. "\n"
    else
        text = text .. "Status: Idle\n"
    end
    text = text .. "JobID: " .. game.JobId .. "\n"
    text = text .. "Total fruit: {" .. totalFruit .. "}\n"
    label.Text = text
end

spawn(function()
    while task.wait(0.5) do
        if hopping then
            if hoppingDots == "" then
                hoppingDots = "."
            elseif hoppingDots == "." then
                hoppingDots = ".."
            elseif hoppingDots == ".." then
                hoppingDots = "..."
            else
                hoppingDots = ""
            end
        else
            hoppingDots = ""
        end
    end
end)

function TweenTo(pos)
    local hrp = Player.Character and Player.Character:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    local distance = (pos.Position - hrp.Position).Magnitude
    if distance <= 300 then
        hrp.CFrame = pos
    else
        local tween = TweenService:Create(
            hrp,
            TweenInfo.new(distance / TweenSpeed, Enum.EasingStyle.Linear),
            { CFrame = pos }
        )
        tween:Play()
        tween.Completed:Wait()
    end
end

-- store fruit
function StoreAllFruit()
    local backpack = Player.Backpack
    local character = Player.Character
    for _, fruitName in ipairs(FruitList) do
        local obj = backpack:FindFirstChild(fruitName) or character:FindFirstChild(fruitName)
        if obj then
            pcall(function()
                ReplicatedStorage.Remotes.CommF_:InvokeServer("StoreFruit", fruitName, obj)
            end)
        end
    end
end

function FlyUp()
    local hrp = Player.Character and Player.Character:FindFirstChild("HumanoidRootPart")
    if hrp then
        hrp.CFrame = hrp.CFrame + Vector3.new(0,50,0)
    end
end

function Hop()
    TeleportService:Teleport(game.PlaceId, Player)
end

spawn(function()
    while task.wait(0.5) do
        local foundFruit = false
        for _, v in ipairs(Workspace:GetChildren()) do
            if v:IsA("Model") and v:FindFirstChild("Handle") and table.find(FruitList,v.Name) then
                foundFruit = true
                local distance = (Player.Character.HumanoidRootPart.Position - v.Handle.Position).Magnitude
                UpdateUI("Collecting", v.Name, distance)
                TweenTo(v.Handle.CFrame)
                local start = tick()
                while tick() - start < 5 do
                    StoreAllFruit()
                    task.wait(0.5)
                end
                task.wait(2)
                FlyUp()
                totalFruit += 1
                StarterGui:SetCore("SendNotification", {
                    Title = "HuneIPA - Fruit Finder",
                    Text = "Find {" .. totalFruit .. "} fruit on this server",
                    Duration = 5
                })
                hopping = true
                UpdateUI("Hopping")
                task.wait(3)
                Hop()
                hopping = false
                break
            end
        end
        if not foundFruit then
            UpdateUI("Idle")
        end
    end
end)
