local addonName, GPFM = ...

-- ============================================================================
-- GamePad Input Handler
-- ============================================================================

local GPFrame = CreateFrame("Button", "GamePadFlightMapGPFrame", UIParent, "SecureHandlerBaseTemplate")
GPFM.GPFrame = GPFrame

GPFrame:RegisterForClicks("AnyDown")
GPFrame:SetPropagateKeyboardInput(true)

GPFM.gamepadActive = false

local repeatTimer = nil
local repeatRate = 0.1

-- ============================================================================
-- Utility: direction to action mapping
-- ============================================================================
local function GetDirectionAction(direction)
    if direction == "PADDUP" then
        GPFM.SelectPrev()
    elseif direction == "PADDDOWN" then
        GPFM.SelectNext()
    elseif direction == "PADDLEFT" then
        GPFM.SelectNode(GPFM.selectedIndex - 5)
    elseif direction == "PADDRIGHT" then
        GPFM.SelectNode(GPFM.selectedIndex + 5)
    end
end

-- ============================================================================
-- Activate / Deactivate
-- ============================================================================
function GPFM.ActivateGamePad()
    if GPFM.gamepadActive then return end
    GPFM.gamepadActive = true

    GPFrame:EnableGamePadButton(true)
    GPFrame:SetPropagateKeyboardInput(false)

    GPFrame:SetScript("OnGamePadButtonDown", function(_, button)
        GPFM.OnGamePadButtonDown(button)
    end)
    GPFrame:SetScript("OnGamePadButtonUp", function(_, button)
        GPFM.OnGamePadButtonUp(button)
    end)
    GPFrame:SetScript("OnGamePadStick", function(_, stick, x, y)
        GPFM.OnGamePadStick(stick, x, y)
    end)

    GPFM.Debug("GamePad input activated")
end

function GPFM.DeactivateGamePad()
    if not GPFM.gamepadActive then return end
    GPFM.gamepadActive = false

    GPFrame:EnableGamePadButton(false)
    GPFrame:SetPropagateKeyboardInput(true)

    GPFrame:SetScript("OnGamePadButtonDown", nil)
    GPFrame:SetScript("OnGamePadButtonUp", nil)
    GPFrame:SetScript("OnGamePadStick", nil)

    GPFM:CancelRepeat()

    GPFM.Debug("GamePad input deactivated")
end

-- ============================================================================
-- GamePad Button Handler
-- ============================================================================
function GPFM.OnGamePadButtonDown(button)
    if not GPFM.gamepadActive then return end
    if not GPFM.MainFrame or not GPFM.MainFrame:IsShown() then return end

    GPFM.Debug("GamePad button:", button)

    if button == "PADDUP" or button == "PADDDOWN" or button == "PADDLEFT" or button == "PADDRIGHT" then
        GetDirectionAction(button)
        GPFM.StartRepeat(button)
    elseif button == "PADA" or button == "PAD1" then
        local node = GPFM.GetSelectedNode()
        if node then
            GPFM.TakeFlight(node)
        end
    elseif button == "PADB" or button == "PAD2" then
        CloseTaxiMap()
    elseif button == "PADX" or button == "PAD3" then
        GPFM.ToggleUnreachable()
    elseif button == "PADY" or button == "PAD4" then
        if GPFM.MainFrame and GPFM.MainFrame.SearchBox then
            GPFM.MainFrame.SearchBox:SetFocus()
        end
    end
end

function GPFM.OnGamePadButtonUp(button)
    if button == "PADDUP" or button == "PADDDOWN" or button == "PADDLEFT" or button == "PADDRIGHT" then
        GPFM:CancelRepeat()
    end
end

-- ============================================================================
-- GamePad Stick Handler
-- ============================================================================
local lastStickMove = 0

function GPFM.OnGamePadStick(stick, x, y)
    if not GPFM.gamepadActive then return end
    if not GPFM.MainFrame or not GPFM.MainFrame:IsShown() then return end

    if stick == "LStick" then
        local now = GetTime()
        if now - lastStickMove < 0.15 then return end

        if y > 0.5 then
            GPFM.SelectPrev()
            lastStickMove = now
        elseif y < -0.5 then
            GPFM.SelectNext()
            lastStickMove = now
        end
    end
end

-- ============================================================================
-- Key Repeat
-- ============================================================================
function GPFM.StartRepeat(direction)
    GPFM:CancelRepeat()

    repeatTimer = C_Timer.NewTicker(repeatRate, function()
        GetDirectionAction(direction)
    end)
end

function GPFM:CancelRepeat()
    if repeatTimer then
        repeatTimer:Cancel()
        repeatTimer = nil
    end
end

-- ============================================================================
-- Init
-- ============================================================================
function GPFM.InitGamePad()
    GPFM.Debug("GamePad input initialized")
end
