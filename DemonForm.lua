--[[
	DemonForm.lua - drop SoD demon form (Metamorphosis) at a flight master or
	before mounting up.

	Warlock demon form counts as a shapeshift, which blocks taxi use and
	mounting. The protected CancelShapeshiftForm() API can't be called from
	addon code, but running the `/cancelform` slash command via
	ChatEdit_SendText is unprotected and works out of combat -- which is when
	you'd talk to a flight master or summon a mount.

	Approach (same as the LetMeTaxi addon): when the taxi interaction is refused
	because we're shapeshifted, or the taxi map opens, send `/cancelform`. For
	mounting we do the same reactively (any "can't do that while shapeshifted"
	error while db.demonForm.dropOnMount is on).

	Note: we deliberately do NOT try to auto-recast a hotbar/macro mount after
	dropping form. Confirmed by testing: `/cancelform` sent via ChatEdit_SendText
	works from addon code, but `/cast <spell>` sent the same way silently does
	nothing -- Blizzard hardened spell-casting slash commands against this
	trick specifically (anti-bot), while leaving benign utility commands like
	/cancelform alone. So for a bag item / hotbar button / macro, the best we
	can do is drop form and let the player click again themselves. Our own HL
	mount button (Buttons.lua) sidesteps this entirely: it drops form in
	PreClick, then its *own* SecureActionButton attribute fires the cast
	natively via the real hardware click -- no chat trick involved -- so it
	stays one-click reliable.
]]

local HL = _G.HoneyLock

HL:RegisterDefaults({
	demonForm = {
		dropAtFlightMaster = true,
		dropOnMount = true,
	},
})

-- Diagnostic logging, off by default. /hl demonformdebug toggles it at
-- runtime; /hl debuglog reopens the popup if it gets closed.
HL:RegisterDefaults({ demonForm = { debug = false } })
local function dbg(...)
	if HL.db and HL.db.demonForm and HL.db.demonForm.debug then
		HL:LogDebug("[DemonForm]", ...)
	end
end

-- Run a slash command from insecure code (out of combat only).
local function runSlash(cmd)
	if InCombatLockdown() then
		dbg("runSlash skipped -- InCombatLockdown, cmd=", cmd)
		return
	end
	local eb = DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.editBox
	dbg(("runSlash cmd=%q DEFAULT_CHAT_FRAME=%s eb=%s ChatEdit_SendText=%s"):format(
		cmd, tostring(DEFAULT_CHAT_FRAME), tostring(eb), tostring(ChatEdit_SendText)))
	if eb and ChatEdit_SendText then
		eb:SetText(cmd)
		ChatEdit_SendText(eb, 0)
		dbg("runSlash sent, eb:GetText() after send =", tostring(eb:GetText()))
	end
end

local function cancelForm()
	runSlash("/cancelform")
end

-- Public: called from Buttons.lua right before our own mount button/flyout
-- casts, so the mount goes through on the first click instead of erroring.
function HL:DropDemonFormForMount()
	if not self.db.demonForm.dropOnMount then return end
	cancelForm()
end

-- Any client message telling us an action was blocked by our shapeshift.
-- Covers the taxi-specific string as well as the generic "can't mount /
-- can't do that while shapeshifted" errors raised by bag items, action bar
-- buttons, and macros -- none of which we can hook directly.
local function isShapeshiftError(msg)
	return type(msg) == "string" and msg:lower():find("shapeshift", 1, true) ~= nil
end

function HL:InitDemonForm()
	self:RegisterEvent("UI_ERROR_MESSAGE", function(_, arg1, arg2)
		local code = (type(arg1) == "number" and arg1) or nil   -- classic: (errType, msg)
		local msg  = (type(arg2) == "string" and arg2) or (type(arg1) == "string" and arg1) or nil

		local isTaxi = code == ERR_TAXIPLAYERSHAPESHIFTED
			or (msg and ERR_TAXIPLAYERSHAPESHIFTED and msg == ERR_TAXIPLAYERSHAPESHIFTED)

		dbg(("UI_ERROR_MESSAGE arg1=%s(%s) arg2=%s(%s) isTaxi=%s shapeshiftMatch=%s"):format(
			tostring(arg1), type(arg1), tostring(arg2), type(arg2),
			tostring(isTaxi), tostring(isShapeshiftError(msg))))

		if isTaxi then
			if self.db.demonForm.dropAtFlightMaster then cancelForm() end
		elseif isShapeshiftError(msg) then
			-- A bag-item/button/macro mount attempt refused for being
			-- shapeshifted: drop form and let the player click again.
			dbg("shapeshift error matched by text -> dropping form")
			self:DropDemonFormForMount()
		end
	end)

	-- If the taxi map does open (e.g. dropped just in time), make sure we're
	-- out of form so the flight actually works.
	self:RegisterEvent("TAXIMAP_OPENED", function()
		if self.db.demonForm.dropAtFlightMaster then cancelForm() end
	end)
end
