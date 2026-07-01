# Changelog

All notable changes to HoneyLock are documented here.
This project follows [Keep a Changelog](https://keepachangelog.com) and
[Semantic Versioning](https://semver.org).

## [Unreleased]

## [0.1.6] - 2026-07-01
### Changed
- Reworked shard destroying. The standalone Destroy-shards button is gone; the
  **shard counter is now clickable** and destroys one over-limit shard per
  click. Enable **Show shard limit** to display `current/limit` and turn the
  counter red when over. `/hl destroy` does the same from chat.
### Removed
- Automatic shard destruction is not possible on this client: `DeleteCursorItem`
  is protected and requires a hardware event, so deletion is one-per-click only.

## [0.1.5] - 2026-06-29
### Added
- Mount is now a flyout: Felsteed (60%) and Dreadsteed (100%); left-click
  casts the fastest you know, right-click opens the picker.
- New Utility flyout for non-buff abilities: Ritual of Summoning, Portal of
  Summoning, Eye of Kilrogg, Banish, plus Create Spellstone / Firestone.
- Portal of Summoning (Season of Discovery) is now supported.
- Red border reminders on the stone buttons: Healthstone when you're missing
  one, Soulstone when none is currently applied to you or a group member.
### Changed
- Buff menu now contains only true self-buffs (armor, breath, invisibility,
  soul link, shadow ward).
- Flyout menus open outward along each satellite's own angle (Buff up-left,
  Pet up-right, Utility up, Mount right).
- Stone buttons: left-click only *uses* a held stone; creation is right-click
  only (no accidental creates).
- Standalone Spellstone/Firestone bar buttons removed (their create actions
  live in the Utility menu).

## [0.1.4] - 2026-06-28
### Fixed
- Unchecking the Timers option now removes any timer bars already on screen
  (previously it only stopped new ones from appearing).

## [0.1.3] - 2026-06-26
### Fixed
- Changing a menu's default ability now takes effect immediately instead of
  only after a reload (the secure attribute apply is deferred out of the
  dropdown's handler).

## [0.1.2] - 2026-06-26
### Added
- Flyout menus now have a configurable left-click default: left-click the Buff
  or Pet button casts the chosen ability; right-click opens the flyout to pick.
  Set the default per menu in options; the button shows the default's icon.
- Soul shard counter is now configurable: font face and size (integer), with
  a toggle to hide it. It sits below the logo (bottom-center, outside it).
### Changed
- Maintain a curated CHANGELOG; CurseForge release notes now come from it.

## [0.1.1] - 2026-06-22
### Fixed
- Spell detection now works on the Season of Discovery client: the spellbook
  is scanned by flat index (the skill-line-count API is missing on 1.15.4),
  so known spells — including rune abilities — resolve correctly.
- Stone/spell casting now uses each spell's exact name including its tier
  (e.g. `Create Healthstone (Minor)`); stripping the tier had silently broken
  casts.
- `/hl debug` no longer errors and now reports resolved ids and secure button
  attributes.

### Added
- Buttons whose spell you don't currently know are greyed out (desaturated).
- Known-spell and button state refresh automatically on spell, rune, and gear
  changes.
- Menus collapse after you click an ability.
- The center is now an addon-icon logo (drag to move, right-click for options)
  instead of a spell button.

## [0.1.0] - 2026-06-21
### Added
- Initial release for WoW Classic — Season of Discovery.
- Honeycomb button bar: center logo ringed by Soulstone, Healthstone, Buff and
  Pet flyout menus, Mount, and Destroy-shards (Spellstone/Firestone optional).
- Soul shard counter, bag organize, and destroy-over-limit.
- Timers for Soulstone, Banish, and Enslave.
- Nightfall (Shadow Trance) proc alert.
- Native Blizzard options panel (`/hl`).
- 100% Lua, no XML, stock spell icons (octagon-masked); minimal libraries.

[Unreleased]: https://github.com/tekHudson/HoneyLock/compare/v0.1.6...HEAD
[0.1.6]: https://github.com/tekHudson/HoneyLock/compare/v0.1.5...v0.1.6
[0.1.5]: https://github.com/tekHudson/HoneyLock/compare/v0.1.4...v0.1.5
[0.1.4]: https://github.com/tekHudson/HoneyLock/compare/v0.1.3...v0.1.4
[0.1.3]: https://github.com/tekHudson/HoneyLock/compare/v0.1.2...v0.1.3
[0.1.2]: https://github.com/tekHudson/HoneyLock/compare/v0.1.1...v0.1.2
[0.1.1]: https://github.com/tekHudson/HoneyLock/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/tekHudson/HoneyLock/releases/tag/v0.1.0
