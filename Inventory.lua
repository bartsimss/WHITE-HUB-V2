-- =====================
-- Inventory.lua
-- Handles item counting, selling, buying, and keep-item logic.
-- Updated for YBA's new dialogue system (v1.7974+).
-- Uses DialogueGui clicking instead of the old EndDialogue remote.
-- =====================

local Players             = game:GetService("Players")
local VirtualInputManager = game:GetService("VirtualInputManager")
local MarketplaceService  = game:GetService("MarketplaceService")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")

local Player    = Players.LocalPlayer
local Inventory = {}

local _config   = nil
local _movement = nil

-- =====================
-- CONSTANTS
-- =====================
local LUCKY_STOP  = 9
local MONEY_STOP  = 1000000
local GAMEPASS_2X = 14597778
local _has2x      = false

-- Maximum item counts per item type (doubled if player owns 2x gamepass)
local MaxItemAmounts = {
    ["Gold Coin"]                      = 45,
    ["Rokakaka"]                       = 25,
    ["Pure Rokakaka"]                  = 10,
    ["Mysterious Arrow"]               = 25,
    ["Diamond"]                        = 30,
    ["Ancient Scroll"]                 = 10,
    ["Caesar's Headband"]              = 10,
    ["Stone Mask"]                     = 10,
    ["Rib Cage of The Saint's Corpse"] = 20,
    ["Quinton's Glove"]                = 10,
    ["Zeppeli's Hat"]                  = 10,
    ["Lucky Arrow"]                    = 10,
    ["Lucky Stone Mask"]               = 10,
    ["Clackers"]                       = 10,
    ["Steel Ball"]                     = 10,
    ["Dio's Diary"]                    = 10,
}

-- =====================
-- INIT
-- =====================
function Inventory:Init(Modules)
    _config   = Modules.Config
    _movement = Modules.Movement

    -- Detect 2x gamepass and double all item caps
    pcall(function()
        _has2x = MarketplaceService:UserOwnsGamePassAsync(Player.UserId, GAMEPASS_2X)
    end)
    if _has2x then
        for k, v in pairs(MaxItemAmounts) do
            MaxItemAmounts[k] = v * 2
        end
        print("[Inventory] 2x gamepass detected — item caps doubled.")
    else
        print("[Inventory] Initialized (no 2x gamepass).")
    end
end

-- =====================
-- ITEM COUNTING
-- =====================

-- Counts how many of a given item the player currently has
-- (checks both Backpack and Character)
function Inventory:Count(name)
    local count = 0

    -- Count in backpack
    if Player.Backpack then
        for _, tool in pairs(Player.Backpack:GetChildren()) do
            if tool.Name == name then
                count = count + 1
            end
        end
    end

    -- Count equipped tools in character
    if Player.Character then
        for _, obj in pairs(Player.Character:GetChildren()) do
            if obj:IsA("Tool") and obj.Name == name then
                count = count + 1
            end
        end
    end

    return count
end

-- Returns true if the player has reached the max cap for the item
function Inventory:HasMax(name)
    local cap = MaxItemAmounts[name]
    if not cap then return false end
    return self:Count(name) >= cap
end

-- Returns the max cap for the given item (or 0 if unknown)
function Inventory:GetMax(name)
    return MaxItemAmounts[name] or 0
end

-- =====================
-- PLAYER STATS HELPERS
-- =====================

-- Returns the player's current money (from PlayerStats)
function Inventory:GetMoney()
    local ok, val = pcall(function()
        return Player.PlayerStats.Money.Value
    end)
    return ok and val or 0
end

-- Phase 1 thresholds
function Inventory:GetLuckyStop()     return LUCKY_STOP end
function Inventory:GetMoneyStop()     return MONEY_STOP end
function Inventory:HasEnoughLucky()   return self:Count("Lucky Arrow") >= LUCKY_STOP end
function Inventory:IsMoneyMaxed()     return self:GetMoney() >= MONEY_STOP end
function Inventory:ShouldStopPhase1() return self:HasEnoughLucky() and self:IsMoneyMaxed() end

-- =====================
-- KEEP ITEMS LOGIC
-- =====================

-- Returns a list of items the user wants to keep (sell = false)
-- Lucky Arrow and Lucky Stone Mask are always excluded
function Inventory:GetKeepItems()
    local sellItems = _config:GetSellItems()
    local list = {}
    for name, sell in pairs(sellItems) do
        if not sell and name ~= "Lucky Arrow" and name ~= "Lucky Stone Mask" then
            table.insert(list, name)
        end
    end
    return list
end

-- Returns true if ALL keep-items are at max capacity
function Inventory:AllKeepItemsFull()
    local keepItems = self:GetKeepItems()
    if #keepItems == 0 then return true end
    for _, name in ipairs(keepItems) do
        if not self:HasMax(name) then
            return false
        end
    end
    return true
end

-- =====================
-- DIALOGUE CLICKING HELPERS
-- (YBA v1.7974+ uses a client-side DialogueGui — no more sell remote)
-- =====================

-- Attempts to click a GuiButton using multiple methods
-- Returns true if at least one method was attempted successfully
local function clickButton(btn)
    if not btn then
        print("[Inventory][DEBUG] clickButton called with nil button")
        return false
    end

    print(("[Inventory][DEBUG] clickButton: %s (Text: '%s', Pos: %s)"):format(btn.Name, tostring(btn.Text), tostring(btn.AbsolutePosition)))

    local firedMethod = false

    -- Method 1: firesignal (fastest, works if executor supports it)
    if typeof(firesignal) == "function" then
        local ok, err = pcall(function()
            firesignal(btn.MouseButton1Click)
            if btn.Activated then
                firesignal(btn.Activated)
            end
        end)
        print(("[Inventory][DEBUG] -> firesignal attempted: ok=%s err=%s"):format(tostring(ok), tostring(err)))
        if ok then firedMethod = true end
    else
        print("[Inventory][DEBUG] -> firesignal not available in executor.")
    end

    -- Method 2: VirtualInputManager (physical click via screen coords)
    local ok2, err2 = pcall(function()
        local absPos  = btn.AbsolutePosition
        local absSize = btn.AbsoluteSize
        local x = absPos.X + absSize.X / 2
        local y = absPos.Y + absSize.Y / 2

        VirtualInputManager:SendMouseButtonEvent(x, y, 0, true,  game, 1)
        task.wait(0.05)
        VirtualInputManager:SendMouseButtonEvent(x, y, 0, false, game, 1)
    end)
    print(("[Inventory][DEBUG] -> VirtualInputManager attempted: ok=%s err=%s"):format(tostring(ok2), tostring(err2)))
    if ok2 then firedMethod = true end

    return firedMethod
end

local function dumpGuiHierarchy(root, maxDepth, currentDepth)
    maxDepth = maxDepth or 3
    currentDepth = currentDepth or 0
    if currentDepth > maxDepth then return end

    for _, child in ipairs(root:GetChildren()) do
        local info = child.ClassName .. " '" .. child.Name .. "'"
        if child:IsA("TextLabel") or child:IsA("TextButton") then
            info = info .. " [Text: '" .. tostring(child.Text) .. "']"
        end
        if child:IsA("GuiObject") then
            info = info .. " [Visible: " .. tostring(child.Visible) .. "]"
        end
        print(string.rep("  ", currentDepth + 1) .. info)
        dumpGuiHierarchy(child, maxDepth, currentDepth + 1)
    end
end

local function advanceDialogue(dlg)
    if not dlg then
        dlg = Player.PlayerGui and Player.PlayerGui:FindFirstChild("DialogueGui")
    end
    if not dlg then return end

    -- 1. Click ClickContinue button if visible
    local clickContinue = dlg:FindFirstChild("ClickContinue", true)
    if clickContinue and clickContinue:IsA("GuiButton") and clickContinue.Visible then
        print("[Inventory][DEBUG] Pressing ClickContinue to skip dialogue...")
        clickButton(clickContinue)
        return
    end

    -- 2. Physical mouse click on screen (advances typewriter / prompts in YBA)
    pcall(function()
        VirtualInputManager:SendMouseButtonEvent(0, 8, 0, true, nil, 1)
        task.wait(0.04)
        VirtualInputManager:SendMouseButtonEvent(0, 8, 0, false, nil, 1)
    end)
end

-- Waits for a specific option name (e.g. "Option1", "Option6") to appear in DialogueGui.Frame.Options,
-- pulsing dialogue advance clicks while waiting.
local function waitAndClickOption(targetOptionName, timeout, fallbackText)
    timeout = timeout or 4
    local start = tick()
    print(("[Inventory][DEBUG] waitAndClickOption: Looking for %s (fallbackText: %s, timeout: %ds)..."):format(targetOptionName, tostring(fallbackText), timeout))

    while tick() - start < timeout do
        local dlg = Player.PlayerGui and Player.PlayerGui:FindFirstChild("DialogueGui")
        if dlg then
            local opts = dlg:FindFirstChild("Options", true)
            if opts and #opts:GetChildren() > 0 then
                -- 1. Direct name match (e.g. "Option1", "Option6")
                local opt = opts:FindFirstChild(targetOptionName)
                if opt then
                    local btn = opt:IsA("GuiButton") and opt or opt:FindFirstChildWhichIsA("GuiButton", true)
                    if btn and btn.Visible ~= false then
                        local text = btn:IsA("TextButton") and btn.Text or ""
                        print(("[Inventory][DEBUG] Found target %s (Text: '%s') -> Clicking!"):format(targetOptionName, text))
                        clickButton(btn)
                        return true
                    end
                end

                -- 2. Fallback text search if provided
                if fallbackText then
                    for _, child in ipairs(opts:GetChildren()) do
                        local btn = child:IsA("GuiButton") and child or child:FindFirstChildWhichIsA("GuiButton", true)
                        if btn and btn.Visible ~= false then
                            local btnText = btn:IsA("TextButton") and btn.Text or ""
                            if btnText:lower():find(fallbackText:lower(), 1, true) then
                                print(("[Inventory][DEBUG] Found fallback text match '%s' on %s (Text: '%s') -> Clicking!"):format(fallbackText, child.Name, btnText))
                                clickButton(btn)
                                return true
                            end
                        end
                    end
                end

                -- 3. If target was Option6, fallback to clicking the last option child
                if targetOptionName == "Option6" then
                    local children = opts:GetChildren()
                    local last = children[#children]
                    if last then
                        local btn = last:IsA("GuiButton") and last or last:FindFirstChildWhichIsA("GuiButton", true)
                        if btn and btn.Visible ~= false then
                            local text = btn:IsA("TextButton") and btn.Text or ""
                            print(("[Inventory][DEBUG] Option6 fallback: Clicking last option %s (Text: '%s')"):format(last.Name, text))
                            clickButton(btn)
                            return true
                        end
                    end
                end
            end

            -- Skip dialogue / press in the middle
            advanceDialogue(dlg)
        end
        task.wait(0.15)
    end

    warn(("[Inventory][DEBUG] ❌ Timed out waiting for %s"):format(targetOptionName))
    local dlg = Player.PlayerGui and Player.PlayerGui:FindFirstChild("DialogueGui")
    if dlg then
        dumpGuiHierarchy(dlg)
    end
    return false
end

-- =====================
-- SELL ALL
-- Sells every item marked as "sell = true" in the config.
-- Walks through the new dialogue flow:
--   1. "I'd like to sell this..."
--   2. "Deal."
--   3. "I'll sell ALL of these."
-- =====================
function Inventory:SellAll()
    print("[Inventory][DEBUG] ========== SellAll() START ==========")

    -- Guard clauses
    local farmEnabled = _config and _config:Get("FarmEnabled")
    print("[Inventory][DEBUG] Guard check - FarmEnabled: " .. tostring(farmEnabled))
    if not farmEnabled then
        print("[Inventory][DEBUG] Aborting: FarmEnabled is false.")
        return
    end

    local currentMoney = self:GetMoney()
    local isMaxed = self:IsMoneyMaxed()
    print(("[Inventory][DEBUG] Guard check - Money: %d / %d (IsMoneyMaxed: %s)"):format(currentMoney, MONEY_STOP, tostring(isMaxed)))
    if isMaxed then
        print("[Inventory] Money already maxed — skipping sell.")
        return
    end

    local autoSell = _config and _config:Get("AutoSell")
    print("[Inventory][DEBUG] Guard check - AutoSell: " .. tostring(autoSell))
    if not autoSell then
        print("[Inventory] AutoSell disabled — skipping sell.")
        return
    end

    -- Build list of items to sell
    local sellItems = _config:GetSellItems()
    local toSell = {}

    print("[Inventory][DEBUG] Evaluating configured SellItems:")
    for name, sell in pairs(sellItems) do
        local count = self:Count(name)
        print(("[Inventory][DEBUG]   • %s: SellConfig=%s, Owned=%d"):format(tostring(name), tostring(sell), count))
        if sell and count > 0 then
            table.insert(toSell, name)
        end
    end

    print(("[Inventory][DEBUG] Items to sell count: %d -> [%s]"):format(#toSell, table.concat(toSell, ", ")))
    if #toSell == 0 then
        print("[Inventory] No items to sell.")
        return
    end

    print("[Inventory] Selling " .. #toSell .. " item type(s)...")

    -- Locate the Merchant ProximityPrompt
    print("[Inventory][DEBUG] Searching for Merchant ProximityPrompt...")
    local merchantPrompt
    local dlgFolder = workspace:FindFirstChild("Dialogues")
    if dlgFolder then
        print("[Inventory][DEBUG] Found workspace.Dialogues folder.")
        local merchant = dlgFolder:FindFirstChild("ShiftPlox, The Travelling Merchant")
        if merchant then
            print("[Inventory][DEBUG] Found merchant model in Dialogues: " .. merchant:GetFullName())
            merchantPrompt = merchant:FindFirstChildWhichIsA("ProximityPrompt", true)
            if merchantPrompt then
                print("[Inventory][DEBUG] Found ProximityPrompt via Dialogues folder: " .. merchantPrompt:GetFullName())
            else
                print("[Inventory][DEBUG] No ProximityPrompt inside merchant model in Dialogues.")
            end
        else
            print("[Inventory][DEBUG] 'ShiftPlox, The Travelling Merchant' not found directly in workspace.Dialogues.")
            local childrenNames = {}
            for _, c in ipairs(dlgFolder:GetChildren()) do table.insert(childrenNames, c.Name) end
            print("[Inventory][DEBUG] workspace.Dialogues children: " .. table.concat(childrenNames, ", "))
        end
    else
        print("[Inventory][DEBUG] workspace.Dialogues folder NOT found.")
    end

    -- Fallback: search workspace
    if not merchantPrompt then
        print("[Inventory][DEBUG] Running fallback scan across workspace for merchant model...")
        for _, obj in ipairs(workspace:GetDescendants()) do
            if obj:IsA("Model") and (obj.Name:find("ShiftPlox") or obj.Name:find("Merchant")) then
                print("[Inventory][DEBUG] Found candidate merchant model in workspace: " .. obj:GetFullName())
                local pp = obj:FindFirstChildWhichIsA("ProximityPrompt", true)
                if pp then
                    merchantPrompt = pp
                    print("[Inventory][DEBUG] Found ProximityPrompt in fallback model: " .. pp:GetFullName())
                    break
                end
            end
        end
    end

    if not merchantPrompt then
        warn("[Inventory] ❌ Merchant ProximityPrompt not found — cannot sell.")
        return
    end

    -- Diagnostic: Check player distance to Merchant Prompt
    local promptPart = merchantPrompt.Parent and merchantPrompt.Parent:IsA("BasePart") and merchantPrompt.Parent
    local charRoot = Player.Character and Player.Character:FindFirstChild("HumanoidRootPart")
    if promptPart and charRoot then
        local dist = (promptPart.Position - charRoot.Position).Magnitude
        print(("[Inventory][DEBUG] Distance to Merchant: %.1f studs (MaxActivationDistance: %.1f)"):format(dist, merchantPrompt.MaxActivationDistance))
        if dist > merchantPrompt.MaxActivationDistance then
            warn(("[Inventory][DEBUG] ⚠️ Player is far from merchant (%.1f > %.1f)! Prompt might not fire if distance check is enforced."):format(dist, merchantPrompt.MaxActivationDistance))
        end
    end

    local soldCount   = 0
    local failedCount = 0

    -- Sell each item type
    for i, itemName in ipairs(toSell) do
        print(("[Inventory][DEBUG] [%d/%d] Processing item: %s"):format(i, #toSell, itemName))
        local countBefore = self:Count(itemName)

        -- Re-fetch the tool (might be in backpack or equipped)
        local tool = Player.Backpack:FindFirstChild(itemName)
        if not tool and Player.Character then
            tool = Player.Character:FindFirstChild(itemName)
        end

        if not tool then
            warn("[Inventory][DEBUG] ❌ Could not find tool instance for: " .. itemName)
            failedCount = failedCount + 1
        else
            print(("[Inventory][DEBUG] Found tool %s in %s"):format(itemName, tool.Parent.Name))

            -- Equip the item so the server knows which one to sell
            local char = Player.Character
            local hum  = char and char:FindFirstChildWhichIsA("Humanoid")
            if hum and tool.Parent == Player.Backpack then
                print("[Inventory][DEBUG] Equipping " .. itemName .. "...")
                hum:EquipTool(tool)
                task.wait(0.3)
                print("[Inventory][DEBUG] Tool equipped. Current parent: " .. tostring(tool.Parent and tool.Parent.Name))
            end

            -- Open the dialogue via ProximityPrompt
            print("[Inventory][DEBUG] Firing merchant ProximityPrompt...")
            if typeof(fireproximityprompt) ~= "function" then
                warn("[Inventory][DEBUG] ⚠️ fireproximityprompt is NOT a global function in this executor!")
            end
            local ppOk, ppErr = pcall(function() fireproximityprompt(merchantPrompt) end)
            print(("[Inventory][DEBUG] fireproximityprompt executed: ok=%s, err=%s"):format(tostring(ppOk), tostring(ppErr)))
            task.wait(0.8)

            -- Step 1: "I'd like to sell this..." -> Option1
            print("[Inventory][DEBUG] Step 1: Selecting Option1 ('I'd like to sell this')...")
            local step1 = waitAndClickOption("Option1", 4, "sell")
            print("[Inventory][DEBUG] Step 1 result: " .. tostring(step1))
            task.wait(0.4)

            -- Step 2: "Deal." -> Option1
            if step1 then
                print("[Inventory][DEBUG] Step 2: Selecting Option1 ('Deal.')...")
                local step2 = waitAndClickOption("Option1", 4, "deal")
                print("[Inventory][DEBUG] Step 2 result: " .. tostring(step2))
                task.wait(0.4)

                -- Step 3: "I'll sell ALL of these." -> Option6
                if step2 then
                    print("[Inventory][DEBUG] Step 3: Selecting Option6 ('Sell ALL')...")
                    local step3 = waitAndClickOption("Option6", 4, "all")
                    print("[Inventory][DEBUG] Step 3 result: " .. tostring(step3))

                    task.wait(1.2)

                    -- Verify the item was actually sold
                    local countAfter = self:Count(itemName)
                    print(("[Inventory][DEBUG] Verification for %s: before=%d, after=%d"):format(itemName, countBefore, countAfter))

                    local stillHas = Player.Backpack:FindFirstChild(itemName)
                    if not stillHas and Player.Character then
                        stillHas = Player.Character:FindFirstChild(itemName)
                    end

                    if not stillHas or countAfter < countBefore then
                        soldCount = soldCount + 1
                        print("[Inventory] ✅ Sold: " .. itemName)
                    else
                        failedCount = failedCount + 1
                        warn("[Inventory] ❌ Failed to sell: " .. itemName .. " (Item still in inventory)")
                    end
                else
                    failedCount = failedCount + 1
                    warn("[Inventory] ❌ Step 2 (Option1 - Deal) failed for: " .. itemName)
                end
            else
                failedCount = failedCount + 1
                warn("[Inventory] ❌ Step 1 (Option1 - Sell) failed for: " .. itemName)
            end

            task.wait(0.3)
        end
    end

    print(("[Inventory] SellAll done — Sold: " .. soldCount .. " | Failed: " .. failedCount))
    print("[Inventory][DEBUG] ========== SellAll() END ==========")
end

-- =====================
-- BUY LUCKY ARROWS
-- =====================
function Inventory:BuyLucky()
    if not _config:Get("FarmEnabled") then return end
    if not _config:Get("BuyLucky")     then return end
    if self:Count("Lucky Arrow") >= LUCKY_STOP then return end

    local money = self:GetMoney()
    if money < 75000 then return end

    print("[Inventory] Buying Lucky Arrows... ($" .. money .. ")")
    local attempts = 0

    while self:GetMoney() >= 75000 and attempts < 15 do
        pcall(function()
            local char = Player.Character
            if not char then return end
            local re = char:FindFirstChild("RemoteEvent")
            if not re then return end
            re:FireServer("PurchaseShopItem", { ItemName = "1x Lucky Arrow" })
        end)
        task.wait(1)
        attempts = attempts + 1

        local count = self:Count("Lucky Arrow")
        print("[Inventory] Lucky Arrows: " .. count .. "/" .. LUCKY_STOP)

        if count >= LUCKY_STOP then
            print("[Inventory] Reached " .. LUCKY_STOP .. " Lucky Arrows — stopping purchase (YBA bug).")
            break
        end
    end
end

-- =====================
-- STAND UTILITIES (used by CombatFarm)
-- =====================

-- Returns the name of the player's currently equipped stand
function Inventory:GetCurrentStand()
    if Player and Player.PlayerStats and Player.PlayerStats.Stand then
        return Player.PlayerStats.Stand.Value
    end
    return "None"
end

-- Returns true if the player has any stand equipped
function Inventory:HasStand()
    return self:GetCurrentStand() ~= "None"
end

-- Attempts to summon the stand if it is currently unsummoned.
-- Returns true if the stand was summoned by this call.
function Inventory:SummonStand()
    local char = Player.Character
    if not char then return false end

    local remoteFunc = char:FindFirstChild("RemoteFunction")
    if not remoteFunc then return false end

    local summoned = char:FindFirstChild("SummonedStand")
    if summoned and summoned.Value == false then
        remoteFunc:InvokeServer("ToggleStand", "Toggle")
        task.wait(0.3)
        return true
    end

    return false
end

return Inventory
