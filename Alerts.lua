--[[
	Alerts.lua - Nightfall (Shadow Trance) proc alert.

	When the Shadow Trance buff appears on the player, flash its icon in the
	center of the screen (pulsing), swipe a countdown as the free-cast window
	runs out, and optionally play a sound. Hides when the buff is
	consumed/expires. A "config mode" (unlocked) state lets the player drag
	the icon to a new spot; no custom textures for the icon itself (uses the
	spell's own icon), but borrows Blizzard's "marching ants" proc-glow sprite
	sheet for the highlight.
]]

local HL = _G.HoneyLock

HL:RegisterDefaults({
	alerts = {
		nightfall = true,
		sound = true,
		soundId = 8960, -- Ready Check
		scale = 1.0,
		alpha = 1.0,
		icon = "nightfall", -- "nightfall" (Shadow Trance) or "shadowbolt"
		glow = true,        -- crawling-ants proc border
		countdown = true,   -- radial swipe showing the free-cast window
		locked = true,      -- false while in "config mode" (drag to move)
		point = { "CENTER", "UIParent", "CENTER", 0, 150 },
	},
})

-- Built-in Blizzard sounds the player can pick between for the Nightfall
-- proc alert. Raw IDs are used as a fallback since SOUNDKIT entries aren't
-- guaranteed to exist on every client.
HL.NIGHTFALL_SOUND_CHOICES = {
	{ text = "Ready Check",  value = SOUNDKIT and SOUNDKIT.READY_CHECK or 8960 },
	{ text = "Raid Warning", value = SOUNDKIT and SOUNDKIT.RAID_WARNING or 8959 },
	{ text = "Level Up",     value = 888 },
}

HL.NIGHTFALL_ICON_CHOICES = {
	{ text = "Nightfall (Shadow Trance)", value = "nightfall" },
	{ text = "Shadow Bolt",               value = "shadowbolt" },
}

-- Shadow Bolt rank 1 -- only used to source an icon texture, never cast.
local SHADOW_BOLT_ICON_SPELLID = 686

local function iconTexture()
	if HL.db.alerts.icon == "shadowbolt" then
		return (select(3, GetSpellInfo(SHADOW_BOLT_ICON_SPELLID))) or "Interface\\Icons\\Spell_Shadow_ShadowBolt"
	end
	return (select(3, GetSpellInfo(HL.SHADOW_TRANCE_SPELLID))) or "Interface\\Icons\\Spell_Shadow_Twilight"
end

-- Present + duration/expiration (for the countdown swipe), or nil if absent.
local function findShadowTrance()
	local name = HL.SHADOW_TRANCE_NAME
	if not name then return false end
	if AuraUtil and AuraUtil.FindAuraByName then
		local n, _, _, _, duration, expirationTime = AuraUtil.FindAuraByName(name, "player")
		if n then return true, duration, expirationTime end
		return false
	end
	-- Fallback: classic buff scan
	for i = 1, 40 do
		local n, _, _, _, duration, expirationTime = UnitBuff("player", i)
		if not n then break end
		if n == name then return true, duration, expirationTime end
	end
	return false
end

------------------------------------------------------------------------
-- Marching-ants proc glow (same sprite sheet/technique as ShieldHotSwapper):
-- Interface\SpellActivationOverlay\IconAlertAnts, 256x256, 22 frames of
-- 48x48px (5 columns), stepped by hand via SetTexCoord since the Blizzard
-- glue templates that normally drive it aren't reliably present.
------------------------------------------------------------------------

local ANTS_COLS = 5
local ANTS_FRAME_UV = 48 / 256
local ANTS_FRAME_COUNT = 22
local ANTS_FPS = 24

local function glowPulse(f, elapsed)
	f.antsT = (f.antsT or 0) + elapsed
	local frame = math.floor(f.antsT * ANTS_FPS) % ANTS_FRAME_COUNT
	local col = frame % ANTS_COLS
	local row = math.floor(frame / ANTS_COLS)
	local left = col * ANTS_FRAME_UV
	local top = row * ANTS_FRAME_UV
	f.ants:SetTexCoord(left, left + ANTS_FRAME_UV, top, top + ANTS_FRAME_UV)
end

local function setGlowShown(f, show)
	if show == f.glowShown then return end
	f.glowShown = show
	if show then
		f.antsT = 0
		f.ants:Show()
		f:SetScript("OnUpdate", glowPulse)
	else
		f:SetScript("OnUpdate", nil)
		f.ants:Hide()
	end
end

------------------------------------------------------------------------
-- Frame
------------------------------------------------------------------------

local function ensureFrame()
	if HL.nightfallFrame then return HL.nightfallFrame end
	local f = CreateFrame("Frame", "HoneyLockNightfall", UIParent)
	f:SetSize(64, 64)
	f:SetPoint(unpack(HL.db.alerts.point))
	f:SetClampedToScreen(true)
	f:SetMovable(true)
	f:Hide()

	-- move-mode highlight border (only shown while unlocked)
	local border = f:CreateTexture(nil, "BACKGROUND")
	border:SetPoint("TOPLEFT", -4, 4)
	border:SetPoint("BOTTOMRIGHT", 4, -4)
	border:SetColorTexture(1, 0.82, 0, 0.6)
	border:Hide()
	f.border = border

	local icon = f:CreateTexture(nil, "ARTWORK")
	icon:SetAllPoints()
	icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	f.icon = icon

	-- countdown: radial swipe (no numbers, no bar) showing the free-cast
	-- window running out. Falls back to nil (skipped) if the template is
	-- ever missing on a client.
	local ok, cooldown = pcall(CreateFrame, "Cooldown", nil, f, "CooldownFrameTemplate")
	if ok and cooldown then
		cooldown:SetAllPoints()
		cooldown:SetDrawEdge(false)
		cooldown:SetReverse(false)
		if cooldown.SetHideCountdownNumbers then cooldown:SetHideCountdownNumbers(true) end
		f.cooldown = cooldown
	end

	-- crawling-ants proc glow, centered slightly larger than the icon
	local ants = f:CreateTexture(nil, "OVERLAY", nil, 3)
	ants:SetSize(64 * 1.4, 64 * 1.4)
	ants:SetPoint("CENTER", f, "CENTER")
	ants:SetTexture("Interface\\SpellActivationOverlay\\IconAlertAnts")
	ants:SetVertexColor(0.6, 0.4, 1) -- shadow-purple tint
	ants:Hide()
	f.ants = ants

	local hint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	hint:SetPoint("TOP", f, "BOTTOM", 0, -2)
	hint:SetText("Unlocked - drag to move")
	hint:Hide()
	f.hint = hint

	-- pulse animation
	local ag = f:CreateAnimationGroup()
	ag:SetLooping("BOUNCE")
	local pulse = ag:CreateAnimation("Scale")
	pulse:SetDuration(0.5)
	if pulse.SetScaleTo then
		pulse:SetScaleTo(1.2, 1.2)
	else
		pulse:SetFromScale(1, 1); pulse:SetToScale(1.2, 1.2)
	end
	pulse:SetOrigin("CENTER", 0, 0)
	f.pulse = ag

	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", function(self)
		if not HL.db.alerts.locked then self:StartMoving() end
	end)
	f:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local p, _, rp, x, y = self:GetPoint()
		HL.db.alerts.point = { p, "UIParent", rp, x, y }
	end)

	HL.nightfallFrame = f
	return f
end

-- Applies icon/scale/alpha from saved settings. Safe to call any time.
local function applyAppearance(f)
	f.icon:SetTexture(iconTexture())
	f:SetScale(HL.db.alerts.scale or 1.0)
	f:SetAlpha(HL.db.alerts.alpha or 1.0)
end

-- Re-applies live settings to an already-built frame (called from Options
-- when the player changes icon/alpha/size/glow while previewing or procced).
function HL:RefreshNightfallAppearance()
	local f = self.nightfallFrame
	if not f then return end
	applyAppearance(f)
	if f:IsShown() then
		setGlowShown(f, self.db.alerts.glow)
	end
end

function HL:ShowNightfall(duration, expirationTime)
	if not self.db.alerts.nightfall then return end
	local f = ensureFrame()
	applyAppearance(f)
	f:Show()
	if f.pulse then f.pulse:Play() end
	setGlowShown(f, self.db.alerts.glow)
	if f.cooldown then
		if self.db.alerts.countdown and duration and duration > 0 and expirationTime then
			f.cooldown:SetCooldown(expirationTime - duration, duration)
			f.cooldown:Show()
		else
			f.cooldown:Hide()
		end
	end
	if self.db.alerts.sound then
		PlaySound(self.db.alerts.soundId or 8960, "Master")
	end
end

function HL:HideNightfall()
	local f = self.nightfallFrame
	if not f then return end
	if f.pulse then f.pulse:Stop() end
	if f.cooldown then f.cooldown:Hide() end
	if not self.nightfallConfigMode then
		setGlowShown(f, false)
		f:Hide()
	end
end

-- Called from the aura event handler.
function HL:CheckNightfall()
	if self.nightfallConfigMode then return end -- don't fight the live preview
	local has, duration, expirationTime = findShadowTrance()
	if has and not self.nightfallActive then
		self.nightfallActive = true
		self:ShowNightfall(duration, expirationTime)
	elseif (not has) and self.nightfallActive then
		self.nightfallActive = false
		self:HideNightfall()
	end
end

------------------------------------------------------------------------
-- Config ("move") mode: unlock, show a live preview, allow dragging.
------------------------------------------------------------------------

function HL:ToggleNightfallConfigMode(on)
	self.db.alerts.locked = not on
	self.nightfallConfigMode = on
	local f = ensureFrame()
	f:EnableMouse(on)
	f.border:SetShown(on)
	f.hint:SetShown(on)
	if on then
		applyAppearance(f)
		f:Show()
		setGlowShown(f, self.db.alerts.glow)
		if f.cooldown and self.db.alerts.countdown then
			-- one-shot preview swipe so the player can see how it looks
			f.cooldown:SetCooldown(GetTime(), 3)
			f.cooldown:Show()
		elseif f.cooldown then
			f.cooldown:Hide()
		end
	else
		if f.cooldown then f.cooldown:Hide() end
		if not self.nightfallActive then
			setGlowShown(f, false)
			f:Hide()
		end
	end
end
