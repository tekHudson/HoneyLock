# HoneyLock

A lightweight warlock helper for **World of Warcraft Classic — Season of Discovery**.

HoneyLock is a lean, from-scratch addon: 100% Lua (no XML), no custom themed
art (stock spell icons masked into an octagon), and a small dependency
footprint. It is inspired by Necrosis but is independent code.

## Features

- **Honeycomb button bar** — a larger center "sphere" (casts your main spell,
  shows your soul shard count) ringed by:
  - Soulstone & Healthstone (left-click = use, right-click = create)
  - Buff and Pet flyout menus
  - Mount
  - Destroy-shards
- **Soul shard counter** + optional auto-organize / destroy-over-limit
- **Timers** for Soulstone, Banish, and Enslave
- **Nightfall (Shadow Trance) proc alert**
- **Native options panel** (Blizzard Settings UI)

Spellstone/Firestone buttons exist but are hidden by default — enable them in
the options panel.

## Usage

- `/hl` — open options
- `/hl debug` — open a copy-paste diagnostics window (spell resolution)

Drag the center sphere to move the bar.

## Install

Drop the `HoneyLock` folder into
`World of Warcraft/_classic_era_/Interface/AddOns/`.

## Notes

Built for the Classic Era 1.15.x client that Season of Discovery runs on. SoD
rune abilities are resolved by name where their spell IDs differ from
vanilla/TBC.
