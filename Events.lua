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
	end)
end

------------------------------------------------------------------------
-- Init
------------------------------------------------------------------------

function NL:InitEvents()
	self:RegisterEvent("BAG_UPDATE", requestBagScan)
	self:RegisterEvent("BAG_UPDATE_DELAYED", requestBagScan)

	local function refresh()
		self:RefreshKnownSpells()
		if InCombatLockdown() then
			self.deferredRefresh = true
		else
			self:RefreshButtons()
		end
	end
	self:RegisterEvent("SPELLS_CHANGED", refresh)
	self:RegisterEvent("LEARNED_SPELL_IN_TAB", refresh)

	self:RegisterEvent("PLAYER_REGEN_ENABLED", function()
		if self.deferredRefresh then
			self.deferredRefresh = false
			self:RefreshButtons()
		end
	end)

	-- Nightfall via aura changes on the player
	self:RegisterEvent("UNIT_AURA", function(_, unit)
		if unit == "player" then self:CheckNightfall() end
	end)

	-- Cast-based timers
	self:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED", function(_, unit, _, spellID)
		if unit ~= "player" then return end
		local usage = CAST_TO_TIMER[spellID]
		if usage then
			self:StartTimer(usage, TIMER_LABEL[usage], nil)
		end
	end)
end
