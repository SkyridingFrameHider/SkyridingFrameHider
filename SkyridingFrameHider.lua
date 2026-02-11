-- SkyridingFrameHider
-- Hide any frame while skyriding, flying, or mounted
-- Configure via /sfh commands

local addonName = ...

---------------------------------------------------------------------------
-- Upvalue caching (local lookups are faster than global table lookups)
---------------------------------------------------------------------------
local IsMounted = IsMounted
local IsFlying = IsFlying
local issecretvalue = issecretvalue

-- Cached API references (resolved once during init, avoids repeated nil-checks)
local GetGlidingInfo  -- C_PlayerInfo.GetGlidingInfo
local GetPlayerAura   -- C_UnitAuras.GetPlayerAuraBySpellID

-- Constants
local SKYRIDING_SPELL_ID = 410137
local TICKER_INTERVAL = 0.25 -- seconds between checks while mounted
local VALID_MODES = {
	skyriding = true,
	flying = true,
	mounted = true,
}

-- Default settings
local defaults = {
	frameNames = {},
	mode = "skyriding", -- "skyriding" | "flying" | "mounted"
}

-- Runtime state
local db                       -- Cached reference to SkyridingFrameHiderDB
local trackedFrames = {}       -- Resolved frame references
local numTrackedFrames = 0     -- Cached count for fast early-exit checks
local frameStates = {}         -- Original alpha/mouse state before hiding
local updateTicker             -- Ticker for frequent updates while mounted
local lastShouldHide = false   -- Track state changes to avoid redundant work

-- Color helpers for chat output
local function PrintMsg(msg)
	print("|cFF33AAFF[SFH]|r " .. msg)
end

local function PrintError(msg)
	print("|cFFFF3333[SFH]|r " .. msg)
end

local function PrintSuccess(msg)
	print("|cFF33FF33[SFH]|r " .. msg)
end

-- Initialize saved variables with defaults
local function InitializeDB()
	if not SkyridingFrameHiderDB then
		-- One-time initialization: create defaults only when DB is missing.
		SkyridingFrameHiderDB = CopyTable(defaults)
	end

	-- Cache reference to avoid global lookup in hot path
	db = SkyridingFrameHiderDB

	-- Cache API availability once (these never change at runtime)
	if C_PlayerInfo and C_PlayerInfo.GetGlidingInfo then
		GetGlidingInfo = C_PlayerInfo.GetGlidingInfo
	end
	if C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
		GetPlayerAura = C_UnitAuras.GetPlayerAuraBySpellID
	end
end

---------------------------------------------------------------------------
-- Detection
---------------------------------------------------------------------------

local function ShouldHideFrames()
	if not IsMounted() then
		return false
	end

	local mode = db.mode

	-- Mode: mounted -- hide whenever mounted
	if mode == "mounted" then
		return true
	end

	if not IsFlying() then
		return false
	end

	-- Mode: flying -- hide on all flying (includes skyriding)
	if mode == "flying" then
		return true
	end

	-- Mode: skyriding (default) -- only hide while skyriding
	if GetGlidingInfo then
		local _, canGlide = GetGlidingInfo()
		if canGlide then
			return true
		end
	end

	return GetPlayerAura and GetPlayerAura(SKYRIDING_SPELL_ID) and true or false
end

---------------------------------------------------------------------------
-- Frame management
---------------------------------------------------------------------------

local function DiscoverFrames()
	local newFrames = {}
	local count = 0

	for i = 1, #db.frameNames do
		local targetFrame = _G[db.frameNames[i]]
		if targetFrame then
			count = count + 1
			newFrames[count] = targetFrame
		end
	end

	trackedFrames = newFrames
	numTrackedFrames = count
end

local function SaveFrameState(targetFrame)
	if frameStates[targetFrame] then
		return frameStates[targetFrame]
	end

	local currentAlpha = targetFrame:GetAlpha()
	-- Guard against secret values; skip this frame only (not all frames)
	if issecretvalue and issecretvalue(currentAlpha) then
		return nil
	end

	local state = {
		alpha = currentAlpha,
		mouseEnabled = targetFrame.IsMouseEnabled and targetFrame:IsMouseEnabled() or nil,
	}
	frameStates[targetFrame] = state
	return state
end

local function HideFrame(targetFrame)
	if not (targetFrame.SetAlpha and targetFrame.GetAlpha) then
		return
	end

	local state = SaveFrameState(targetFrame)
	if not state then
		return
	end

	targetFrame:SetAlpha(0)
	if state.mouseEnabled and targetFrame.EnableMouse then
		targetFrame:EnableMouse(false)
	end
end

local function RestoreFrame(targetFrame)
	local state = frameStates[targetFrame]
	if not state then
		return
	end

	if targetFrame.SetAlpha and state.alpha then
		targetFrame:SetAlpha(state.alpha)
	end
	if targetFrame.EnableMouse and state.mouseEnabled ~= nil then
		targetFrame:EnableMouse(state.mouseEnabled)
	end

	frameStates[targetFrame] = nil
end

local function HideTrackedFrames()
	for i = 1, numTrackedFrames do
		HideFrame(trackedFrames[i])
	end
end

local function RestoreTrackedFrames()
	for i = 1, numTrackedFrames do
		RestoreFrame(trackedFrames[i])
	end
end

local function CheckAndUpdateFrameVisibility()
	-- Early exit if nothing is tracked
	if numTrackedFrames == 0 then
		return
	end

	local shouldHide = ShouldHideFrames()

	if shouldHide ~= lastShouldHide then
		lastShouldHide = shouldHide

		if shouldHide then
			HideTrackedFrames()
		else
			RestoreTrackedFrames()
		end
	end
end

-- Start/stop ticker based on mount state for efficiency.
-- In "mounted" mode the hide state depends solely on IsMounted(), which is
-- fully captured by PLAYER_MOUNT_DISPLAY_CHANGED, so no ticker is needed.
-- In "flying"/"skyriding" modes the ticker polls IsFlying()/GetGlidingInfo()
-- because there is no event for takeoff/landing transitions.
local function UpdateTicker()
	local needsTicker = IsMounted() and db.mode ~= "mounted"

	if needsTicker and not updateTicker then
		updateTicker = C_Timer.NewTicker(TICKER_INTERVAL, CheckAndUpdateFrameVisibility)
	elseif not needsTicker and updateTicker then
		updateTicker:Cancel()
		updateTicker = nil
	end
end

local function RefreshVisibility()
	UpdateTicker()
	CheckAndUpdateFrameVisibility()
end

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------

local function FindTrackedFrameIndex(frameName)
	for i = 1, #db.frameNames do
		if db.frameNames[i] == frameName then
			return i
		end
	end
	return nil
end

local function PrintHelp()
	PrintMsg("SkyridingFrameHider commands:")
	print("  |cFFFFFF00/sfh add <framename>|r - Add a frame to hide")
	print("  |cFFFFFF00/sfh remove <framename>|r - Remove a frame")
	print("  |cFFFFFF00/sfh list|r - List tracked frames")
	print("  |cFFFFFF00/sfh mode [skyriding|flying|mounted]|r - Set hide mode")
	print("  Modes:")
	print("    |cFFFFFF00skyriding|r - Only hide while skyriding (default)")
	print("    |cFFFFFF00flying|r - Hide while flying (skyriding + regular)")
	print("    |cFFFFFF00mounted|r - Hide whenever mounted")
end

local function HandleAddCommand(param)
	if param == "" then
		PrintMsg("Usage: /sfh add <framename>")
		return
	end

	local targetFrame = _G[param]
	if not targetFrame then
		PrintError("Frame not found: " .. param)
		PrintMsg("Make sure the frame exists and the name is correct.")
		return
	end

	if FindTrackedFrameIndex(param) then
		PrintMsg("Frame already tracked: " .. param)
		return
	end

	db.frameNames[#db.frameNames + 1] = param
	DiscoverFrames()

	-- If currently hiding, also hide the newly added frame immediately
	if lastShouldHide then
		HideTrackedFrames()
	end

	PrintSuccess("Added frame: " .. param)
end

local function HandleRemoveCommand(param)
	if param == "" then
		PrintMsg("Usage: /sfh remove <framename>")
		return
	end

	local index = FindTrackedFrameIndex(param)
	if not index then
		PrintError("Frame not in tracked list: " .. param)
		return
	end

	-- Restore the frame if it is currently hidden
	local targetFrame = _G[param]
	if targetFrame then
		RestoreFrame(targetFrame)
	end

	table.remove(db.frameNames, index)
	DiscoverFrames()
	PrintSuccess("Removed frame: " .. param)
end

local function HandleListCommand()
	PrintMsg("Tracked frames:")
	if #db.frameNames == 0 then
		print("  (none)")
		return
	end

	for i = 1, #db.frameNames do
		local name = db.frameNames[i]
		local exists = _G[name] and "|cFF33FF33[found]|r" or "|cFFFF3333[not found]|r"
		print("  " .. i .. ". " .. name .. " " .. exists)
	end
end

local function HandleModeCommand(param)
	local mode = param:lower()
	if mode == "" then
		PrintMsg("Current mode: |cFFFFFF00" .. db.mode .. "|r")
		PrintMsg("Available modes: skyriding, flying, mounted")
		return
	end

	if not VALID_MODES[mode] then
		PrintError("Invalid mode: " .. param)
		PrintMsg("Available modes: skyriding, flying, mounted")
		return
	end

	-- Restore frames before changing mode
	RestoreTrackedFrames()
	lastShouldHide = false

	db.mode = mode
	PrintSuccess("Mode set to: " .. mode)

	-- Re-check with new mode and update ticker
	RefreshVisibility()
end

local commandHandlers = {
	add = HandleAddCommand,
	remove = HandleRemoveCommand,
	list = HandleListCommand,
	mode = HandleModeCommand,
}

local function HandleSlashCommand(msg)
	local cmd, param = strsplit(" ", msg, 2)
	cmd = cmd and cmd:lower() or ""
	param = param and strtrim(param) or ""

	local handler = commandHandlers[cmd]
	if handler then
		handler(param)
		return
	end

	PrintHelp()
end

SLASH_SKYRIDINGFRAMEHIDER1 = "/sfh"
SLASH_SKYRIDINGFRAMEHIDER2 = "/skyridingframehider"
SlashCmdList["SKYRIDINGFRAMEHIDER"] = HandleSlashCommand

---------------------------------------------------------------------------
-- Event handling & initialization
---------------------------------------------------------------------------

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_MOUNT_DISPLAY_CHANGED")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")

local function HandlePlayerLogin()
	DiscoverFrames()
	RefreshVisibility()
	PrintMsg("Loaded. Type |cFFFFFF00/sfh|r for commands.")
end

local function HandleStateUpdateEvent()
	if not db then
		return
	end

	RefreshVisibility()
end

eventFrame:SetScript("OnEvent", function(self, event, arg1)
	if event == "ADDON_LOADED" then
		if arg1 == addonName then
			InitializeDB()
		end
		return
	end

	if event == "PLAYER_LOGIN" then
		HandlePlayerLogin()
		return
	end

	if event == "PLAYER_MOUNT_DISPLAY_CHANGED" or event == "PLAYER_ENTERING_WORLD" then
		HandleStateUpdateEvent()
		return
	end
end)
