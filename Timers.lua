--[[
	Timers.lua - lightweight status-bar timers for Soulstone, Banish, Enslave.

	Started from the player's own successful casts (UNIT_SPELLCAST_SUCCEEDED).
	Bars stack under an anchor and count down; they self-remove on expiry.
	No custom textures (uses a Blizzard status-bar texture).
]]

local NL = _G.HoneyLock

NL:RegisterDefaults({
	timers = {
		enabled = true,
		point = { "CENTER", "UIParent", "CENTER", 250, 120 },
		width = 150,
		height = 16,
		spacing = 2,
		track = { soulstone = true, banish = true, enslave = true },
	},
})

-- Best-effort durations (seconds). Verify Soulstone in SoD; vanilla buff ~15m.
local DURATIONS = { soulstone = 900, banish = 30, enslave = 300 }

local BAR_TEX = "Interface\\TargetingFrame\\UI-StatusBar"
local COLORS = {
	soulstone = { 0.5, 0.4, 0.9 },
	banish    = { 0.6, 0.3, 0.8 },
	enslave   = { 0.8, 0.4, 0.2 },
}

local active = {}   -- list of { usage, label, expires, duration, frame }

------------------------------------------------------------------------
-- Bar pool
------------------------------------------------------------------------

local function ensureAnchor()
	if NL.timerAnchor then return NL.timerAnchor end
	local f = CreateFrame("Frame", "HoneyLockTimers", UIParent)
	f:SetSize(NL.db.timers.width, NL.db.timers.height)
	f:SetPoint(unpack(NL.db.timers.point))
	f:SetMovable(true)
	f:EnableMouse(false)
	NL.timerAnchor = f
	return f
end

local pool = {}
local function acquireBar()
	local bar = table.remove(pool)
	if bar then bar:Show(); return bar end
	local anchor = ensureAnchor()
	bar = CreateFrame("StatusBar", nil, anchor)
	bar:SetStatusBarTexture(BAR_TEX)
	bar:SetSize(NL.db.timers.width, NL.db.timers.height)
	bar.bg = bar:CreateTexture(nil, "BACKGROUND")
	bar.bg:SetAllPoints()
	bar.bg:SetColorTexture(0, 0, 0, 0.5)
	bar.label = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	bar.label:SetPoint("LEFT", 4, 0)
	bar.time = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	bar.time:SetPoint("RIGHT", -4, 0)
	return bar
end

local function releaseBar(bar)
	bar:Hide()
	bar:ClearAllPoints()
	table.insert(pool, bar)
end

local function relayout()
	local y = 0
	local h, sp = NL.db.timers.height, NL.db.timers.spacing
	for _, t in ipairs(active) do
		t.frame:ClearAllPoints()
		t.frame:SetPoint("TOPLEFT", NL.timerAnchor, "TOPLEFT", 0, y)
		t.frame:SetSize(NL.db.timers.width, h)
		y = y - (h + sp)
	end
end

------------------------------------------------------------------------
-- Public: start / clear
------------------------------------------------------------------------

function NL:StartTimer(usage, label, duration)
	if not self.db.timers.enabled then return end
	if not self.db.timers.track[usage] then return end
	duration = duration or DURATIONS[usage] or 30

	-- replace an existing timer of the same usage
	for i = #active, 1, -1 do
		if active[i].usage == usage then
			releaseBar(active[i].frame)
			table.remove(active, i)
		end
	end

	local bar = acquireBar()
	local c = COLORS[usage] or { 0.4, 0.4, 0.8 }
	bar:SetStatusBarColor(c[1], c[2], c[3])
	bar:SetMinMaxValues(0, duration)
	bar:SetValue(duration)
	bar.label:SetText(label or usage)

	table.insert(active, {
		usage = usage, label = label or usage,
		expires = GetTime() + duration, duration = duration, frame = bar,
	})
	relayout()
	self:StartTimerTicker()
end

function NL:StartTimerTicker()
	if self.timerTicker then return end
	self.timerTicker = self:ScheduleRepeatingTimer(function()
		local now = GetTime()
		local changed = false
		for i = #active, 1, -1 do
			local t = active[i]
			local remain = t.expires - now
			if remain <= 0 then
				releaseBar(t.frame)
				table.remove(active, i)
				changed = true
			else
				t.frame:SetValue(remain)
				t.frame.time:SetText(remain >= 60
					and ("%d:%02d"):format(remain / 60, remain % 60)
					or ("%.0f"):format(remain))
			end
		end
		if changed then relayout() end
		if #active == 0 and NL.timerTicker then
			NL:CancelTimer(NL.timerTicker)
			NL.timerTicker = nil
		end
	end, 0.1)
end

-- Remove all active timer bars and stop the ticker (e.g. when disabled).
function NL:ClearTimers()
	for i = #active, 1, -1 do
		releaseBar(active[i].frame)
		active[i] = nil
	end
	relayout()
	if self.timerTicker then
		self:CancelTimer(self.timerTicker)
		self.timerTicker = nil
	end
end
