--[[
	SummonMsg.lua - announce a Ritual of Summoning / Portal of Summoning cast
	to the party (or raid, if in one).

	Fires off HL:AnnounceSummon() from the same UNIT_SPELLCAST_SUCCEEDED
	handler Events.lua already uses for cast-based timers. The message text
	is user-editable; "<spell name>" in it is replaced with the spell's
	actual name.
]]

local HL = _G.HoneyLock

HL:RegisterDefaults({
	summonMsg = {
		enabled = true,
		text = "I am casting <spell name>, please click.",
	},
})

-- spellID -> true, for the casts we announce (Ritual of Summoning, and the
-- SoD Portal of Summoning rune).
HL.SummonSpellIDs = {}
do
	local function add(ids)
		if not ids then return end
		for _, id in ipairs(ids) do HL.SummonSpellIDs[id] = true end
	end
	add(HL.SpellIDs.summoning)
	add(HL.SpellIDs.summon_portal)
end

-- % is special in gsub replacement strings; escape any that show up in a
-- spell name so it's inserted literally.
local function escapeReplacement(s)
	return (s:gsub("%%", "%%%%"))
end

-- Called from Events.lua when a tracked summon spell cast succeeds.
function HL:AnnounceSummon(spellID)
	if not self.db.summonMsg.enabled then return end
	if not IsInGroup() then return end

	local text = self.db.summonMsg.text
	if not text or text == "" then return end

	local name = GetSpellInfo(spellID) or "the summoning spell"
	text = text:gsub("<spell name>", escapeReplacement(name))

	local channel = IsInRaid() and "RAID" or "PARTY"
	SendChatMessage(text, channel)
end
