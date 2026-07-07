--[[
	HoneyLock - a lightweight warlock helper for Season of Discovery.
	Lua-only, minimal dependencies. No custom textures (uses spell icons).
]]

local ADDON_NAME = ...
local AceAddon = LibStub("AceAddon-3.0")

-- Create the addon object with embedded event/timer mixins.
local HL = AceAddon:NewAddon("HoneyLock", "AceEvent-3.0", "AceTimer-3.0")
_G.HoneyLock = HL

HL.version = GetAddOnMetadata and GetAddOnMetadata(ADDON_NAME, "Version") or "0.1.0"

------------------------------------------------------------------------
-- Saved variables: defaults + recursive merge (no AceDB dependency)
------------------------------------------------------------------------

-- Module defaults get merged in here via HL:RegisterDefaults() before login.
HL.defaults = {
	enabled = true,
	-- per-feature defaults are contributed by each module below
}

-- Deep-fill: copy any key from src that's missing in dst (recursing tables).
local function CopyDefaults(src, dst)
	if type(src) ~= "table" then return dst end
	if type(dst) ~= "table" then dst = {} end
	for k, v in pairs(src) do
		if type(v) == "table" then
			dst[k] = CopyDefaults(v, dst[k])
		elseif dst[k] == nil then
			dst[k] = v
		end
	end
	return dst
end

-- Modules call this at file scope to contribute their default settings.
function HL:RegisterDefaults(tbl)
	CopyDefaults(tbl, self.defaults)
end

------------------------------------------------------------------------
-- Lifecycle
------------------------------------------------------------------------

function HL:OnInitialize()
	HoneyLockDB = HoneyLockDB or {}
	self.db = CopyDefaults(self.defaults, HoneyLockDB)

	-- Slash command -> open the (native) options panel; falls back to a hint.
	SLASH_HONEYLOCK1 = "/hl"
	SLASH_HONEYLOCK2 = "/honeylock"
	SlashCmdList["HONEYLOCK"] = function(msg)
		msg = (msg or ""):lower():gsub("%s+", "")
		if msg == "debug" then
			HL:RefreshKnownSpells()
			HL:Debug()
		elseif msg == "destroy" then
			HL:ScanBags()
			HL:DestroyShards(false)
		elseif msg == "demonformdebug" then
			HL.db.demonForm.debug = not HL.db.demonForm.debug
			HL:Print("DemonForm debug logging:", tostring(HL.db.demonForm.debug))
		elseif msg == "debuglog" then
			HL:ShowDebugWindow()
		elseif HL.OpenOptions then
			HL:OpenOptions()
		else
			HL:Print("Options panel not loaded yet.")
		end
	end
end

function HL:OnEnable()
	-- Only run for warlocks.
	local _, class = UnitClass("player")
	if class ~= "WARLOCK" then
		self:Print("HoneyLock is for warlocks; disabling.")
		return
	end

	self:RefreshKnownSpells()
	self:BuildBar()
	self:InitOptions()
	self:InitDemonForm()
	self:InitEvents()
	self:ScanBags()
	self:CheckNightfall()

	self:Print(("v%s loaded. Type /hl for options."):format(tostring(self.version)))
end

------------------------------------------------------------------------
-- Small helpers shared by modules
------------------------------------------------------------------------

-- A simple window with a pre-selected, scrollable text box for easy copying.
function HL:ShowCopyWindow(text)
	local f = self.copyWindow
	if not f then
		f = CreateFrame("Frame", "HoneyLockCopyWindow", UIParent, BackdropTemplateMixin and "BackdropTemplate")
		f:SetSize(520, 420)
		f:SetPoint("CENTER")
		f:SetFrameStrata("DIALOG")
		f:SetMovable(true)
		f:EnableMouse(true)
		f:RegisterForDrag("LeftButton")
		f:SetScript("OnDragStart", f.StartMoving)
		f:SetScript("OnDragStop", f.StopMovingOrSizing)
		if f.SetBackdrop then
			f:SetBackdrop({
				bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
				edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
				tile = true, tileSize = 32, edgeSize = 32,
				insets = { left = 8, right = 8, top = 8, bottom = 8 },
			})
		end

		local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		title:SetPoint("TOP", 0, -14)
		title:SetText("HoneyLock — select all & copy (Ctrl+C)")

		local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
		close:SetPoint("TOPRIGHT", -4, -4)

		local scroll = CreateFrame("ScrollFrame", "HoneyLockCopyScroll", f, "UIPanelScrollFrameTemplate")
		scroll:SetPoint("TOPLEFT", 14, -36)
		scroll:SetPoint("BOTTOMRIGHT", -34, 14)

		local edit = CreateFrame("EditBox", nil, scroll)
		edit:SetMultiLine(true)
		edit:SetFontObject(ChatFontNormal)
		edit:SetWidth(460)
		edit:SetAutoFocus(false)
		edit:SetScript("OnEscapePressed", function() f:Hide() end)
		scroll:SetScrollChild(edit)
		f.edit = edit
	end
	f.edit:SetText(text or "")
	f:Show()
	f.edit:SetFocus()
	f.edit:HighlightText()
end

------------------------------------------------------------------------
-- Live debug log window: a persistent, appending, easy-to-copy popup.
-- Modules call HL:LogDebug(...) instead of HL:Print(...) for chatter that
-- shouldn't spam the chat frame; HL:ShowDebugWindow() opens/raises it.
------------------------------------------------------------------------

function HL:ShowDebugWindow()
	local f = self.debugWindow
	if not f then
		f = CreateFrame("Frame", "HoneyLockDebugWindow", UIParent, BackdropTemplateMixin and "BackdropTemplate")
		f:SetSize(560, 460)
		f:SetPoint("CENTER")
		f:SetFrameStrata("DIALOG")
		f:SetMovable(true)
		f:EnableMouse(true)
		f:RegisterForDrag("LeftButton")
		f:SetScript("OnDragStart", f.StartMoving)
		f:SetScript("OnDragStop", f.StopMovingOrSizing)
		if f.SetBackdrop then
			f:SetBackdrop({
				bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
				edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
				tile = true, tileSize = 32, edgeSize = 32,
				insets = { left = 8, right = 8, top = 8, bottom = 8 },
			})
		end

		local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		title:SetPoint("TOP", 0, -14)
		title:SetText("HoneyLock — debug log (Ctrl+A, Ctrl+C to copy)")

		local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
		close:SetPoint("TOPRIGHT", -4, -4)

		local clear = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
		clear:SetSize(70, 20)
		clear:SetPoint("TOPLEFT", 14, -12)
		clear:SetText("Clear")
		clear:SetScript("OnClick", function() HL:ClearDebugLog() end)

		local scroll = CreateFrame("ScrollFrame", "HoneyLockDebugScroll", f, "UIPanelScrollFrameTemplate")
		scroll:SetPoint("TOPLEFT", 14, -40)
		scroll:SetPoint("BOTTOMRIGHT", -34, 14)

		local edit = CreateFrame("EditBox", nil, scroll)
		edit:SetMultiLine(true)
		edit:SetFontObject(ChatFontNormal)
		edit:SetWidth(496)
		edit:SetAutoFocus(false)
		edit:SetScript("OnEscapePressed", function() f:Hide() end)
		scroll:SetScrollChild(edit)
		f.edit = edit
		f.scroll = scroll

		self.debugWindow = f
	end
	self:RefreshDebugWindow()
	f:Show()
	return f
end

function HL:ClearDebugLog()
	self.debugLines = {}
	self:RefreshDebugWindow()
end

function HL:RefreshDebugWindow()
	local f = self.debugWindow
	if not f or not self.debugLines then return end
	f.edit:SetText(table.concat(self.debugLines, "\n"))
	-- Scroll to the bottom once the edit box reflows to its new height.
	C_Timer.After(0, function()
		if f.scroll and f.scroll.SetVerticalScroll and f.scroll.GetVerticalScrollRange then
			f.scroll:SetVerticalScroll(f.scroll:GetVerticalScrollRange())
		end
	end)
end

-- Append a line to the debug log popup (not the chat frame). Opens the
-- window the first time it's used so new messages are visible immediately.
function HL:LogDebug(...)
	self.debugLines = self.debugLines or {}
	local msg = strjoin(" ", tostringall(...))
	table.insert(self.debugLines, msg)
	if #self.debugLines > 500 then table.remove(self.debugLines, 1) end
	if self.debugWindow and self.debugWindow:IsShown() then
		self:RefreshDebugWindow()
	else
		self:ShowDebugWindow()
	end
end

function HL:Print(...)
	local msg = "|cff8064c8HoneyLock:|r"
	for i = 1, select("#", ...) do
		msg = msg .. " " .. tostring(select(i, ...))
	end
	DEFAULT_CHAT_FRAME:AddMessage(msg)
end
