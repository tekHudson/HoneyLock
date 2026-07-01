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
			buffmenu = true, petmenu = true, utility = true,
			mount = true,
		},
		mainSpell = "bolt",      -- left-click on sphere (Shadow Bolt)
		-- left-click default for each flyout menu (right-click opens the flyout)
		menuDefault = { buffmenu = "armor", petmenu = "imp", utility = "summoning" },
	},
})

-- Bolt isn't in Spells.lua's button data; add the base id for the sphere.
NL.SpellIDs.bolt = NL.SpellIDs.bolt or { 686 }

------------------------------------------------------------------------
-- Menu contents and per-usage cast target
------------------------------------------------------------------------

local MENU_CONTENTS = {
	-- true self-buffs only
	buffmenu  = { "armor", "fel_armor", "breath", "invisible", "link", "ward" },
	petmenu   = { "domination", "imp", "voidwalker", "succubus", "felhunter", "felguard", "inferno", "rit_of_doom", "enslave", "sacrifice" },
	-- non-buff utility: rituals, scout, CC, and stone creation
	utility   = { "summoning", "summon_portal", "eye", "banish", "spellstone", "firestone" },
	-- Fastest first so the default falls back to the fastest mount you know.
	mount     = { "dreadsteed", "felsteed" },
}
NL.MenuUsages = MENU_CONTENTS  -- exposed for the options panel

local MENU_KEYS = { "buffmenu", "petmenu", "utility", "mount" }

-- Self-cast usages get unit="player"; everything else uses normal targeting.
local SELF_CAST = {
	armor = true, fel_armor = true, link = true, ward = true, eye = true, invisible = true,
}

local STONES = { "soulstone", "healthstone" }

-- Display order for the straight "line" layout.
local BAR_ORDER = {
	"sphere", "soulstone", "healthstone",
	"buffmenu", "petmenu", "utility", "mount",
}

-- Honeycomb "flower": center + satellites at compass angles (degrees,
-- measured CCW from +x). Flyout menus open away from the center.
local CLUSTER = {
	sphere     = { center = true },
	buffmenu   = { angle = 135, dir = "up" },     -- top-left
	utility    = { angle =  90, dir = "up" },     -- top
	petmenu    = { angle =  45, dir = "up" },     -- top-right
	mount      = { angle =   0, dir = "right" },  -- right
	soulstone  = { angle = 225 },                 -- bottom-left
	healthstone= { angle = 180, dir = "left" },   -- left
}

-- Diagnostics: /hl debug  (output goes to a copy-friendly window)
function NL:Debug()
	local lines = {}
	local function add(s) lines[#lines + 1] = s end
	add("=== HoneyLock v" .. tostring(self.version) .. " debug ===")
	add("knownByName entries: " .. tostring(self.knownByName and #(function() local t={} for k in pairs(self.knownByName) do t[#t+1]=k end return t end)() or 0))

	local function dumpGroup(title, usages)
		add("")
		add(title .. " (usage / known / id / castName):")
		for _, usage in ipairs(usages) do
			add(("  %-12s %-5s %-9s %s"):format(
				usage, tostring(self:IsKnown(usage)),
				tostring(self:HighestKnownID(usage)), tostring(self:GetCastName(usage))))
		end
	end

	dumpGroup("Stones", STONES)
	dumpGroup("Buff menu", MENU_CONTENTS.buffmenu)
	dumpGroup("Pet menu", MENU_CONTENTS.petmenu)
	dumpGroup("Utility menu", MENU_CONTENTS.utility)
	dumpGroup("Mount menu", MENU_CONTENTS.mount)
	dumpGroup("Other", { "bolt" })

	add("")
	add("Stone button attributes (type1/spell1/type2/spell2/item1/held):")
	for _, usage in ipairs(STONES) do
		local b = self.stoneButtons and self.stoneButtons[usage]
		if b then
			add(("  %-12s t1=%s s1=%s t2=%s s2=%s i1=%s held=%s"):format(
				usage,
				tostring(b:GetAttribute("type1")), tostring(b:GetAttribute("spell1")),
				tostring(b:GetAttribute("type2")), tostring(b:GetAttribute("spell2")),
				tostring(b:GetAttribute("item1")), tostring(b.heldItemID)))
		else
			add("  " .. usage .. " (no button)")
		end
	end
	add("InCombatLockdown: " .. tostring(InCombatLockdown()))

	self:ShowCopyWindow(table.concat(lines, "\n"))
end

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

		-- Red alert border: a red octagon a few px larger, behind the icon.
		btn.alert = btn:CreateTexture(nil, "BACKGROUND", nil, -2)
		btn.alert:SetPoint("TOPLEFT", btn, "TOPLEFT", -3, 3)
		btn.alert:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 3, -3)
		btn.alert:SetColorTexture(0.9, 0.1, 0.1, 1)
		local alertMask = btn:CreateMaskTexture()
		alertMask:SetAllPoints(btn.alert)
		alertMask:SetTexture(ICON_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
		btn.alert:AddMaskTexture(alertMask)
		btn.alert:Hide()

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
	self:UpdateButtonAvailability(btn, usage)
end

-- Grey out (desaturate + dim) a button when its spell isn't currently known.
function NL:UpdateButtonAvailability(btn, usage)
	if not btn.icon then return end
	btn.icon:SetTexture(self:GetIcon(usage))
	local known = self:IsKnown(usage)
	btn.icon:SetDesaturated(not known)
	btn.icon:SetAlpha(known and 1 or 0.4)
	if btn.ring then btn.ring:SetAlpha(known and 0.9 or 0.4) end
end

------------------------------------------------------------------------
-- Stone buttons: left = use item if held, else create; right = create
------------------------------------------------------------------------

function NL:ConfigureStoneButton(btn, usage)
	if InCombatLockdown() then return end
	-- right click always creates
	btn:SetAttribute("type2", "spell")
	btn:SetAttribute("spell2", self:GetCastName(usage))
	-- left click: use the held stone if we have one, otherwise do nothing
	-- (creation is right-click only).
	local itemID = btn.heldItemID
	if itemID then
		btn:SetAttribute("type1", "item")
		btn:SetAttribute("item1", "item:" .. itemID)
	else
		btn:SetAttribute("type1", nil)
		btn:SetAttribute("item1", nil)
	end
	self:UpdateButtonAvailability(btn, usage)
	self:UpdateStoneReminders()
end

-- Called by Shards.lua after a bag scan: itemID or nil.
function NL:SetStoneItem(usage, itemID)
	local btn = self.stoneButtons and self.stoneButtons[usage]
	if not btn then return end
	btn.heldItemID = itemID
	self:ConfigureStoneButton(btn, usage)
end

-- Is one of our soul stones currently applied (Soulstone Resurrection buff)?
function NL:IsSoulstoneActive()
	local name = GetSpellInfo(20707)  -- "Soulstone Resurrection"
	if not name or not AuraUtil or not AuraUtil.FindAuraByName then return false end
	if AuraUtil.FindAuraByName(name, "player", "HELPFUL") then return true end
	if IsInRaid() then
		for i = 1, 40 do
			local u = "raid" .. i
			if UnitExists(u) and AuraUtil.FindAuraByName(name, u, "HELPFUL") then return true end
		end
	elseif IsInGroup() then
		for i = 1, 4 do
			local u = "party" .. i
			if UnitExists(u) and AuraUtil.FindAuraByName(name, u, "HELPFUL") then return true end
		end
	end
	return false
end

-- Red border reminders: Healthstone missing, or no active Soulstone.
function NL:UpdateStoneReminders()
	if not self.stoneButtons then return end
	local hs = self.stoneButtons.healthstone
	if hs and hs.alert then
		hs.alert:SetShown(self:IsKnown("healthstone") and not hs.heldItemID)
	end
	local ss = self.stoneButtons.soulstone
	if ss and ss.alert then
		ss.alert:SetShown(self:IsKnown("soulstone") and not self:IsSoulstoneActive())
	end
end

------------------------------------------------------------------------
-- Flyout menus (combat-safe via SecureHandlerClickTemplate)
------------------------------------------------------------------------

function NL:MakeMenu(name, parent, key, icon)
	-- Left-click casts the menu's default ability; right-click opens the flyout.
	local anchor = CreateFrame("Button", name, parent, "SecureActionButtonTemplate")
	anchor:RegisterForClicks("AnyUp")
	styleIcon(anchor, icon)

	-- container holding the secure child buttons
	local size = self.db.bar.size
	local flyout = CreateFrame("Frame", name .. "Flyout", anchor)
	flyout:SetSize(size, size)
	flyout:Hide()
	-- Flyout flows outward along the satellite's own cluster angle.
	anchor.angle = (CLUSTER[key] and CLUSTER[key].angle) or 90

	local entries = MENU_CONTENTS[key]
	for _, usage in ipairs(entries) do
		local child = self:MakeSpellButton(name .. "_" .. usage, flyout, usage)
		child:SetSize(size, size)
		child:Hide()
		child._usage = usage
		-- Collapse the flyout after the ability is clicked (out of combat).
		child:SetScript("PostClick", function()
			if not InCombatLockdown() then flyout:Hide() end
		end)
		if not flyout.children then flyout.children = {} end
		table.insert(flyout.children, child)
	end

	anchor.flyout = flyout
	anchor.menuKey = key

	-- Right-click toggles the flyout (out of combat); left-click casts default.
	anchor:SetScript("PostClick", function(self, button)
		if button == "RightButton" and not InCombatLockdown() then
			flyout:SetShown(not flyout:IsShown())
		end
	end)

	anchor:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		local def = self.defaultUsage or NL.db.bar.menuDefault[key]
		GameTooltip:SetText((key:gsub("menu", " menu")):gsub("^%l", string.upper))
		GameTooltip:AddLine("Left: cast " .. tostring(NL:GetCastName(def) or def) ..
			"  |  Right: open menu", 0.7, 0.7, 0.7)
		GameTooltip:Show()
	end)
	anchor:SetScript("OnLeave", GameTooltip_Hide)

	self:ConfigureMenuDefault(anchor)
	self:LayoutMenu(anchor)
	return anchor
end

-- Apply the menu's default-left-click ability: cast attrs + icon on the anchor.
function NL:ConfigureMenuDefault(anchor)
	if InCombatLockdown() or not anchor then return end
	local key = anchor.menuKey
	local usage = self.db.bar.menuDefault[key]
	-- Fall back to the first known ability if the chosen default isn't valid.
	if not usage or not self:IsKnown(usage) then
		for _, u in ipairs(MENU_CONTENTS[key]) do
			if self:IsKnown(u) then usage = u; break end
		end
	end
	usage = usage or MENU_CONTENTS[key][1]
	anchor.defaultUsage = usage
	anchor:SetAttribute("type1", "spell")
	anchor:SetAttribute("spell1", self:GetCastName(usage))
	if SELF_CAST[usage] then
		anchor:SetAttribute("unit", "player")
	else
		anchor:SetAttribute("unit", nil)
	end
	self:UpdateButtonAvailability(anchor, usage)
end

-- Lay out the known spells in a menu, flowing outward along the cluster angle.
function NL:LayoutMenu(anchor)
	if InCombatLockdown() then return end
	local size = self.db.bar.size
	local step = size + self.db.bar.spacing
	local rad = math.rad(anchor.angle or 90)
	local vx, vy = math.cos(rad), math.sin(rad)   -- outward direction
	local flyout = anchor.flyout

	flyout:ClearAllPoints()
	flyout:SetPoint("CENTER", anchor, "CENTER", 0, 0)
	flyout:SetSize(size, size)

	local n = 1   -- first child sits one step outward from the menu button
	for _, child in ipairs(flyout.children or {}) do
		if self:IsKnown(child._usage) then
			self:ConfigureSpellButton(child, child._usage)
			child:SetSize(size, size)
			child:ClearAllPoints()
			child:SetPoint("CENTER", anchor, "CENTER", vx * step * n, vy * step * n)
			child:Show()
			n = n + 1
		else
			child:Hide()
		end
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
	styleIcon(sphere, "Interface\\AddOns\\HoneyLock\\Textures\\icon")
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
		GameTooltip:AddLine("Drag to move  |  Right-click: options", 0.7, 0.7, 0.7)
		GameTooltip:Show()
	end)
	sphere:SetScript("OnLeave", GameTooltip_Hide)
	-- Right-click opens the options panel (insecure post-hook; out of combat).
	sphere:SetScript("PostClick", function(self, button)
		if button == "RightButton" and not InCombatLockdown() then
			NL:OpenOptions()
		end
	end)
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
	self.barButtons.utility   = self:MakeMenu("HoneyLockUtilityMenu", bar, "utility", "Interface\\Icons\\Spell_Shadow_Twilight")

	-- mount flyout: Felsteed / Dreadsteed, default = fastest known
	self.barButtons.mount = self:MakeMenu("HoneyLockMount", bar, "mount", "Interface\\Icons\\Spell_Nature_Swiftness")

	-- sphere is a logo/handle only (drag + right-click options), no cast
	self:ConfigureSphere()

	self:LayoutBar()
	self:RefreshBar()
end

function NL:ConfigureSphere()
	if InCombatLockdown() or not self.barButtons then return end
	local sphere = self.barButtons.sphere
	if not sphere then return end
	-- No spell on the center; clear any cast attributes.
	sphere:SetAttribute("type1", nil)
	sphere:SetAttribute("spell1", nil)
end

function NL:LayoutBar()
	if InCombatLockdown() or not self.bar then return end
	if self.db.bar.layout == "line" then
		self:LayoutLine()
	else
		self:LayoutHoneycomb()
	end
	-- relayout menus in case sizes/positions changed
	for _, key in ipairs(MENU_KEYS) do
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
	for _, key in ipairs(MENU_KEYS) do
		if self.barButtons[key] then
			self:ConfigureMenuDefault(self.barButtons[key])
			self:LayoutMenu(self.barButtons[key])
		end
	end
	self:ConfigureSphere()
	self:LayoutBar()
end

-- Called from options when a menu's default ability changes.
function NL:SetMenuDefault(key, usage)
	self.db.bar.menuDefault[key] = usage
	local anchor = self.barButtons and self.barButtons[key]
	if not anchor then return end
	if InCombatLockdown() then
		self.deferredRefresh = true
	else
		-- Apply on the next frame: changing secure attributes from inside the
		-- dropdown's click handler gets dropped, so escape that context first.
		C_Timer.After(0, function()
			if not InCombatLockdown() then NL:ConfigureMenuDefault(anchor) end
		end)
	end
end
