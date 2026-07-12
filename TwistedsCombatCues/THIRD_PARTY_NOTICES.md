# Third-Party Notices

Twisteds Combat Cues ("the addon") is an add-on for **World of Warcraft**. Its own
source code and original artwork are released under the **GNU General Public License,
version 2** (see `LICENSE`).

This file lists third-party material that is bundled with, referenced by, or used to
build the addon, together with the attribution and licensing that could be identified.

> **Important — unverified material.** Some bundled fonts and sound files could **not**
> be verified as freely redistributable. Those items are called out below under
> "Unverified / redistribution not confirmed." The addon's own license (GPL v2, in
> `LICENSE`) does **not** apply to any third-party material listed here. Nothing in this
> addon claims ownership of Blizzard Entertainment assets or of any third-party file.

---

## 1. Blizzard Entertainment, Inc.

World of Warcraft, the game client and its APIs, and all in-game names, icons, spell
artwork, item artwork, textures, built-in fonts (e.g. `FRIZQT__`, `SKURRI`,
`MORPHEUS`), built-in sound kits, and the raid target ("target marker") icon textures
(`Interface\TargetingFrame\...`) are the property of **Blizzard Entertainment, Inc.**

The addon references these assets at runtime through the game client; it does **not**
bundle or redistribute them. No ownership is claimed. This project is not affiliated
with or endorsed by Blizzard Entertainment.

Spell and item **names and IDs** shown by the addon (including the bundled search
databases in the `TwistedsCombatCues_DB` companion) are Blizzard game data.

---

## 2. Tabler Icons

The interface icons under `assets/icons/*.tga` are converted from **Tabler Icons**
(<https://tabler.io/icons>), which are licensed under the **MIT License**.

```
Copyright (c) 2020-2024 Paweł Kuna

Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the "Software"), to deal in
the Software without restriction ... (standard MIT terms).
```

The `.tga` files bundled here are rasterized/recolored derivatives of the original
MIT-licensed SVGs.

---

## 3. wago.tools (database exports)

The bundled search databases (`TwistedsCombatCues_DB/SpellDB.lua`,
`TwistedsCombatCues_DB/ItemDB.lua`) are generated offline from **DB2 CSV exports
provided by wago.tools** (<https://wago.tools>). The underlying spell/item data is
**Blizzard game data** (see section 1); wago.tools is the export tooling used to obtain
it. The generation scripts are development-only and are **not** shipped in the release.

---

## 4. WeakAuras

**WeakAuras** is credited in-addon as *inspiration only*. This addon is not derived from
WeakAuras source code, and WeakAuras is **not** the licensor or owner of the bundled
sound files (see section 6). No WeakAuras code is included.

---

## 5. Bundled fonts (`assets/fonts/`)

These TrueType/OpenType fonts are bundled for the on-screen-text font picker. They come
from **mixed sources with different licenses**, and several are **proprietary**.

**Open-licensed (redistributable), SIL Open Font License / Ubuntu Font Licence:**

| Font | Typical license |
| --- | --- |
| Fira Sans (Bold / Light / Medium) | SIL OFL 1.1 |
| Poppins | SIL OFL 1.1 |
| Ubuntu | Ubuntu Font Licence 1.0 |
| Barlow Condensed | SIL OFL 1.1 |
| Changa | SIL OFL 1.1 |
| Cinzel Decorative | SIL OFL 1.1 |
| Exo | SIL OFL 1.1 |
| Russo One | SIL OFL 1.1 |

> The SIL OFL and Ubuntu Font Licence permit bundling and redistribution but require
> that the license text accompany the font. Those license texts **are included** in
> `assets/fonts/LICENSES/` (one per font family; see the README there), so these fonts
> are compliant to redistribute.

**Proprietary / commercial — redistribution NOT permitted (should be removed):**

| Font | Owner / note |
| --- | --- |
| Arial Bold, Arial Narrow | Monotype - proprietary, not redistributable |
| Gotham Narrow, Gotham Narrow Ultra | Hoefler & Co. - commercial, not redistributable |
| Avant Garde ("Avant Garde Naowh") | ITC / Monotype - proprietary |

**Unverified / redistribution not confirmed:**

| Font | Note |
| --- | --- |
| Expressway, Expressway Bold | Typodermic - free for some uses; license not confirmed here |
| Future X Black | source/license not identified |
| Homespun | commonly distributed free; license not confirmed here |
| KMT Kimberley, KMT Ninja Naruto | source/license not identified |

---

## 6. Bundled sounds (`Sounds/`)

The 64 cue-sound files come from **mixed community sources**. Provenance was inspected
from each file's embedded metadata; most files carry **no license information**, so
their redistribution rights **could not be verified**.

**Identified from embedded metadata:**

| Source (ARTIST tag) | Files | Note |
| --- | --- | --- |
| **Piffz** | 25 | Well-known WoW community boss-mod/call-out sounds (Adds, Boss, Circle, Cross, Diamond, DontRelease, Empowered, Focus, Idiot, Left, Moon, Next, Portal, Protected, Release, Right, RunAway, Skull, Spread, Square, Stack, Star, Switch, Taunt, Triangle). No explicit license found in the files. **Redistribution rights unverified.** |
| **qubodup / Iwan Gabovitch** | 1 | `DoubleWhoosh.ogg` - the file's own comment states *"I release this file into the public domain."* **Public domain (verified from file).** |
| **RICHERlandTV / Richard Litherland** | 1 | `ErrorBeep.ogg` - a freesound.org author; the specific license is **not stated in the file** and is unverified. |
| *(no author tag)* | 37 | No artist/license metadata. Some carry only editing-software or date hints (e.g. FL Studio, Adobe Audition, TASCAM recorder). **Origin and redistribution rights unknown/unverified.** |

**Only `DoubleWhoosh.ogg` can be confirmed as freely redistributable (public domain).**
The addon's GPL v2 license does **not** apply to any of these sound files. They are
**not** claimed to be licensed by WeakAuras.

> **Action needed before public distribution.** The redistribution rights for the Piffz
> sounds and the 37 untagged sounds are **not verified**. Before publishing, either
> confirm permission/licensing for each file, replace them with sounds under a known
> permissive/CC0 license, or remove them. This file will be updated once provenance is
> confirmed.

---

*If you are a rights holder for any bundled material and believe it is included in
error, please contact the addon author and it will be removed.*
