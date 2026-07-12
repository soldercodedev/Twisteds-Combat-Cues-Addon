# Twisteds Combat Cues

A lightweight, dependency-free World of Warcraft **Retail** addon that fires
**audible and visual cues** based on **rules you build yourself**. Each rule
watches a set of conditions (in combat, no target, a buff missing, a spell off
cooldown, an instance type, a health/resource threshold, …) and plays a cue when
they're met.

Built by **Twisted Modding**. Version **1.1.1**.

---

## What it does

The addon is a small **rule engine**. A **rule** is:

- a **name**,
- a list of **conditions** combined with **All** (every condition true) or
  **Any** (at least one true), and
- an **action**: which sound to play, an optional looping sound, an optional
  chat message, and an optional center-screen visual.

When a rule's conditions become true, its cue fires **once** on entry (respecting
a per-rule cooldown). It resets when the conditions stop being true. You manage
all of this in a standalone **Cue Manager** window.

The addon ships with one default rule — **"No target in combat"** — reproducing
the original behavior. You can edit it, disable it, or add your own.

---

## Installation

1. Copy **both** folders into `World of Warcraft\_retail_\Interface\AddOns\`:

   ```
   ...\Interface\AddOns\TwistedsCombatCues\TwistedsCombatCues.toc
   ...\Interface\AddOns\TwistedsCombatCues_DB\TwistedsCombatCues_DB.toc
   ```

   - **`TwistedsCombatCues`** — the addon.
   - **`TwistedsCombatCues_DB`** — the spell/item search databases. It's
     **load-on-demand**: it uses no memory until you first open the spell/icon
     picker, and the parsed index is freed a few seconds after the picker closes.
     If this folder is missing, the addon still works — spell/buff search just
     falls back to your spellbook, active auras, and pasting IDs.

2. Restart the game or type `/reload`.
3. Ensure *Twisteds Combat Cues* is enabled in the AddOns list. (You don't need to
   enable the `_DB` addon — it loads on demand.)

---

## Slash commands

| Command | Action |
|---|---|
| `/tcc` or `/twistedscombatcues` | Open/close the **Cue Manager** window |
| `/tcc config` | Open the Cue Manager |
| `/tcc options` | Open the global options (Blizzard Settings panel) |
| `/tcc on` / `/tcc off` | Enable / disable all cues |
| `/tcc test` | Play a test cue and flash the visual |
| `/tcc move` | Unlock the visual to drag it; run again to lock |
| `/tcc status` | List rules and which are currently active |
| `/tcc reset` | Reset **all** settings and rules (confirmation required) |
| `/tcc reset confirm` | Actually perform the reset |

All chat output is prefixed with `Twisteds Combat Cues:`.

---

## The Cue Manager

Open with `/tcc`. It's a single self-skinned window (dark theme, mint accent) —
**all options live here**; the Blizzard panel is just a launcher.

- **Left sidebar:** every rule as a nav item with an on/off toggle. Click a rule
  to edit it. **+ New Rule** (opens the template menu) and **Global Options** sit
  at the bottom. The window is movable (drag the header) and closes with Escape.
- **Right — Editor:** edit the selected rule:
  - **Rule name**, **Enabled** toggle, **Match All / Any**
  - **Conditions** — add/remove rows; each row picks a condition type and its
    parameters
  - **Action** — sound (with **Test**), play-sound, cooldown, loop + interval,
    chat message, and a visual with custom **text**, **color**, and **pulse**
  - **Duplicate** / **Export Rule** / **Delete Rule**
- **Global Options** (sidebar button): enable addon, rules profile + copy buttons,
  sound channel, visual scale, **theme accent color**, **Move visual on screen**,
  **Import / Export All**, and Reset.

### Condition types

| Type | What it checks | Notes |
|---|---|---|
| **Combat state** | In combat / out of combat | Event-driven |
| **Target state** | No target / has target / hostile & alive / dead / attackable | Event-driven |
| **Buff / aura on you** | A buff is *missing*, *present* (proc gained), or *time left ≤ N sec* | Search by name or ID; time-left needs polling |
| **Spell ready** | A spell (by name *or* ID) is off cooldown | Use the search icon to find it; ignores the global cooldown; needs polling |
| **Instance type** | In any instance / not in an instance / Dungeon / Raid / Arena / Battleground / Scenario | Event-driven (zone change) |
| **Group / raid** | In a group / not in a group / in a raid / not in a raid | Event-driven (roster change) |
| **Health / Resource %** | Player health or primary resource above/below a % | Needs polling |

### One-click alert templates

The **New Rule** button opens a menu of ready-made alerts:

- **No target (in combat)** — the classic no-target warning.
- **Missing buff** — fires in combat when a buff you pick is missing.
- **Spell off cooldown** — fires in combat when a spell you pick is ready.
- **Buff / proc gained** — fires when a buff/proc you pick becomes active.
- **Blank rule** — start from nothing.

Templates that need a spell start with an empty field — click the search icon to
fill it in.

### Finding spells and buffs

For **Buff / aura** and **Spell ready** conditions, the parameter shows a small
**icon** next to a text box:

- **Type** a spell/buff **name**, a **partial** name, or a numeric **spell ID**.
- **Click the icon** to open the **Find Spell / Buff** search popup. As you type,
  it lists matches — each with its **icon, name, and ID** — and hovering a result
  shows its full in-game **tooltip**. Click one to fill the field.
- The icon in the editor updates to the chosen spell, and hovering it shows the
  tooltip so you can confirm the right spell was picked.

Search results come from three sources:

1. A **bundled spell database** (`SpellDB.lua`, ~165k spells) — type **3+ letters**
   to search it.
2. Your **currently-active auras** and **spellbook** (surfaced even with 1–2
   letters).
3. **Direct ID lookup** — type a numeric spell ID.

Icons and tooltips are always resolved live from the game client, so every result
shows the correct art. Storing the **ID** (which happens automatically when you
pick from the search) is the most reliable option — it is language-independent and
unambiguous.

> WoW addons cannot access the internet, so the database is a **bundled snapshot**
> built offline from [wago.tools](https://wago.tools/db2). It reflects the client
> version it was generated against; regenerate it after a patch (see below). If a
> brand-new spell isn't in the snapshot yet, paste its numeric ID.

### Updating the spell database

`SpellDB.lua` is generated by `Tools/generate_spelldb.py` (requires Python 3, no
extra packages). To refresh it for a new patch:

```
cd TwistedsCombatCues/Tools
python generate_spelldb.py            # downloads latest data from wago.tools
```

This pulls the `SpellName` and `SpellMisc` tables from wago.tools, keeps spells
that have an icon (dropping internal/test entries), removes duplicate names, and
writes `SpellDB.lua`. Useful flags: `--build <version>` to pin a client build,
`--keep-duplicates` for every spell id, `--keep-iconless` / `--keep-junk` to skip
filtering. The addon still works if `SpellDB.lua` is missing — search just falls
back to spellbook/auras/ID.

### Example rules

- **Refresh a buff:** Match **All** — `In combat` + `Buff "Mark of the Wild" is
  missing`. Action: Warning Siren + visual "BUFF".
- **Use a cooldown:** Match **All** — `In combat` + `Spell "Kill Command" ready`.
  Action: a short custom sound, no visual.
- **Low health warning:** Match **Any** — `Health below 30%`. Action: Heartbeat,
  looping every 1.5s.

---

## Global options

Open the **Global Options** view from the sidebar (or `/tcc options`):

- **Enable addon** — master on/off.
- **Rules profile** — *Account-wide (shared)* or *This character only*, plus a
  From / Rule / To copier (copy every rule or one rule between any profiles).
- **Sound channel** — defaults to **Master** so cues are audible even when Sound
  Effects volume is low.
- **Window scale** — size of the Cue Manager window.
- **Check interval** — how often *polling* conditions (spell ready, resource %,
  buff time-left) are re-checked. Higher = less CPU, slightly less responsive;
  event-driven conditions (combat, target, auras, zone, group, spec) are unaffected.
- **Theme accent** — recolor the interface accent.
- **Minimap button** — show/hide it.
- **Import / Export All Rules** — see Sharing.
- **Reset Active Profile**.

Per-rule visual text/icon **color, font, size, pulse, and on-screen position** are
set in each rule's editor (not here) — see the ACTION section of a rule.

---

## The visual warning: color and position

- **Color** is **per rule** — each rule's action has a color swatch next to its
  visual text. Click it to open the standard color picker.
- **Position** is **global** (one on-screen spot for whichever cue is showing).
  Click **Move visual on screen** in Global Options, or type `/tcc move`: the
  window hides and a sample **NO TARGET** appears — drag it anywhere, then run
  `/tcc move` again to lock. The position is saved per profile.

---

## Sharing rules (import / export)

Rules can be shared as text strings:

- **Export Rule** (in a rule's editor) or **Export All Rules** (Global Options)
  produces a string starting with `TCC1!` / `TCCX1!`. The dialog selects it for
  you — press **Ctrl+C**.
- **Import Rule(s)** (Global Options) — paste a string and click **Import**.
  Imported rules are added (never overwrite existing ones) and given fresh IDs.

The string is a base64-encoded snapshot of the rule(s). Import parses it in a
**sandbox with no access to game functions** and validates the structure, so a
malformed or hand-edited string fails safely rather than running code. Strings are
self-contained — sounds resolve by key and spells by ID/name on the recipient's
client.

---

## Account-wide vs. per-character rules

Each character can use either:

- **Account-wide (shared)** — one rule set shared by all your characters
  (`TwistedsCombatCuesDB`). The default.
- **This character only** — a private rule set just for this character
  (`TwistedsCombatCuesCharDB`).

Switch with the **Rules profile** dropdown in `/tcc options`. Each character
remembers its own choice, so you can (for example) keep shared rules on most
characters and a custom set on one.

The two **Copy** buttons move your current rules between profiles (a deep copy —
the profiles stay independent afterward), which is the easy way to start a
character profile from your account-wide rules. **Reset Active Profile** only
resets whichever profile is currently active; the other is left untouched.

---

## Sounds

The **Sound** dropdown in each rule's action is split into two groups:

- **Blizzard Sounds** — built-in game sounds (Raid Warning, Ready Check, Alarm
  Clock, Map Ping, Subtle Notification, PvP Warning), played via `PlaySound`.
- **Custom Sounds** — 60+ files bundled in the `Sounds/` folder, played via
  `PlaySoundFile`.

Selecting any entry previews it immediately.

### Adding your own sound file

1. Drop an `.ogg` (recommended) or `.mp3` into `Sounds/`.
2. Add a row to `TCC.SOUNDS` in **`Sounds.lua`**, e.g.
   `{ key = "MyAlert", label = "My Alert", file = "MyAlert.ogg" }`.
3. `/reload`. It appears under **Custom Sounds**.

Safety: `SOUNDKIT` constants are verified at runtime and a missing/unsupported
file falls back to **Raid Warning**, so a bad entry never errors.

---

## File structure

```
TwistedsCombatCues/
├── TwistedsCombatCues.toc   # Metadata + load order + SavedVariables
├── Sounds.lua               # Sound catalog + playback (PlaySound / PlaySoundFile)
├── Conditions.lua           # Condition types (metadata) + rule evaluation
├── SpellDB.lua              # Bundled spell-name search index (auto-generated)
├── Core.lua                 # Engine, per-rule state, events, saved vars, slash
├── UI.lua                   # Standalone Cue Manager window + spell picker
├── Options.lua              # Global options (Blizzard Settings panel)
├── Sounds/                  # Bundled custom sound files (.ogg / .mp3)
├── Tools/
│   └── generate_spelldb.py  # Offline script to regenerate SpellDB.lua
└── README.md                # This file
```

Saved variables live in **`TwistedsCombatCuesDB`** (account-wide) and
**`TwistedsCombatCuesCharDB`** (per character); each holds global options + a
`rules` array. Defaults are merged in after updates without overwriting your
rules or choices.

---

## How it evaluates (performance)

- The engine is **event-driven** for combat, target, aura, spell-cooldown, and
  zone changes.
- Conditions that events can't catch — **Spell ready**, **Health/Resource %**,
  and **Buff time-left ≤ N** — are handled by a **throttled poller** that runs
  ~4×/second, and **only while at least one enabled rule needs it**. Rules built
  purely from combat/target/instance/buff-missing conditions use **no polling at
  all**.
- Each cue fires **once** when its rule becomes active; the per-rule cooldown
  prevents re-spam if conditions flap. Leaving the active state (or combat) resets
  it.

---

## Testing checklist

1. `/tcc` opens the Cue Manager; the default rule is listed.
2. `/tcc test` plays a sound and flashes **TEST**.
3. Enter combat with no target → the default rule fires **NO TARGET**.
4. Create a rule: **In combat** + **Buff "…" missing**, drop the buff in combat,
   confirm it fires; reapply the buff, confirm it stops.
5. Create a **Spell ready** rule for a known spell; use the spell (goes on
   cooldown → silent) and confirm it fires again when it comes back up.
6. `/tcc status` shows which rules are ACTIVE.
7. `/reload` in combat → active rules re-fire as appropriate.

---

## Troubleshooting

- **A buff/spell rule never fires:** if you typed a **name**, it must match
  exactly. The reliable fix is to click the **search icon**, find the spell, and
  select it so the rule stores its **ID**. Buff rules check auras on **you**.
- **No sound:** confirm the rule's *Play sound* is on, the addon is enabled
  (`/tcc status`), Master volume is up, and Sound is enabled in game options.
- **Manager looks empty / errors:** `/reload`; make sure all files (including the
  `Sounds/` folder) are present and the folder is named exactly
  `TwistedsCombatCues`.
- **"Interface out of date":** update `## Interface:` in the TOC. Get the current
  value with `/run print((select(4, GetBuildInfo())))`.

---

## Current WoW API notes / limitations

- The addon **only warns** — it never targets, casts, or uses any protected
  action.
- **Target state "dead"** and **hostile & alive** use `UnitIsDeadOrGhost` /
  `UnitCanAttack`; the plain "has target" uses `UnitExists`.
- Buff detection prefers `C_UnitAuras.GetPlayerAuraBySpellID` (exact ID, covers
  buffs and debuffs on you) and falls back to `AuraUtil.FindAuraByName`.
- Spell readiness uses `C_Spell.GetSpellInfo` / `C_Spell.GetSpellCooldown` and
  ignores the global cooldown (~1.5s).
- The spell/buff search reads your spellbook (`C_SpellBook`), active auras
  (`C_UnitAuras`), direct ID lookups (`C_Spell.GetSpellInfo`), and a bundled
  offline-generated index (`SpellDB.lua`). Addons cannot query the game database
  at runtime, so the index is a snapshot regenerated per patch from wago.tools.
- The bundled database is stored as a single string blob and parsed at first use
  (Lua 5.1 caps constants per function, so a giant table literal would fail to
  load); the raw blob is freed after the index is built.
- Instance type uses `IsInInstance`; resource/health uses `UnitHealth` /
  `UnitPower`. Combat state uses `UnitAffectingCombat("player")`.
- Only one center-screen visual shows at a time (the first active rule that
  requests a visual, in list order).
