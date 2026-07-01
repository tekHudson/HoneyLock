# HoneyLock

A lightweight warlock helper for **World of Warcraft Classic — Season of Discovery**.

HoneyLock is a lean, from-scratch addon: 100% Lua (no XML), no custom themed
art (stock spell icons masked into an octagon), and a small dependency
footprint. It is inspired by Necrosis but is independent code.

## The bar

A **honeycomb "flower"**: a larger center logo ringed by satellites. Drag the
center to move the whole bar; **right-click the center** to open options.

Around the center:

- **Soulstone** & **Healthstone** — left-click **uses** a held stone,
  right-click **creates** one. A **red border** warns when a Healthstone is
  missing or no Soulstone is currently applied to you or a group member.
- **Buff menu** — self-buffs: Demon/Fel Armor, Unending Breath, Detect
  Invisibility, Soul Link, Shadow Ward.
- **Pet menu** — Imp, Voidwalker, Succubus, Felhunter, Felguard, Infernal,
  Doomguard, Fel Domination, Enslave, Sacrifice.
- **Utility menu** — Ritual of Summoning, Portal of Summoning, Eye of Kilrogg,
  Banish, and Create Spellstone / Firestone.
- **Mount** — Felsteed / Dreadsteed.

### Flyout menus

Every menu button works the same way:

- **Left-click** casts a **configurable default** ability.
- **Right-click** opens the flyout; click an ability to cast it (the menu then
  closes). For Mount, the default is the fastest mount you know.

Flyouts open outward along each button's own angle, and abilities you don't yet
know are greyed out. Set each menu's default in the options panel.

## Soul shards

- A **shard counter** sits below the logo. Enable **Show shard limit** to
  display it as `current/limit` and turn it **red** when you're over.
- **Click the counter** to destroy one over-limit shard. (Deletion is
  hardware-event protected on the current client, so it removes one per click —
  it cannot be automated.)
- Optional **auto-organize** consolidates loose shards into a soul bag.

## Other

- **Timers** for Soulstone, Banish, and Enslave.
- **Nightfall (Shadow Trance)** proc alert with optional sound.
- Native Blizzard **options panel**, including counter font/size.

## Commands

- `/hl` — open options
- `/hl destroy` — destroy one over-limit shard
- `/hl debug` — copy-paste diagnostics window (spell resolution)

## Install

Drop the `HoneyLock` folder into
`World of Warcraft/_classic_era_/Interface/AddOns/`.

## Notes

Built for the Classic Era 1.15.x client that Season of Discovery runs on. SoD
abilities are resolved by name when their spell IDs differ from vanilla/TBC, so
runes and reworked spells (e.g. Summon Felguard, Fel Armor, Portal of
Summoning) are picked up automatically once learned.
