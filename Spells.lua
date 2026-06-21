--[[
	Spells.lua - warlock spell data for HoneyLock.

	Spell IDs are seeded from Classic/vanilla data. They remain valid on
	Season of Discovery (SoD runs on the Classic Era client). SoD-specific
	abilities (e.g. Felguard via rune) are learned as normal spells, so the
	"highest known rank" resolution below picks them up automatically.

	Each usage maps to a rank-ordered list of spell IDs (lowest rank first).
	We resolve the highest *known* rank at runtime; casting by base name then
	casts that rank (Classic casts the highest known rank when no rank given).
]]

local NL = _G.HoneyLock

-- usage -> { spellID, spellID, ... }  (ascending rank)
NL.SpellIDs = {
	-- Stone creation
	soulstone   = { 693, 20752, 20755, 20756, 20757, 27238, 47884 },
	healthstone = { 6201, 6202, 5699, 11729, 11730, 27230, 47871, 47878 },
	spellstone  = { 2362, 17727, 17728, 28172, 47886, 47888 },
	firestone   = { 6366, 17951, 17952, 17953, 27250, 60219, 60220 },

	-- Demons / summons
	domination  = { 18708 },                 -- Fel Domination (talent)
	imp         = { 688 },
	voidwalker  = { 697 },
	succubus    = { 712 },
	felhunter   = { 691 },
	felguard    = { 30146, 427748 },         -- 427748 = SoD rune; 30146 = TBC
	inferno     = { 1122 },                  -- Inferno (summons Infernal)
	rit_of_doom = { 18540 },                 -- Ritual of Doom (Doomguard)
	enslave     = { 1098, 11725, 11726, 61191 },
	sacrifice   = { 18788 },                 -- Demonic Sacrifice (talent)

	-- Mounts
	mounts      = { 5784, 23161 },           -- Felsteed, Dreadsteed

	-- Buffs / utility
	armor       = { 687, 696, 706, 1086, 11733, 11734, 11735, 27260, 47793, 47889 }, -- Demon Skin/Armor
	breath      = { 5697 },                  -- Unending Breath
	invisible   = { 132, 2970, 11743 },      -- Detect Invisibility
	eye         = { 126 },                   -- Eye of Kilrogg
	summoning   = { 698 },                   -- Ritual of Summoning
	link        = { 19028 },                 -- Soul Link (talent)
	ward        = { 6229, 11739, 11740, 28610, 47890, 47891 }, -- Shadow Ward
	banish      = { 710, 18647 },

	-- Curses
	weakness     = { 702, 1108, 6205, 7646, 11707, 11708, 27224, 30909, 50511 },
	agony        = { 980, 1014, 6217, 11711, 11712, 11713, 27218, 47863, 47864 },
	tongues      = { 1714, 11719 },
	exhaustion   = { 18223 },
	elements     = { 1490, 11721, 11722, 27228, 47865 },
	doom         = { 603, 30910, 47867 },
	recklessness = { 704, 7658, 7659, 11717, 27226 },
}

-- Reagent flags (for tooltips / shard awareness)
NL.UsesSoulShard = {
	voidwalker = true, succubus = true, felhunter = true, felguard = true,
	inferno = true, rit_of_doom = true, enslave = false,
	soulstone = true, healthstone = true, spellstone = true, firestone = true,
	summoning = true,
}

-- Nightfall proc buff
NL.SHADOW_TRANCE_SPELLID = 17941
NL.SHADOW_TRANCE_NAME = (GetSpellInfo(17941))

------------------------------------------------------------------------
-- Resolution helpers
------------------------------------------------------------------------

local function isKnown(spellID)
	-- IsSpellKnown handles spellbook spells; IsPlayerSpell catches some others.
	if IsSpellKnown and IsSpellKnown(spellID) then return true end
	if IsPlayerSpell and IsPlayerSpell(spellID) then return true end
	return false
end

-- Cache of spells actually in the player's spellbook, keyed by name -> spellID.
-- This lets SoD runes (which use different spell IDs than vanilla/TBC) resolve
-- by name, so we don't have to hardcode every rune's ID.
NL.knownByName = {}

function NL:RefreshKnownSpells()
	wipe(self.knownByName)

	local function record(name, id)
		if name and id then
			if not self.knownByName[name] or id > self.knownByName[name] then
				self.knownByName[name] = id
			end
		end
	end

	-- Modern API (WoW 11.x / Classic Era 1.15.4+, which SoD runs on).
	if C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines then
		local PLAYER = Enum.SpellBookSpellBank.Player
		for line = 1, C_SpellBook.GetNumSpellBookSkillLines() do
			local info = C_SpellBook.GetSpellBookSkillLineInfo(line)
			if info then
				local from = (info.itemIndexOffset or 0) + 1
				local to = (info.itemIndexOffset or 0) + (info.numSpellBookItems or 0)
				for i = from, to do
					local item = C_SpellBook.GetSpellBookItemInfo(i, PLAYER)
					if item and item.spellID then
						record(item.name or C_SpellBook.GetSpellBookItemName(i, PLAYER), item.spellID)
					end
				end
			end
		end
		return
	end

	-- Legacy fallback (older clients).
	local numTabs = GetNumSpellTabs and GetNumSpellTabs() or 0
	for tab = 1, numTabs do
		local _, _, offset, numSpells = GetSpellTabInfo(tab)
		if offset and numSpells then
			for i = offset + 1, offset + numSpells do
				local name = GetSpellBookItemName and GetSpellBookItemName(i, "spell")
				local _, id = GetSpellBookItemInfo and GetSpellBookItemInfo(i, "spell")
				record(name, id)
			end
		end
	end
end

-- Returns a spellID if a spell of this NAME is in the player's spellbook.
-- Passing a name (not an id) to GetSpellInfo only resolves for known spells,
-- which is the only reliable way to detect SoD rune-granted abilities.
local function knownByExactName(name)
	if not name then return nil end
	local _, _, _, _, _, _, id = GetSpellInfo(name)
	if id then return id end
	return nil
end
NL.knownByExactName = knownByExactName

-- Highest known spellID for a usage, or nil.
function NL:HighestKnownID(usage)
	local list = self.SpellIDs[usage]
	if not list then return nil end
	for i = #list, 1, -1 do
		if isKnown(list[i]) then return list[i] end
	end
	-- Name fallbacks: a same-named spell may be known under a different id (SoD).
	-- Try every candidate, since some ids don't exist on this client (e.g. a
	-- TBC id on the Era client returns nil from GetSpellInfo).
	for i = 1, #list do
		local name = GetSpellInfo(list[i])
		if name then
			local byName = knownByExactName(name)
			if byName then return byName end
			if self.knownByName[name] then return self.knownByName[name] end
		end
	end
	return nil
end

-- Is any rank of this usage known?
function NL:IsKnown(usage)
	return self:HighestKnownID(usage) ~= nil
end

-- Base (rank-stripped) cast name for a usage. Returns nil if unknown.
-- Falls back to the lowest-rank id's name so buttons can show a label even
-- before the spell is learned (the secure cast simply fails until learned).
function NL:GetCastName(usage)
	local id = self:HighestKnownID(usage)
	if not id then
		local list = self.SpellIDs[usage]
		id = list and list[1]
	end
	if not id then return nil end
	local name = GetSpellInfo(id)
	if not name then return nil end
	return name:match("^(.-)%(") or name   -- strip "(Rank X)" if present
end

-- Icon texture for a usage (uses highest known, else lowest).
function NL:GetIcon(usage)
	local id = self:HighestKnownID(usage)
	if not id then
		local list = self.SpellIDs[usage]
		id = list and list[1]
	end
	if not id then return nil end
	local _, _, icon = GetSpellInfo(id)
	return icon
end
