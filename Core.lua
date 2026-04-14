local addonName, GPFM = ...

GPFM.Version = "1.3.0"

-- ============================================================================
-- Utility: Clamp
-- ============================================================================
local function Clamp(value, minVal, maxVal)
    if minVal > maxVal then minVal, maxVal = maxVal, minVal end
    return math.max(minVal, math.min(maxVal, value))
end

-- ============================================================================
-- Debug
-- ============================================================================
function GPFM.Debug(...)
    if GPFM.debugMode then
        print("|cFF00FF00[GPFM]|r", ...)
    end
end

-- ============================================================================
-- Event Frame
-- ============================================================================
local EventFrame = CreateFrame("Frame")
GPFM.EventFrame = EventFrame

GPFM.selectedIndex = 1
GPFM.nodes = {}
GPFM.filteredNodes = {}
GPFM.showUnreachable = false
GPFM.searchText = ""
GPFM.currentHighlightPin = nil
GPFM.currentHighlightProvider = nil
GPFM.pendingShowTimer = nil
GPFM.pendingShowAttempts = 0
GPFM.cachedProvider = nil
GPFM.cachedPinMap = nil

-- ============================================================================
-- Taxi Node Data
-- ============================================================================
function GPFM.GetAllTaxiNodes()
    local mapID = GetTaxiMapID()
    if not mapID then return {} end
    local ok, result = pcall(C_TaxiMap.GetAllTaxiNodes, mapID)
    if not ok then return {} end
    return result or {}
end

function GPFM.RefreshNodes()
    GPFM.nodes = GPFM.GetAllTaxiNodes()
    GPFM.Debug("RefreshNodes: got", #GPFM.nodes, "nodes, mapID:", GetTaxiMapID())
    GPFM.ApplyFilter()
end

function GPFM.ApplyFilter()
    GPFM.filteredNodes = {}
    for _, node in ipairs(GPFM.nodes) do
        -- Always filter out current location
        if node.state == Enum.FlightPathState.Current then
            -- skip
        else
            local passReachable = GPFM.showUnreachable or node.state ~= Enum.FlightPathState.Unreachable
            local passSearch = true
            if GPFM.searchText and GPFM.searchText ~= "" then
                local name = node.name or ""
                passSearch = name:lower():find(GPFM.searchText:lower(), 1, true) ~= nil
            end
            if passReachable and passSearch then
                table.insert(GPFM.filteredNodes, node)
            end
        end
    end

    -- Smart sort: Reachability > Usage Frequency > Distance > Name
    local flightStats = GamePadFlightMapDB and GamePadFlightMapDB.flightStats or {}
    local centerX, centerY = 0.5, 0.5 -- Player position proxy on flight map

    table.sort(GPFM.filteredNodes, function(a, b)
        -- 1. Reachability: Reachable > Unreachable
        local aReach = (a.state == Enum.FlightPathState.Reachable) and 1 or 0
        local bReach = (b.state == Enum.FlightPathState.Reachable) and 1 or 0
        if aReach ~= bReach then return aReach > bReach end

        --[[ 2. Favorites (disabled)
        local aFav = (flightStats.favorites and flightStats.favorites[a.name]) and 1 or 0
        local bFav = (flightStats.favorites and flightStats.favorites[b.name]) and 1 or 0
        if aFav ~= bFav then return aFav > bFav end
        ]]

        -- 3. Usage frequency: more used first
        local aCount = flightStats[a.name] or 0
        local bCount = flightStats[b.name] or 0
        if aCount ~= bCount then return aCount > bCount end

        -- 4. Distance: closer first (only when difference is meaningful)
        local aDist = math.sqrt(((a.x or 0) - centerX) ^ 2 + ((a.y or 0) - centerY) ^ 2)
        local bDist = math.sqrt(((b.x or 0) - centerX) ^ 2 + ((b.y or 0) - centerY) ^ 2)
        if math.abs(aDist - bDist) > 0.0001 then return aDist < bDist end

        -- 5. Alphabetical fallback
        return (a.name or "") < (b.name or "")
    end)

    if #GPFM.filteredNodes == 0 then
        GPFM.selectedIndex = 1
    else
        GPFM.selectedIndex = Clamp(GPFM.selectedIndex, 1, #GPFM.filteredNodes)
    end
end

function GPFM.GetSelectedNode()
    return GPFM.filteredNodes[GPFM.selectedIndex]
end

-- ============================================================================
-- Map Pin Highlight Sync
-- ============================================================================

-- Build pin mapping by enumerating pins, and find the real provider from pin.owner
function GPFM.BuildPinCache()
    if not FlightMapFrame then return end

    local pinMap = {}
    local realProvider = nil
    local pinCount = 0

    -- Enumerate all flight point pins
    if FlightMapFrame.EnumeratePinsByTemplate then
        for pin in FlightMapFrame:EnumeratePinsByTemplate("FlightMap_FlightPointPinTemplate") do
            if pin.taxiNodeData and pin.taxiNodeData.slotIndex then
                pinMap[pin.taxiNodeData.slotIndex] = pin
                pinCount = pinCount + 1
                -- Get the real data provider from pin.owner
                if not realProvider and pin.owner then
                    realProvider = pin.owner
                end
            end
        end
    end

    GPFM.cachedPinMap = pinMap
    GPFM.cachedProvider = realProvider

    GPFM.Debug("BuildPinCache:", pinCount, "pins, realProvider:", realProvider ~= nil,
        "hasHighlightRoute:", realProvider and realProvider.HighlightRouteToPin ~= nil)
end

-- Clear cache when overlay hides
function GPFM.ClearPinCache()
    GPFM.cachedPinMap = nil
    GPFM.cachedProvider = nil
end

function GPFM.GetPinBySlotIndex(slotIndex)
    -- Use cache
    if GPFM.cachedPinMap then
        return GPFM.cachedPinMap[slotIndex]
    end
    -- Build cache first
    GPFM.BuildPinCache()
    return GPFM.cachedPinMap and GPFM.cachedPinMap[slotIndex]
end

function GPFM.GetRealProvider()
    if GPFM.cachedProvider then
        return GPFM.cachedProvider
    end
    GPFM.BuildPinCache()
    return GPFM.cachedProvider
end

function GPFM.HighlightPinOnMap(node)
    if not node then return end

    GPFM.ClearPinHighlight()

    local pin = GPFM.GetPinBySlotIndex(node.slotIndex)
    if not pin then
        GPFM.Debug("Pin not found for slotIndex:", node.slotIndex)
        return
    end

    GPFM.currentHighlightPin = pin

    local provider = GPFM.GetRealProvider()
    GPFM.currentHighlightProvider = provider

    -- Only highlight reachable nodes
    if node.state == Enum.FlightPathState.Reachable then
        -- Change icon to yellow
        if pin.Icon and pin.atlasFormat then
            pin.Icon:SetAtlas(pin.atlasFormat:format("Taxi_Frame_Yellow"))
        end

        -- Draw flight route lines via the real data provider
        if provider and provider.HighlightRouteToPin then
            GPFM.Debug("Calling provider:HighlightRouteToPin")
            provider:HighlightRouteToPin(pin)
        else
            GPFM.Debug("No provider.HighlightRouteToPin available")
        end
    end

    -- Show tooltip
    if pin.OnMouseEnter then
        pin:OnMouseEnter()
    end

    GPFM.Debug("Highlighted pin for:", node.name, "reachable:", node.state == Enum.FlightPathState.Reachable)
end

function GPFM.ClearPinHighlight()
    if GPFM.currentHighlightPin then
        local pin = GPFM.currentHighlightPin
        local provider = GPFM.currentHighlightProvider
        local nodeData = pin.taxiNodeData

        if nodeData and nodeData.state == Enum.FlightPathState.Reachable then
            -- Restore icon
            if pin.Icon and pin.atlasFormat then
                if pin.useSpecialReachableIcon then
                    pin.Icon:SetAtlas(pin.atlasFormat:format("Taxi_Frame_Special"))
                else
                    pin.Icon:SetAtlas(pin.atlasFormat:format("Taxi_Frame_Gray"))
                end
            end

            -- Remove flight route lines
            if provider and provider.RemoveRouteToPin then
                provider:RemoveRouteToPin(pin)
            end
        end

        -- Also call OnMouseLeave for full cleanup
        if pin.OnMouseLeave then
            pin:OnMouseLeave()
        end
    end

    -- Hide tooltip
    GameTooltip_Hide()

    GPFM.currentHighlightPin = nil
    GPFM.currentHighlightProvider = nil
end

-- ============================================================================
-- Take Flight
-- ============================================================================
function GPFM.TakeFlight(node)
    if not node then return end
    if node.state == Enum.FlightPathState.Unreachable then
        GPFM.Debug("Cannot fly to unreachable node:", node.name)
        return
    end
    -- Record flight frequency
    if GamePadFlightMapDB and GamePadFlightMapDB.flightStats then
        local name = node.name or "Unknown"
        GamePadFlightMapDB.flightStats[name] = (GamePadFlightMapDB.flightStats[name] or 0) + 1
        GPFM.Debug("Flight stats updated:", name, "=", GamePadFlightMapDB.flightStats[name])
    end
    GPFM.Debug("Flying to:", node.name, "slotIndex:", node.slotIndex)
    TakeTaxiNode(node.slotIndex)
end

-- ============================================================================
-- List Navigation
-- ============================================================================
function GPFM.SelectNode(index)
    if #GPFM.filteredNodes == 0 then return end
    GPFM.selectedIndex = Clamp(index, 1, #GPFM.filteredNodes)
    local node = GPFM.GetSelectedNode()
    if node then
        GPFM.HighlightPinOnMap(node)
        GPFM.UpdateListVisual()
    end
end

function GPFM.SelectPrev()
    GPFM.SelectNode(GPFM.selectedIndex - 1)
end

function GPFM.SelectNext()
    GPFM.SelectNode(GPFM.selectedIndex + 1)
end

-- ============================================================================
-- Cancel pending show timer
-- ============================================================================
function GPFM.CancelPendingShow()
    if GPFM.pendingShowTimer then
        GPFM.pendingShowTimer:Cancel()
        GPFM.pendingShowTimer = nil
    end
    GPFM.pendingShowAttempts = 0
end

-- ============================================================================
-- Show / Hide Overlay
-- ============================================================================
function GPFM.ShowOverlay()
    GPFM.Debug("ShowOverlay called, DB=", GamePadFlightMapDB, "enabled=", GamePadFlightMapDB and GamePadFlightMapDB.enabled)
    if not GamePadFlightMapDB or not GamePadFlightMapDB.enabled then
        GPFM.Debug("ShowOverlay skipped: disabled or DB missing")
        return
    end
    if GPFM.MainFrame and GPFM.MainFrame:IsShown() then
        GPFM.Debug("ShowOverlay skipped: already shown")
        return
    end

    GPFM.Debug("Showing GamePad Flight Map overlay")

    GPFM.RefreshNodes()
    GPFM.CreateOverlay()
    GPFM.BuildPinCache()
    GPFM.MainFrame:Show()
    GPFM.ActivateGamePad()
    -- Reset selection on open, no map highlight
    GPFM.selectedIndex = 1
    GPFM.UpdateListVisual()
end

function GPFM.HideOverlay()
    if not GPFM.MainFrame then return end

    GPFM.Debug("Hiding GamePad Flight Map overlay")
    GPFM.CancelPendingShow()
    GPFM.DeactivateGamePad()
    GPFM.ClearPinHighlight()
    GPFM.ClearPinCache()
    GPFM.MainFrame:Hide()
end

-- ============================================================================
-- Create Overlay Frame
-- ============================================================================
function GPFM.CreateOverlay()
    if GPFM.MainFrame then
        GPFM.RefreshList()
        return
    end

    local frame = CreateFrame("Frame", "GamePadFlightMapOverlay", FlightMapFrame, "BackdropTemplate")
    frame:SetSize(280, 520)
    frame:SetPoint("TOPLEFT", FlightMapFrame, "TOPRIGHT", 4, 0)
    frame:SetPoint("BOTTOM", FlightMapFrame, "BOTTOM", 0, 0)
    frame:SetFrameStrata("DIALOG")
    frame:SetFrameLevel(100)

    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    frame:SetBackdropColor(0, 0, 0, 0.9)

    -- Close on escape
    table.insert(UISpecialFrames, "GamePadFlightMapOverlay")

    -- Title
    frame.Title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    frame.Title:SetPoint("TOP", frame, "TOP", 0, -12)
    frame.Title:SetText("|TInterface\\Icons\\icon_petfamily_flying:16:16:0:0|t 飞行点")

    -- Status line
    frame.StatusText = frame:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    frame.StatusText:SetPoint("TOP", frame.Title, "BOTTOM", 0, -4)
    if GameFontDisable then
        frame.StatusText:SetFont(GameFontDisable:GetFont(), 10)
    end

    -- Search box
    frame.SearchBox = CreateFrame("EditBox", nil, frame, "SearchBoxTemplate")
    frame.SearchBox:SetSize(220, 20)
    frame.SearchBox:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -56)
    frame.SearchBox:SetAutoFocus(false)
    frame.SearchBox:SetScript("OnTextChanged", function(self)
        if SearchBoxTemplate_OnTextChanged then
            SearchBoxTemplate_OnTextChanged(self)
        end
        GPFM.searchText = self:GetText() or ""
        GPFM.ApplyFilter()
        GPFM.SelectNode(1)
        GPFM.RefreshList()
    end)
    frame.SearchBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)

    -- Hint text
    frame.HintText = frame:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    frame.HintText:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 10, 8)
    frame.HintText:SetText("|cFFAAAAAA双击飞行 右键关闭 [X]可达 [Y]搜索|r")

    -- Scroll frame
    frame.ScrollFrame = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    frame.ScrollFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -80)
    frame.ScrollFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -24, 28)

    frame.ScrollChild = CreateFrame("Frame", nil, frame.ScrollFrame)
    frame.ScrollChild:SetWidth(244)
    frame.ScrollFrame:SetScrollChild(frame.ScrollChild)

    -- Mouse scroll wheel
    frame:EnableMouseWheel(true)
    frame:SetScript("OnMouseWheel", function(self, delta)
        if delta > 0 then
            GPFM.SelectPrev()
        else
            GPFM.SelectNext()
        end
    end)

    -- Button pool (on ScrollChild so buttons get clipped by ScrollFrame)
    frame.ScrollChild.buttonPool = {}

    GPFM.MainFrame = frame
    GPFM.RefreshList()
end

-- ============================================================================
-- List Item Button
-- ============================================================================
local BUTTON_HEIGHT = 36
local BUTTON_SPACING = 2

function GPFM.AcquireButton(parent, index)
    local button = parent.buttonPool[index]
    if not button then
        button = CreateFrame("Button", nil, parent)
        button:SetSize(244, BUTTON_HEIGHT)
        button:RegisterForClicks("LeftButtonUp", "RightButtonUp")

        -- Background
        button.Bg = button:CreateTexture(nil, "BACKGROUND")
        button.Bg:SetAllPoints()
        button.Bg:SetColorTexture(0, 0, 0, 0)

        -- Selected indicator (left bar)
        button.SelectedBar = button:CreateTexture(nil, "ARTWORK")
        button.SelectedBar:SetWidth(3)
        button.SelectedBar:SetPoint("LEFT")
        button.SelectedBar:SetPoint("TOP", 0, -2)
        button.SelectedBar:SetPoint("BOTTOM", 0, 2)
        button.SelectedBar:SetColorTexture(0.2, 0.6, 1.0, 0)

        -- Icon
        button.Icon = button:CreateTexture(nil, "ARTWORK")
        button.Icon:SetSize(18, 18)
        button.Icon:SetPoint("LEFT", 8, 0)

        -- Name
        button.Name = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        button.Name:SetPoint("LEFT", button.Icon, "RIGHT", 6, 0)
        button.Name:SetPoint("RIGHT", -40, 0)
        button.Name:SetJustifyH("LEFT")
        button.Name:SetWordWrap(false)

        -- Count text (flight frequency)
        button.CountText = button:CreateFontString(nil, "OVERLAY", "GameFontDisable")
        button.CountText:SetPoint("RIGHT", -6, 0)
        button.CountText:SetJustifyH("RIGHT")
        if GameFontDisable then
            button.CountText:SetFont(GameFontDisable:GetFont(), 9)
        end

        --[[ Star icon for favorites (disabled)
        button.Star = button:CreateTexture(nil, "ARTWORK")
        button.Star:SetSize(14, 14)
        button.Star:SetPoint("RIGHT", -6, 0)
        button.Star:SetTexture("Interface\\COMMON\\FavoritesIcon")
        button.Star:SetDesaturated(true)
        button.Star:Hide()
        ]]

        -- Double-click detection
        button.lastClickTime = 0

        button:SetScript("OnClick", function(self, mouseButton)
            if mouseButton == "RightButton" then
                CloseTaxiMap()
                return
            end
            -- Left click: select + highlight map route
            GPFM.SelectNode(self.index)
            -- Double click: take flight
            local now = GetTime()
            if now - self.lastClickTime < 0.3 then
                GPFM.TakeFlight(GPFM.GetSelectedNode())
                self.lastClickTime = 0
            else
                self.lastClickTime = now
            end
        end)

        button:SetScript("OnEnter", function(self)
            -- Hover only updates list selection visual, NOT map highlight
            GPFM.selectedIndex = self.index
            GPFM.UpdateListVisual()
        end)

        parent.buttonPool[index] = button
    end

    button:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -(index - 1) * (BUTTON_HEIGHT + BUTTON_SPACING))
    button:Show()
    return button
end

-- ============================================================================
-- Refresh / Update List Visual
-- ============================================================================
function GPFM.RefreshList()
    if not GPFM.MainFrame then return end

    -- Hide all existing buttons
    for _, btn in ipairs(GPFM.MainFrame.ScrollChild.buttonPool) do
        btn:Hide()
    end

    -- Update status text
    local reachable = 0
    for _, node in ipairs(GPFM.nodes) do
        if node.state ~= Enum.FlightPathState.Unreachable then
            reachable = reachable + 1
        end
    end
    GPFM.MainFrame.StatusText:SetText(
        string.format("|cFFAAAAAA共 %d 个飞行点，可达 %d|r", #GPFM.nodes, reachable)
    )

    -- Adjust scroll child height
    local totalHeight = #GPFM.filteredNodes * (BUTTON_HEIGHT + BUTTON_SPACING)
    GPFM.MainFrame.ScrollChild:SetHeight(math.max(totalHeight, 1))

    -- Create/update buttons
    local flightStats = GamePadFlightMapDB and GamePadFlightMapDB.flightStats or {}
    for i, node in ipairs(GPFM.filteredNodes) do
        local button = GPFM.AcquireButton(GPFM.MainFrame.ScrollChild, i)
        button.index = i
        button.Name:SetText(node.name or "Unknown")

        -- Show flight count
        local count = flightStats[node.name] or 0
        if count > 0 then
            button.CountText:SetText("|cFF88CCFF" .. count .. "|r")
        else
            button.CountText:SetText("")
        end

        --[[ Show favorite star (disabled)
        local isFav = flightStats.favorites and flightStats.favorites[node.name]
        if isFav then
            button.Star:Show()
            button.CountText:SetPoint("RIGHT", -22, 0)
        else
            button.Star:Hide()
            button.CountText:SetPoint("RIGHT", -6, 0)
        end
        ]]

        local icon
        if node.state == Enum.FlightPathState.Reachable then
            icon = "Interface\\TaxiFrame\\UI-Taxi-Icon-Green"
        else
            icon = "Interface\\TaxiFrame\\UI-Taxi-Icon-Gray"
        end
        button.Icon:SetTexture(icon)

        if node.state == Enum.FlightPathState.Unreachable then
            button.Name:SetTextColor(0.5, 0.5, 0.5)
        elseif node.state == Enum.FlightPathState.Current then
            button.Name:SetTextColor(0.2, 1.0, 0.2)
        else
            button.Name:SetTextColor(1, 1, 1)
        end
    end

    GPFM.UpdateListVisual()
end

function GPFM.UpdateListVisual()
    if not GPFM.MainFrame then return end

    for i, btn in ipairs(GPFM.MainFrame.ScrollChild.buttonPool) do
        if btn:IsShown() then
            if i == GPFM.selectedIndex then
                btn.Bg:SetColorTexture(0.2, 0.6, 1.0, 0.25)
                btn.SelectedBar:SetColorTexture(0.2, 0.6, 1.0, 1.0)
                btn.Name:SetTextColor(0.5, 1.0, 1.0)
            else
                btn.Bg:SetColorTexture(0, 0, 0, 0)
                btn.SelectedBar:SetColorTexture(0.2, 0.6, 1.0, 0)
                local node = GPFM.filteredNodes[i]
                if node then
                    if node.state == Enum.FlightPathState.Unreachable then
                        btn.Name:SetTextColor(0.5, 0.5, 0.5)
                    elseif node.state == Enum.FlightPathState.Current then
                        btn.Name:SetTextColor(0.2, 1.0, 0.2)
                    else
                        btn.Name:SetTextColor(1, 1, 1)
                    end
                end
            end
        end
    end

    GPFM.ScrollToSelected()
end

function GPFM.ScrollToSelected()
    if not GPFM.MainFrame or not GPFM.MainFrame.ScrollFrame then return end
    local sf = GPFM.MainFrame.ScrollFrame
    local visibleHeight = sf:GetHeight()
    local selectedY = (GPFM.selectedIndex - 1) * (BUTTON_HEIGHT + BUTTON_SPACING)
    local currentScroll = sf:GetVerticalScroll()

    if selectedY < currentScroll then
        sf:SetVerticalScroll(selectedY)
    elseif selectedY + BUTTON_HEIGHT > currentScroll + visibleHeight then
        sf:SetVerticalScroll(selectedY + BUTTON_HEIGHT - visibleHeight)
    end
end

-- ============================================================================
-- Toggle Unreachable Filter
-- ============================================================================
function GPFM.ToggleUnreachable()
    GPFM.showUnreachable = not GPFM.showUnreachable
    GPFM.ApplyFilter()
    GPFM.SelectNode(1)
    GPFM.RefreshList()
    GPFM.Debug("Show unreachable:", GPFM.showUnreachable)
end

-- ============================================================================
-- Event Registration
-- ============================================================================
EventFrame:SetScript("OnEvent", function(self, event, ...)
    -- Always log events in debug mode to diagnose issues
    if GPFM.debugMode then
        print("|cFF00FF00[GPFM]|r Event:", event, ...)
    end

    if event == "ADDON_LOADED" then
        local loadedAddon = ...
        if loadedAddon == addonName then
            GPFM:OnLoad()
        end
    elseif event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" then
        local interactionType = ...
        local taxiEnum = Enum and Enum.PlayerInteractionType and Enum.PlayerInteractionType.TaxiNpc
        GPFM.Debug("Interaction type:", interactionType, "TaxiNpc enum:", taxiEnum)

        -- Check if this is a taxi interaction:
        -- 1. Exact enum match, or
        -- 2. FlightMapFrame becomes visible (fallback for changed enum values)
        local isTaxi = (interactionType == taxiEnum)

        if isTaxi then
            GPFM.Debug("Taxi NPC interaction started (enum match)")
        else
            -- Fallback: detect taxi by checking if FlightMapFrame appears shortly after
            GPFM.Debug("Non-taxi interaction, will check if FlightMapFrame appears")
        end

        -- For any interaction near taxi, schedule a check
        -- (some WoW versions use different enum values, or fire multiple events)
        GPFM.CancelPendingShow()
        GPFM.pendingShowAttempts = 0
        local function TryShowOverlay()
            GPFM.pendingShowTimer = nil
            GPFM.pendingShowAttempts = GPFM.pendingShowAttempts + 1
            local fmShown = FlightMapFrame and FlightMapFrame:IsShown()
            GPFM.Debug("Attempt", GPFM.pendingShowAttempts, "- FlightMapFrame shown:", fmShown)
            if fmShown then
                GPFM.ShowOverlay()
            elseif GPFM.pendingShowAttempts < 3 then
                -- Retry up to 3 times (0.5s, 1.0s, 1.5s)
                GPFM.pendingShowTimer = C_Timer.After(0.5, TryShowOverlay)
            end
        end
        GPFM.pendingShowTimer = C_Timer.After(0.5, TryShowOverlay)
    elseif event == "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" then
        local interactionType = ...
        local taxiEnum = Enum and Enum.PlayerInteractionType and Enum.PlayerInteractionType.TaxiNpc
        if interactionType == taxiEnum then
            GPFM.Debug("Taxi NPC interaction ended")
            GPFM.HideOverlay()
        else
            -- Also hide if FlightMapFrame was shown (handles enum mismatch)
            if GPFM.MainFrame and GPFM.MainFrame:IsShown() then
                -- Delay check - only hide if FlightMapFrame actually closes
                C_Timer.After(0.3, function()
                    if not FlightMapFrame or not FlightMapFrame:IsShown() then
                        GPFM.HideOverlay()
                    end
                end)
            end
        end
    end
end)

EventFrame:RegisterEvent("ADDON_LOADED")
EventFrame:RegisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_SHOW")
EventFrame:RegisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_HIDE")

-- ============================================================================
-- Slash Command (for testing & debug)
-- ============================================================================
SLASH_GPFM1 = "/gpfm"
SLASH_GPFM2 = "/gamepadflightmap"
SlashCmdList["GPFM"] = function(msg)
    msg = (msg or ""):lower()
    msg = strtrim(msg)
    if msg == "debug" then
        GamePadFlightMapDB.debugMode = not GamePadFlightMapDB.debugMode
        GPFM.debugMode = GamePadFlightMapDB.debugMode
        print("|cFF00FF00[GPFM]|r Debug mode:", GPFM.debugMode)
    elseif msg == "show" then
        GPFM.ShowOverlay()
    elseif msg == "hide" then
        GPFM.HideOverlay()
    elseif msg == "toggle" then
        if GPFM.MainFrame and GPFM.MainFrame:IsShown() then
            GPFM.HideOverlay()
        else
            GPFM.ShowOverlay()
        end
    elseif msg == "stats" then
        if GamePadFlightMapDB and GamePadFlightMapDB.flightStats then
            print("|cFF00FF00[GPFM]|r Flight Stats:")
            for name, count in pairs(GamePadFlightMapDB.flightStats) do
                if type(count) == "number" then
                    print("  " .. name .. ": " .. count)
                end
            end
        else
            print("|cFF00FF00[GPFM]|r No flight stats recorded yet")
        end
    elseif msg == "resetstats" then
        if GamePadFlightMapDB then
            GamePadFlightMapDB.flightStats = {}
            print("|cFF00FF00[GPFM]|r Flight stats reset")
        end
    --[[ Favorites commands (disabled)
    elseif msg == "fav" then
        local node = GPFM.GetSelectedNode()
        if node then GPFM.ToggleFavorite(node) end
    ]]
    else
        print("|cFF00FF00[GPFM]|r Commands:")
        print("  /gpfm debug      - Toggle debug mode")
        print("  /gpfm show       - Force show overlay")
        print("  /gpfm hide       - Force hide overlay")
        print("  /gpfm toggle     - Toggle overlay")
        print("  /gpfm stats      - Show flight statistics")
        print("  /gpfm resetstats - Reset flight statistics")
    end
end

-- ============================================================================
-- OnLoad
-- ============================================================================
function GPFM:OnLoad()
    GPFM.Debug("GamePadFlightMap loaded")

    if not GamePadFlightMapDB then
        GamePadFlightMapDB = {
            enabled = true,
            debugMode = false,
            flightStats = {},
        }
    end

    -- Ensure flightStats exists for existing DB
    if not GamePadFlightMapDB.flightStats then
        GamePadFlightMapDB.flightStats = {}
    end

    --[[ Favorites (disabled)
    if not GamePadFlightMapDB.flightStats.favorites then
        GamePadFlightMapDB.flightStats.favorites = {}
    end
    ]]

    GPFM.debugMode = GamePadFlightMapDB.debugMode

    GPFM.InitGamePad()

    -- Check if we're already at a taxi NPC (loaded mid-interaction)
    if FlightMapFrame and FlightMapFrame:IsShown() then
        GPFM.Debug("FlightMapFrame already shown at load, showing overlay")
        GPFM.ShowOverlay()
    end

    GPFM.Debug("Initialization complete, enabled=", GamePadFlightMapDB.enabled)
end
