--[[
	Shards.lua - soul shard counter, bag scanning, and destroy-over-limit.

	The bag scan does double duty: it counts soul shards (#11) and detects
	which stones you're holding so the stone buttons can "use" them on
	left-click (feeds Buttons.lua via NL:SetStoneItem).
]]

local NL = _G.HoneyLock

NL:RegisterDefaults({
	shards = {
		showCounter = true,
		font = "Fonts\\FRIZQT__.TTF",  -- counter font face
		fontSize = 16,                 -- counter font size
		keep = 28,          -- destroy shards above this many
		organize = false,   -- move shards into the designated bag
		bagSlot = nil,      -- container index to keep shards in (nil = auto)
	},
})

local SOUL_SHARD_ID = 6265

-- Stone item IDs -> usage (left-click "use" detection)
local STONE_ITEMS = {}
do
	local map = {
		healthstone = { 5511,19004,19005,5512,19006,19007,5509,19008,19009,5510,19010,19011,9421,19012,19013,22103,22104,22105 },
		soulstone   = { 5232,16892,16893,16895,16896,22116,36895 },
		spellstone  = { 5522,13602,13603,41191,41192,41193,41194,41195,41196 },
		firestone   = { 1254,13699,13700,13701,41169,41170,41171,41172,41173,41174,40773 },
	}
	for usage, ids in pairs(map) do
		for _, id in ipairs(ids) do STONE_ITEMS[id] = usage end
	end
end

-- C_Container compatibility (present on Era 1.15, but be safe)
local Container = C_Container or {}
local GetNumSlots = Container.GetContainerNumSlots or _G.GetContainerNumSlots
local GetItemInfo = Container.GetContainerItemInfo or _G.GetContainerItemInfo
local PickupItem  = Container.PickupContainerItem or _G.PickupContainerItem

local function slotItemID(bag, slot)
	local info = GetItemInfo(bag, slot)
	if type(info) == "table" then return info.itemID, info.stackCount or 1 end
	-- old signature: texture, count, ..., itemID? Fall back to link parse.
	local _, count = info, select(2, GetItemInfo(bag, slot))
	local link = (Container.GetContainerItemLink or _G.GetContainerItemLink)(bag, slot)
	if link then
		local id = tonumber(link:match("item:(%d+)"))
		return id, count or 1
	end
	return nil, 0
end

------------------------------------------------------------------------
-- Scanning
------------------------------------------------------------------------

function NL:ScanBags()
	local shardCount = 0
	local foundStone = { healthstone = nil, soulstone = nil, spellstone = nil, firestone = nil }
	local shardSlots = {}

	for bag = 0, 4 do
		local slots = GetNumSlots and GetNumSlots(bag) or 0
		for slot = 1, slots do
			local id, count = slotItemID(bag, slot)
			if id == SOUL_SHARD_ID then
				shardCount = shardCount + (count or 1)
				table.insert(shardSlots, { bag = bag, slot = slot })
			elseif id and STONE_ITEMS[id] then
				foundStone[STONE_ITEMS[id]] = id
			end
		end
	end

	self.shardCount = shardCount
	self.shardSlots = shardSlots

	-- Update the stone buttons (nil clears a held stone that was consumed).
	self:SetStoneItem("soulstone", foundStone.soulstone)
	self:SetStoneItem("healthstone", foundStone.healthstone)

	self:UpdateShardDisplay()
	if self.UpdateStoneReminders then self:UpdateStoneReminders() end
	return shardCount
end

------------------------------------------------------------------------
-- Counter display (text on the sphere button; no custom textures)
------------------------------------------------------------------------

function NL:UpdateShardDisplay()
	local sphere = self.barButtons and self.barButtons.sphere
	if not sphere then return end
	local s = self.db.shards
	if not sphere.shardText then
		local fs = sphere:CreateFontString(nil, "OVERLAY")
		fs:SetShadowColor(0, 0, 0, 1)
		fs:SetShadowOffset(1, -1)
		sphere.shardText = fs
	end
	local fs = sphere.shardText
	-- Bottom-center, just below the logo (outside it).
	fs:ClearAllPoints()
	fs:SetPoint("TOP", sphere, "BOTTOM", 0, -1)
	fs:SetFont(s.font or "Fonts\\FRIZQT__.TTF", s.fontSize or 16, "OUTLINE")
	if s.showCounter and self.shardCount then
		fs:SetText(self.shardCount)
		fs:Show()
	else
		fs:Hide()
	end
end

------------------------------------------------------------------------
-- Destroy shards over the limit
------------------------------------------------------------------------

------------------------------------------------------------------------
-- Organize: consolidate loose shards into a soul bag
------------------------------------------------------------------------

local SOUL_BAG_FAMILY = 4   -- bag family bit for soul-shard bags
local GetFreeSlots = Container.GetContainerNumFreeSlots or _G.GetContainerNumFreeSlots

local organizing = false
function NL:OrganizeShards()
	if InCombatLockdown() or organizing then return end
	-- find soul bags (family includes the soul-shard bit) and their free slots
	local soulBags = {}
	for bag = 1, 4 do
		local family = 0
		if GetFreeSlots then
			local _, fam = GetFreeSlots(bag)
			family = fam or 0
		end
		if bit.band(family, SOUL_BAG_FAMILY) ~= 0 then
			table.insert(soulBags, bag)
		end
	end
	if #soulBags == 0 then return end

	local function firstFreeSoulSlot()
		for _, bag in ipairs(soulBags) do
			local slots = GetNumSlots and GetNumSlots(bag) or 0
			for slot = 1, slots do
				if not slotItemID(bag, slot) then return bag, slot end
			end
		end
	end

	organizing = true
	for bag = 0, 4 do
		local isSoulBag = false
		for _, b in ipairs(soulBags) do if b == bag then isSoulBag = true end end
		if not isSoulBag then
			local slots = GetNumSlots and GetNumSlots(bag) or 0
			for slot = 1, slots do
				local id = slotItemID(bag, slot)
				if id == SOUL_SHARD_ID then
					local tb, ts = firstFreeSoulSlot()
					if tb and PickupItem then
						PickupItem(bag, slot)
						PickupItem(tb, ts)
					end
				end
			end
		end
	end
	organizing = false
end

function NL:DestroyShards()
	if InCombatLockdown() then
		self:Print("Can't destroy shards in combat.")
		return
	end
	self:ScanBags()
	local keep = self.db.shards.keep or 28
	local over = (self.shardCount or 0) - keep
	if over <= 0 then
		self:Print(("No shards to destroy (have %d, keep %d)."):format(self.shardCount or 0, keep))
		return
	end
	-- Delete from the end of the list first.
	local destroyed = 0
	for i = #self.shardSlots, 1, -1 do
		if destroyed >= over then break end
		local s = self.shardSlots[i]
		if PickupItem then
			PickupItem(s.bag, s.slot)
			DeleteCursorItem()
			destroyed = destroyed + 1
		end
	end
	self:Print(("Destroyed %d soul shard(s)."):format(destroyed))
	C_Timer.After(0.2, function() NL:ScanBags() end)
end
