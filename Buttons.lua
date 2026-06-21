--[[
	Buttons.lua - the floating warlock bar.

	Contents (your picks A1-A10):
	  sphere (drag handle + cast main spell), Soulstone, Healthstone,
	  Spellstone, Firestone, Buff menu, Pet menu, Curse menu, Mount,
	  Destroy-shards.

	All visuals are stock spell icons (no custom textures). Casting buttons
	are SecureActionButtons; flyout menus toggle via a SecureHandler snippet
	so they work in combat.
]]

local NL = _G.HoneyLock

NL:RegisterDefaults({
	bar = {
		shown = true,
		locked = false,
		scale = 1.0,
		size = 32,
		spacing = 6,             -- gap between honeycomb tiles
		sphereScale = 1.45,      -- center icon is larger than the satellites
		point = { "CENTER", "UIParent", "CENTER", 0, -160 },
		layout = "honeycomb",    -- "honeycomb" (flower cluster) or "line"
		show = {                 -- per-button visibility
			sphere = true, soulstone = true, healthstone = true,
			spellstone = false, firestone = false,
			buffmenu = true, petmenu = true,
			mount = true, destroy = true,
		},
		mainSpell = "bolt",      -- left-click on sphere (Shadow Bolt)
	},
})

-- Bolt isn't in Spells.lua's button data; add the base id for the sphere.
NL.SpellIDs.bolt = NL.SpellIDs.bolt or { 686 }

------------------------------------------------------------------------
-- Menu contents and per-usage cast target
------------------------------------------------------------------------

local MENU_CONTENTS = {
	buffmenu  = { "armor", "breath", "invisible", "eye", "summoning", "link", "ward", "banish" },
	petmenu   = { "domination", "imp", "voidwalker", "succubus", "felhunter", "felguard", "inferno", "rit_of_doom", "enslave", "sacrifice" },
}

-- Diagnostics: /hl debug  (output goes to a copy-friendly window)
function NL:Debug()
	local lines = {}
	local function add(s) lines[#lines + 1] = s end

	add("=== HoneyLock v" .. tostring(self.version) .. " debug ===")

	local function dumpGroup(title, usages)
		add("")
		add(title .. " (usage / known / id / castName):")
		for _, usage in ipairs(usages) do
			add(("  %-12s %-5s %-8s %s"):format(
				usage,
				tostring(self:IsKnown(usage)),
				tostring(self:HighestKnownID(usage)),
				tostring(self:GetCastName(usage))))
		end
	end

	dumpGroup("Stones", STONES)
	dumpGroup("Buff menu", MENU_CONTENTS.buffmenu)
	dumpGroup("Pet menu", MENU_CONTENTS.petmenu)
	dumpGroup("Other", { "mounts", "bolt" })

	self:ShowCopyWindow(table.concat(lines, "\n"))
end

-- Self-cast usages get unit="player"; everything else uses normal targeting.
local SELF_CAST = {
	armor = true, link = true, ward = true, eye = true, invisible = true,
}

local STONES = { "soulstone", "healthstone", "spellstone", "firestone" }

-- Display order for the straight "line" layout.
local BAR_ORDER = {
	"sphere", "soulstone", "healthstone", "spellstone", "firestone",
	"buffmenu", "petmenu", "mount", "destroy",
}

-- Honeycomb "flower": center + six satellites at compass angles (degrees,
-- measured CCW from +x). Flyout menus open away from the center.
local CLUSTER = {
	sphere     = { center = true },
	buffmenu   = { angle = 135, dir = "up" },     -- top-left
	petmenu    = { angle =  45, dir = "up" },     -- top-right
	mount      = { angle =   0, dir = "right" },  -- right
	destroy    = { angle = -45 },                 -- bottom-right
	soulstone  = { angle = 225 },                 -- bottom-left
	healthstone= { angle = 180, dir = "left" },   -- left
}

------------------------------------------------------------------------
-- Low-level: an icon-faced secure action button
------------------------------------------------------------------------

-- Cut-corner (octagon) alpha mask shipped in Textures/.
local ICON_MASK = "Interface\\AddOns\\HoneyLock\\Textures\\IconMask"

local function styleIcon(btn, texture)
	if not btn.icon then
		-- Thin dark rim: a black circle slightly larger than the icon.
		btn.ring = btn:CreateTexture(nil, "BACKGROUND")
		btn.ring:SetPoint("TOPLEFT", btn, "TOPLEFT", -1, 1)
		btn.ring:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 1, -1)
		btn.ring:SetColorTexture(0, 0, 0, 0.9)
		local ringMask = btn:CreateMaskTexture()
		ringMask:SetAllPoints(btn.ring)
		ringMask:SetTexture(ICON_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
		btn.ring:AddMaskTexture(ringMask)

		-- The icon itself, masked into a circle.
		btn.icon = btn:CreateTexture(nil, "ARTWORK")
		btn.icon:SetAllPoints(btn)
		btn.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
		local iconMask = btn:CreateMaskTexture()
		iconMask:SetAllPoints(btn.icon)
		iconMask:SetTexture(ICON_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
		btn.icon:AddMaskTexture(iconMask)

		-- Hover glow, shaped to the hexagon.
		btn:SetHighlightTexture("Interface\\Buttons\\WHITE8X8", "ADD")
		local hl = btn:GetHighlightTexture()
		if hl then
			hl:SetAllPoints(btn)
			hl:SetVertexColor(1, 1, 1, 0.25)
			local hlMask = btn:CreateMaskTexture()
			hlMask:SetAllPoints(hl)
			hlMask:SetTexture(ICON_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
			hl:AddMaskTexture(hlMask)
		end
	end
	btn.icon:SetTexture(texture or "Interface\\Icons\\INV_Misc_QuestionMark")
end

-- Create a 'spell' secure button for a usage.
function NL:MakeSpellButton(name, parent, usage)
	local btn = CreateFrame("Button", name, parent, "SecureActionButtonTemplate")
	btn:RegisterForClicks("AnyUp")
	btn.usage = usage
	styleIcon(btn, self:GetIcon(usage))
	btn:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		local id = NL:HighestKnownID(usage) or (NL.SpellIDs[usage] and NL.SpellIDs[usage][1])
		if id then GameTooltip:SetSpellByID(id) else GameTooltip:SetText(usage) end
		GameTooltip:Show()
	end)
	btn:SetScript("OnLeave", GameTooltip_Hide)
	self:ConfigureSpellButton(btn, usage)
	return btn
end

-- (Re)apply secure cast attributes; only safe out of combat.
function NL:ConfigureSpellButton(btn, usage)
	if InCombatLockdown() then return end
	local castName = self:GetCastName(usage)
	btn:SetAttribute("type", "spell")
	btn:SetAttribute("spell", castName)
	if SELF_CAST[usage] then
		btn:SetAttribute("unit", "player")
	else
		btn:SetAttribute("unit", nil)
	end
	if btn.icon then btn.icon:SetTexture(self:GetIcon(usage)) end
end

------------------------------------------------------------------------
-- Stone buttons: left = use item if held, else create; right = create
------------------------------------------------------------------------

function NL:ConfigureStoneButton(btn, usage)
	if InCombatLockdown() then return end
	local castName = self:GetCastName(usage)
	-- right click always creates
	btn:SetAttribute("type2", "spell")
	btn:SetAttribute("spell2", castName)
	-- left click: use item if we have one, else create
	local itemID = btn.heldItemID
	if itemID then
		btn:SetAttribute("type1", "item")
		btn:SetAttribute("item1", "item:" .. itemID)
	else
		btn:SetAttribute("type1", "spell")
		btn:SetAttribute("spell1", castName)
	end
	if btn.icon then
		btn.icon:SetTexture(self:GetIcon(usage))
	end
end

-- Called by Shards.lua after a bag scan: itemID or nil.
function NL:SetStoneItem(usage, itemID)
	local btn = self.stoneButtons and self.stoneButtons[usage]
	if not btn then return end
	btn.heldItemID = itemID
	self:ConfigureStoneButton(btn, usage)
end

------------------------------------------------------------------------
-- Flyout menus (combat-safe via SecureHandlerClickTemplate)
------------------------------------------------------------------------

function NL:MakeMenu(name, parent, key, icon)
	local anchor = CreateFrame("Button", name, parent, "SecureHandlerClickTemplate")
	anchor:RegisterForClicks("AnyUp")
	styleIcon(anchor, icon)

	-- container holding the secure child buttons
	local size = self.db.bar.size
	local flyout = CreateFrame("Frame", name .. "Flyout", anchor)
	flyout:SetSize(size, size)
	flyout:Hide()
	anchor.dir = (CLUSTER[key] and CLUSTER[key].dir) or "down"

	local entries = MENU_CONTENTS[key]
	local shown = 0
	for _, usage in ipairs(entries) do
		local child = self:MakeSpellButton(name .. "_" .. usage, flyout, usage)
		child:SetSize(size, size)
		child:Hide()
		child._usage = usage
		if not flyout.children then flyout.children = {} end
		table.insert(flyout.children, child)
	end

	anchor.flyout = flyout
	anchor.menuKey = key
	anchor:SetFrameRef("flyout", flyout)
	-- Toggle the flyout from the secure environment (works in combat).
	anchor:SetAttribute("_onclick", [[
		local f = self:GetFrameRef("flyout")
		if f:IsShown() then f:Hide() else f:Show() end
	]])

	anchor:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(key:gsub("menu", " menu"))
		GameTooltip:Show()
	end)
	anchor:SetScript("OnLeave", GameTooltip_Hide)

	self:LayoutMenu(anchor)
	return anchor
end

-- Lay out only the known spells in a menu, stacking away from the cluster.
function NL:LayoutMenu(anchor)
	if InCombatLockdown() then return end
	local size = self.db.bar.size
	local spacing = self.db.bar.spacing
	local step = size + spacing
	local dir = anchor.dir or "down"
	local flyout = anchor.flyout

	-- Anchor the flyout container relative to the menu button.
	flyout:ClearAllPoints()
	if dir == "up" then
		flyout:SetPoint("BOTTOM", anchor, "TOP", 0, spacing)
	elseif dir == "left" then
		flyout:SetPoint("RIGHT", anchor, "LEFT", -spacing, 0)
	elseif dir == "right" then
		flyout:SetPoint("LEFT", anchor, "RIGHT", spacing, 0)
	else
		flyout:SetPoint("TOP", anchor, "BOTTOM", 0, -spacing)
	end

	local n = 0
	for _, child in ipairs(flyout.children or {}) do
		if self:IsKnown(child._usage) then
			self:ConfigureSpellButton(child, child._usage)
			child:SetSize(size, size)
			child:ClearAllPoints()
			local off = n * step
			if dir == "up" then
				child:SetPoint("BOTTOM", flyout, "BOTTOM", 0, off)
			elseif dir == "left" then
				child:SetPoint("RIGHT", flyout, "RIGHT", -off, 0)
			elseif dir == "right" then
				child:SetPoint("LEFT", flyout, "LEFT", off, 0)
			else
				child:SetPoint("TOP", flyout, "TOP", 0, -off)
			end
			child:Show()
			n = n + 1
		else
			child:Hide()
		end
	end

	local extent = math.max(size, n * step - spacing)
	if dir == "left" or dir == "right" then
		flyout:SetSize(extent, size)
	else
		flyout:SetSize(size, extent)
	end
end

------------------------------------------------------------------------
-- Build the whole bar
------------------------------------------------------------------------

function NL:BuildBar()
	if self.bar then return end
	if InCombatLockdown() then return end

	local db = self.db.bar
	local bar = CreateFrame("Frame", "HoneyLockBar", UIParent)
	bar:SetMovable(true)
	bar:SetClampedToScreen(true)
	bar:SetScale(db.scale)
	bar:SetPoint(unpack(db.point))
	self.bar = bar

	self.stoneButtons = {}
	self.barButtons = {}

	-- sphere = drag handle + cast main spell
	local sphere = CreateFrame("Button", "HoneyLockSphere", bar, "SecureActionButtonTemplate")
	sphere:RegisterForDrag("LeftButton")
	sphere:RegisterForClicks("AnyUp")
	styleIcon(sphere, "Interface\\Icons\\Spell_Shadow_ShadowBolt")
	sphere:SetScript("OnDragStart", function(self)
		if not NL.db.bar.locked then bar:StartMoving() end
	end)
	sphere:SetScript("OnDragStop", function()
		bar:StopMovingOrSizing()
		local p, _, rp, x, y = bar:GetPoint()
		NL.db.bar.point = { p, "UIParent", rp, x, y }
	end)
	sphere:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine("HoneyLock")
		GameTooltip:AddLine("Drag to move. /hl for options.", 0.7, 0.7, 0.7)
		GameTooltip:Show()
	end)
	sphere:SetScript("OnLeave", GameTooltip_Hide)
	self.barButtons.sphere = sphere

	-- stones
	for _, usage in ipairs(STONES) do
		local btn = CreateFrame("Button", "HoneyLock_" .. usage, bar, "SecureActionButtonTemplate")
		btn:RegisterForClicks("AnyUp")
		styleIcon(btn, self:GetIcon(usage))
		btn:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			local id = NL:HighestKnownID(usage) or NL.SpellIDs[usage][1]
			GameTooltip:SetSpellByID(id)
			GameTooltip:AddLine("Left: use  |  Right: create", 0.7, 0.7, 0.7)
			GameTooltip:Show()
		end)
		btn:SetScript("OnLeave", GameTooltip_Hide)
		self:ConfigureStoneButton(btn, usage)
		self.stoneButtons[usage] = btn
		self.barButtons[usage] = btn
	end

	-- menus
	self.barButtons.buffmenu  = self:MakeMenu("HoneyLockBuffMenu",  bar, "buffmenu",  "Interface\\Icons\\Spell_Shadow_RagingScream")
	self.barButtons.petmenu   = self:MakeMenu("HoneyLockPetMenu",   bar, "petmenu",   "Interface\\Icons\\Spell_Shadow_SummonFelHunter")

	-- mount
	local mount = self:MakeSpellButton("HoneyLockMount", bar, "mounts")
	self.barButtons.mount = mount

	-- destroy shards (non-secure action)
	local destroy = CreateFrame("Button", "HoneyLockDestroy", bar)
	styleIcon(destroy, "Interface\\Icons\\INV_Misc_Gem_Amethyst_02")
	destroy:SetScript("OnClick", function() NL:DestroyShards() end)
	destroy:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText("Destroy soul shards over limit (" .. tostring(NL.db.shards.keep) .. ")")
		GameTooltip:Show()
	end)
	destroy:SetScript("OnLeave", GameTooltip_Hide)
	self.barButtons.destroy = destroy

	-- sphere casts main spell on left click
	self:ConfigureSphere()

	self:LayoutBar()
	self:RefreshBar()
end

function NL:ConfigureSphere()
	if InCombatLockdown() or not self.barButtons then return end
	local sphere = self.barButtons.sphere
	if not sphere then return end
	sphere:SetAttribute("type1", "spell")
	sphere:SetAttribute("spell1", self:GetCastName(self.db.bar.mainSpell))
end

function NL:LayoutBar()
	if InCombatLockdown() or not self.bar then return end
	if self.db.bar.layout == "line" then
		self:LayoutLine()
	else
		self:LayoutHoneycomb()
	end
	-- relayout menus in case sizes/positions changed
	for _, key in ipairs({ "buffmenu", "petmenu" }) do
		if self.barButtons[key] then self:LayoutMenu(self.barButtons[key]) end
	end
end

-- Honeycomb "flower": larger center icon ringed by six satellites.
function NL:LayoutHoneycomb()
	local db = self.db.bar
	local size, spacing = db.size, db.spacing
	local sphereSize = math.floor(size * db.sphereScale + 0.5)
	-- center-to-center radius so satellites sit just outside the center icon
	local radius = sphereSize / 2 + size / 2 + spacing

	-- hide everything first; the cluster only places its known slots
	for _, btn in pairs(self.barButtons) do btn:Hide() end

	for key, pos in pairs(CLUSTER) do
		local btn = self.barButtons[key]
		if btn and db.show[key] then
			if pos.center then
				btn:SetSize(sphereSize, sphereSize)
				btn:ClearAllPoints()
				btn:SetPoint("CENTER", self.bar, "CENTER", 0, 0)
			else
				btn:SetSize(size, size)
				local rad = math.rad(pos.angle)
				local ox = math.cos(rad) * radius
				local oy = math.sin(rad) * radius
				btn:ClearAllPoints()
				btn:SetPoint("CENTER", self.bar, "CENTER", ox, oy)
			end
			btn:Show()
		end
	end

	local span = 2 * (radius + size / 2)
	self.bar:SetSize(span, span)
end

-- Classic straight row (optional alternative layout).
function NL:LayoutLine()
	local db = self.db.bar
	local size, spacing = db.size, db.spacing
	local x = 0
	for _, key in ipairs(BAR_ORDER) do
		local btn = self.barButtons[key]
		if btn then
			btn:SetSize(size, size)
			if db.show[key] then
				btn:ClearAllPoints()
				btn:SetPoint("LEFT", self.bar, "LEFT", x, 0)
				btn:Show()
				x = x + size + spacing
			else
				btn:Hide()
			end
		end
	end
	self.bar:SetSize(math.max(size, x - spacing), size)
end

-- Show/hide whole bar + refresh dynamic state.
function NL:RefreshBar()
	if not self.bar then return end
	self.bar:SetShown(self.db.bar.shown)
	self.bar:SetScale(self.db.bar.scale)
end

-- Reconfigure everything after learning spells / leaving combat.
function NL:RefreshButtons()
	if InCombatLockdown() then return end
	if not self.bar then return end
	for _, usage in ipairs(STONES) do
		if self.stoneButtons[usage] then self:ConfigureStoneButton(self.stoneButtons[usage], usage) end
	end
	for _, key in ipairs({ "buffmenu", "petmenu" }) do
		if self.barButtons[key] then self:LayoutMenu(self.barButtons[key]) end
	end
	if self.barButtons.mount then self:ConfigureSpellButton(self.barButtons.mount, "mounts") end
	self:ConfigureSphere()
	self:LayoutBar()
end
