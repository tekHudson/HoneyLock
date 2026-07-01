--[[
	Events.lua - wires game events to the feature modules.
]]

local NL = _G.HoneyLock

-- Reverse lookup: spellID -> usage, for cast-based timers.
local CAST_TO_TIMER = {}
do
	local function add(usage, ids)
		for _, id in ipairs(ids) do CAST_TO_TIMER[id] = usage end
	end
	add("banish",  NL.SpellIDs.banish)
	add("enslave", NL.SpellIDs.enslave)
	-- Soulstone *resurrection* (item use) spell ids -> soulstone buff timer
	add("soulstone", { 20707, 20762, 20763, 20764, 20765 })
end

local TIMER_LABEL = { banish = "Banish", enslave = "Enslave", soulstone = "Soulstone" }

------------------------------------------------------------------------
-- Bag scan throttle
------------------------------------------------------------------------

local bagDirty = false
local function requestBagScan()
	if bagDirty then return end
	bagDirty = true
	C_Timer.After(0.3, function()
		bagDirty = false
		NL:ScanBags()
		if NL.db.shards.organize and NL.OrganizeShards then
			NL:OrganizeShards()
		end
		-- Note: shards can't be auto-destroyed — DeleteCursorItem is protected
		-- and requires a hardware event (see NL:DestroyShards).
	end)
end

-- Throttle the Soulstone-buff reminder scan (UNIT_AURA fires in bursts).
local reminderDirty = false
function NL:RequestStoneReminderUpdate()
	if reminderDirty then return end
	reminderDirty = true
	C_Timer.After(0.5, function()
		reminderDirty = false
		if NL.UpdateStoneReminders then NL:UpdateStoneReminders() end
	end)
end

------------------------------------------------------------------------
-- Init
------------------------------------------------------------------------

function NL:InitEvents()
	self:RegisterEvent("BAG_UPDATE", requestBagScan)
	self:RegisterEvent("BAG_UPDATE_DELAYED", requestBagScan)

	-- Rescan the spellbook and refresh button availability. Throttled, since
	-- the source events (gear/rune/spell changes) can fire in bursts.
	local refreshPending = false
	local function refresh()
		if refreshPending then return end
		refreshPending = true
		C_Timer.After(0.3, function()
			refreshPending = false
			self:RefreshKnownSpells()
			if InCombatLockdown() then
				self.deferredRefresh = true
			else
				self:RefreshButtons()
			end
		end)
	end
	-- learning/unlearning spells and (SoD) rune changes
	self:RegisterEvent("SPELLS_CHANGED", refresh)
	self:RegisterEvent("LEARNED_SPELL_IN_TAB", refresh)
	self:RegisterEvent("PLAYER_ENTERING_WORLD", refresh)
	-- changing gear / engraving runes
	self:RegisterEvent("PLAYER_EQUIPMENT_CHANGED", refresh)
	-- talent/spec changes (best-effort; ignored if the event doesn't exist)
	pcall(function() self:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED", refresh) end)
	pcall(function() self:RegisterEvent("CHARACTER_POINTS_CHANGED", refresh) end)

	self:RegisterEvent("PLAYER_REGEN_ENABLED", function()
		if self.deferredRefresh then
			self.deferredRefresh = false
			self:RefreshKnownSpells()
			self:RefreshButtons()
		end
	end)

	-- Nightfall via aura changes on the player
	self:RegisterEvent("UNIT_AURA", function(_, unit)
		if unit == "player" then self:CheckNightfall() end
		self:RequestStoneReminderUpdate()
	end)
	self:RegisterEvent("GROUP_ROSTER_UPDATE", function() self:RequestStoneReminderUpdate() end)

	-- Cast-based timers
	self:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED", function(_, unit, _, spellID)
		if unit ~= "player" then return end
		local usage = CAST_TO_TIMER[spellID]
		if usage then
			self:StartTimer(usage, TIMER_LABEL[usage], nil)
		end
	end)
end
