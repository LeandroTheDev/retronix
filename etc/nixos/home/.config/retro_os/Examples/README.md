# Local Achievements for retro_os — design notes

Context dump of everything decided so far, so this can be picked up again in
a later session without re-deriving it.

## Goal

Add achievements for N64 games in `retro_os`, triggered locally while
playing — no RetroAchievements.org account, no internet connection, no
official achievement sets required.

## Why not just use RetroAchievements/RetroArch's built-in Cheevos support

RetroArch already has native RetroAchievements support, but:
- It requires an account and a server-side hash lookup to fetch a game's
  achievement set.
- A fully local, no-account mode isn't offered — even RA's own "Local"
  achievement authoring flow (via RAIntegration/RALibretro's dev tools)
  requires logging in with an account that has developer permission granted
  by the RA website, at least once.

Since the goal is fully local, custom, account-free achievements, we're
building a small independent system instead of trying to route through RA.

## Why not use `rcheevos` (RA's open-source condition-evaluation library) — original decision

`rcheevos` is open source (MIT, github.com/RetroAchievements/rcheevos) and
would need Dart FFI bindings to use from `retro_os`. It solves a problem we
thought we didn't have: speaking the *same condition grammar* as the
official RA server, so community-authored achievement sets can be reused.
Since the plan was to author our own achievements from scratch in our own
JSON format, a small evaluator written in pure Dart seemed to cover what we
need (comparisons, hit counts, change-detection) without a native build step
or FFI.

**Resolved (see "New finding" below):** still no FFI/rcheevos — instead the
pure-Dart evaluator's condition model was extended with the extra primitives
(`ResetIf`, delta comparisons, bit-level reads) that real RA achievements
turned out to need, and achievements are still hand-translated into our own
JSON rather than parsing the `MemAddr` string format directly.

## Architecture

`retro_os` does **not** embed a libretro core — it launches the real
`retroarch` binary as a separate OS process
(`lib/pages/nintendo64_game_open.dart`, via `Process.start('retroarch', ...)`).
This means the Flutter app has no direct memory access to the emulated N64
RAM; something has to bridge the two processes.

**The bridge: RetroArch's built-in Network Command Interface** (UDP, default
port 55355). This is an official RetroArch feature — the same one speedrun
autosplitters (e.g. LiveSplit integrations) use to read game memory without
writing a custom core. Relevant command:

```
READ_CORE_RAM <address_hex> <byte_count>
```

Reply format:
```
READ_CORE_RAM <address_hex> <byte> <byte> ...      (success)
READ_CORE_RAM <address_hex> -1                     (failure)
```

Addresses are 0-based offsets into RDRAM (the same addressing RetroArch's
own in-app Cheat Search and RALibretro's Memory Inspector use) — **not** the
MIPS virtual address (`0x80000000+`) games use internally. No conversion
needed between "address found via memory search" and "address used in
`READ_CORE_RAM`".

**Not yet done:** enabling the network command interface. RetroArch needs
`network_cmd_enable = "true"` added to the override cfg that
`SettingsService.applyRetroarchOverrides()` (`lib/utils/settings_service.dart`)
already writes and passes via `--appendconfig`. This hasn't been wired in yet.

## Code structure (implemented)

```
lib/services/achievements/
├── achievement.dart                # model: id, title, description, points, conditions
├── achievement_service.dart        # orchestrator: owns the poll loop + persistence
├── avaliadores/
│   ├── achievement_condition.dart  # condition model (address, size, op, value, hits, onlyOnChange)
│   └── achievement_evaluator.dart  # pure logic: hit counts, change-detection, decides unlocks
└── leitor_ram/
    └── retroarch_ram_reader.dart   # UDP client speaking READ_CORE_RAM to RetroArch
```

`lib/utils/devices.dart` gained `getGameAchievementsPath(console, game)`,
mirroring the existing `getGameImagePath(console, game)`.

### `RetroarchRamReader` (leitor_ram/)

- Opens a UDP socket, sends `READ_CORE_RAM <addr> <len>`, awaits the reply.
- Requests are serialized (one in flight at a time) because RetroArch's
  replies carry no request ID — there'd be no way to match an out-of-order
  reply to the request that caused it otherwise.
- `readBytes(address, length) -> Future<Uint8List?>`, null on timeout/failure.

### `AchievementCondition` / `satisfiesComparison` / `extractValue` (avaliadores/)

Fields: `address` (hex, RDRAM offset), `size`, `op` (`equals`/`notEquals`/
`greaterThan`/`lessThan`/`greaterOrEqual`/`lessOrEqual`), `value`, plus:
- `compareTarget` (`literal` default, or `previousValue`) — `literal`
  compares against `value`; `previousValue` compares the current poll's
  reading against *this same address/size's own reading from the previous
  poll* (e.g. `greaterThan` + `previousValue` = "this went up since last
  poll"). `value` is ignored (may be omitted) when using `previousValue`.
- `isResetIf` (bool, default false) — marks the condition as a watchdog, not
  part of the achievement's core AND set: if satisfied on a poll, every
  condition's hit-count progress for that achievement is wiped that poll
  instead of counting toward unlocking.
- `onlyOnChange` (bool, default false) — only counts on the false→true
  transition, not on every poll it happens to still hold.
- `targetHits` (int, default 1) — how many satisfied polls are needed before
  the condition counts as done (e.g. "defeat 50 enemies"). Once reached it
  stays done — doesn't need to hold every subsequent poll — unless wiped by
  an `isResetIf` condition.

`size` now covers bit-level reads too: `bit0`..`bit7`, `nibbleLow`,
`nibbleHigh`, `byte`, `word`, `dword`. Bit/nibble sizes still request a
single byte over the wire (`RetroarchRamReader.readBytes` is unchanged) —
`extractValue(size, rawBytes)` is the new piece that masks/shifts it down to
the actual condition value; `byte`/`word`/`dword` still combine bytes
big-endian same as before.

**Still not supported** (not needed by any achievement translated so far):
`PauseIf`, and OR condition groups (`AddSource`/`SubSource`/alt groups).

### `AchievementEvaluator` (avaliadores/)

Pure logic, no I/O. Tracks per-condition hit counts and last-satisfied state
across polls. `tick(achievements, currentValue, previousValue)` — two
lookup callbacks now, one for this poll's reading and one for last poll's
(needed for `previousValue`-target conditions) — returns the achievements
that just transitioned from locked to unlocked on this call. `ResetIf`
conditions are checked first, independently of the core AND set: if any is
satisfied, the achievement's hit-count state is wiped and it's skipped for
that poll entirely. Already-unlocked achievements are skipped.
`restoreUnlocked(ids)` seeds already-earned achievements (loaded from disk)
so they don't refire.

### `AchievementService` (top-level orchestrator)

Singleton (`AchievementService.instance`). `startWatching(console, game)`:
loads definitions, restores unlocked progress, connects the RAM reader,
starts a 500ms `Timer.periodic` poll loop. Each poll batches reads by
`address:sizeName` (dedup key includes the size *name*, not just its byte
count, since e.g. `bit2` and `bit3` both read a single byte over the wire
but extract a different value from it), feeds both this poll's and the
previous poll's snapshot into the evaluator (`_previousSnapshot` field, so
`previousValue`-target conditions have something to compare against), and
persists any new unlocks. `stopWatching()` tears it all down, including
clearing `_previousSnapshot` so a new game never sees a stale delta
baseline.

**Not yet wired in:** nothing in `nintendo64_game_open.dart` calls
`startWatching`/`stopWatching` yet, and there's no unlock-notification UI
(the plan is to reuse the visual pattern already established by
`GameOverlayPage`).

## JSON schema (our own format — see "New finding" for a possible alternative)

### Definitions — `<Consoles>/<console>/Games/<game>/game_achievements.json`

Authored by hand, lives next to `game_image.*` (it's game content, not app
state). A JSON array of achievement objects:

```json
[
  {
    "id": "collected_100_coins",
    "title": "Collector",
    "description": "Collect 100 coins in a single playthrough",
    "points": 10,
    "conditions": [
      { "address": "0x0eb8a0", "size": "byte", "op": "greaterOrEqual", "value": 100 }
    ]
  },
  {
    "id": "got_first_star",
    "title": "First Star",
    "description": "Get your first star",
    "points": 25,
    "conditions": [
      { "address": "0x0eb920", "size": "byte", "op": "greaterThan", "value": 0, "onlyOnChange": true }
    ]
  },
  {
    "id": "defeated_50_enemies",
    "title": "Exterminator",
    "description": "Defeat 50 enemies throughout the game",
    "points": 50,
    "conditions": [
      { "address": "0x0eb9a0", "size": "word", "op": "equals", "value": 1, "onlyOnChange": true, "targetHits": 50 }
    ]
  }
]
```

A working copy of this exact example lives at
`Examples/game_achievements.json` in this same folder.

Field reference — achievement level:

| Field | Required | Notes |
|---|---|---|
| `id` | yes | stable unique key, used for persisted progress — never change after "publishing" |
| `title` | yes | displayed name |
| `description` | yes | displayed description |
| `points` | no (default 0) | free-form scoring, no fixed convention |
| `conditions` | yes | list; **all must hold at once (AND)** — no OR groups in this version |

Field reference — condition level:

| Field | Required | Values | Notes |
|---|---|---|---|
| `address` | yes | hex string, e.g. `"0x0eb8a0"` | 0-based RDRAM offset (see Architecture section) |
| `size` | yes | `"bit0"`..`"bit7"`, `"nibbleLow"`, `"nibbleHigh"`, `"byte"`, `"word"`, `"dword"` | bit/nibble read a single byte and mask it down; byte/word/dword combine big-endian |
| `op` | yes | `"equals"`, `"notEquals"`, `"greaterThan"`, `"lessThan"`, `"greaterOrEqual"`, `"lessOrEqual"` | |
| `value` | required unless `compareTarget` is `"previousValue"` | integer | comparison target |
| `compareTarget` | no (default `"literal"`) | `"literal"` \| `"previousValue"` | `previousValue` compares against this same address/size's own reading from the previous poll instead of `value` |
| `isResetIf` | no (default false) | bool | watchdog — if satisfied, wipes this achievement's hit-count progress that poll instead of counting toward unlock |
| `onlyOnChange` | no (default false) | bool | edge-trigger instead of level-trigger |
| `targetHits` | no (default 1) | integer | "do X N times" counter — latches once reached |

### Real-world example — Super Mario 64

`Examples/super_mario_64_achievements.json` has 10 achievements
hand-translated from RA's real Super Mario 64 achievement set (see "New
finding" below) using all of the fields above, including `isResetIf`,
`compareTarget: "previousValue"`, and `bit2`/`bit3` reads (the Metal
Cap/Vanish Cap flags). Good reference for what a real, non-trivial
achievement looks like in our schema.

### Progress (runtime state, not hand-edited)

`<app data dir>/achievements/progress/<console>/<game>.json` — a plain JSON
array of unlocked achievement `id` strings. Separate from the definitions
file on purpose: definitions are content you author, progress is state the
app owns.

## Finding memory addresses

Use **RetroArch's built-in Cheat Search** (`Cheats` → `Start or Continue
Cheat Search` in the RetroArch menu) — no extra tool needed. Classic
diff-search flow: start search, make the value change in-game, narrow down
by "Search Equal To" / "Increased By" / etc., repeat until one address
survives. This uses the exact same RDRAM-offset addressing as
`READ_CORE_RAM`, so whatever address the search finds drops straight into
`game_achievements.json` with no conversion.

Alternative with a nicer live-memory view: **RALibretro's Memory Inspector**
(github.com/RetroAchievements/RALibretro, open source) — same addressing,
more comfortable for watching several values at once. Doesn't require RA
developer permissions for the memory inspector itself (only RA's official
achievement *editor* does).

**Avoid Cheat Engine** (or any generic process memory scanner) for this —
it operates on `retroarch.exe`'s own virtual memory addresses, not the RDRAM
offset. You'd have to locate RDRAM's base pointer inside the process and
subtract it every time, and that pointer can shift between runs (ASLR). Only
worth it if the RetroArch/RALibretro tools genuinely can't find something.

## New finding: RetroAchievements' public API exposes real achievement data

While looking things up, the user pulled down RetroAchievements' own API
response for Super Mario 64 (`GameId: 10003`) — game metadata plus the full
official achievement set, including each achievement's real `MemAddr`
condition string. This is **not** RetroArch config, it's RA's own service
data (`Sets[0].Achievements[].MemAddr`, `.Title`, `.Description`, `.Points`).

Example `MemAddr`:
```
R:0xH32ddfa!=9_R:0xP33b174=1_0xH34dd1c>d0xH34dd1c.5._0x 33b17c=4866_...
```

This is literally the `rcheevos` trigger-string syntax. Cheat sheet:

| Token | Meaning |
|---|---|
| `R:` prefix on a condition | ResetIf — if true, zeroes hit-counts/progress for the whole achievement |
| `P:` prefix | PauseIf |
| `0xH` | 8-bit read |
| `0x ` (space, no letter) | 16-bit read |
| `0xW` | 24-bit read |
| `0xX` | 32-bit read |
| `0xN`/`0xO`/`0xP`... | single-bit reads (flags) |
| `d0xH...` | delta — that address's value on the *previous* frame/poll |
| `_` between conditions | AND |
| `.5.` suffix on a condition | hit-count target of 5 (same idea as our `targetHits`) |

Compared to our original `AchievementCondition`, real RA achievements
routinely used `ResetIf`, delta comparisons, and bit-level reads — none of
which our evaluator supported at the time. Our `targetHits`/AND/comparisons
already covered part of the grammar.

**Why this matters:** RA's game/achievement metadata for popular games
(including addresses) is reachable through their public API without needing
to hand-run Cheat Search ourselves — a potentially huge shortcut for
authoring `game_achievements.json` files for well-covered games like Mario
64.

**Decision made — landed on a hybrid of options 1 and 2:**

Of the three options originally on the table (1: hand-translate only the
simple ones, no code changes; 2: extend the evaluator + write a full
`MemAddr` string parser; 3: punt), we did **option 2's data model without
its parser**, then applied it via option 1's manual process:

- Extended `AchievementCondition`/`AchievementEvaluator` with exactly the
  three primitives the pulled Mario 64 achievements actually used —
  `isResetIf`, `compareTarget: previousValue` (delta), and bit-level `size`
  values (`bit0`..`bit7`, `nibbleLow`, `nibbleHigh`). See the updated field
  reference above.
- Did **not** write a `MemAddr` string parser — no `PauseIf`, no OR/alt
  groups (`AddSource`/`SubSource`), since nothing translated so far needed
  them.
- Hand-translated all 10 achievements from the pulled Super Mario 64 JSON
  into our schema — see `Examples/super_mario_64_achievements.json`.

If a future game's achievements need `PauseIf` or OR groups, extend the
evaluator further the same way: add just the primitive that's actually
needed, translate by hand, don't build a general `MemAddr` parser unless
translating by hand genuinely becomes the bottleneck.

## Open next steps

1. Add `network_cmd_enable = "true"` (and possibly `network_cmd_port`) to
   `SettingsService.applyRetroarchOverrides()`.
2. Wire `AchievementService.startWatching('Nintendo 64', widget.gameName)` /
   `stopWatching()` into `Nintendo64GameOpen`'s lifecycle
   (`lib/pages/nintendo64_game_open.dart`).
3. Build an unlock-notification UI (toast/overlay), likely reusing patterns
   from `GameOverlayPage`.
4. Move `super_mario_64_achievements.json` from `Examples/` to its real home
   once decided: `Consoles/Nintendo 64/Games/Super Mario 64/game_achievements.json`.
5. Author/port achievements for other games the same way (pull from RA's
   public API, hand-translate into our schema) as they come up.
