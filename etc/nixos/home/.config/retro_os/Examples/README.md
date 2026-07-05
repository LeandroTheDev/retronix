# Tutorial: Exporting achievements from RetroAchievements to retro_os

This guide explains how to grab a game's official achievement set from
RetroAchievements and convert it to the `game_achievements.json` format used
by retro_os.

---

## Step 1 — Find the GameId on RetroAchievements

Open the game's page on `retroachievements.org`. The number at the end of the
URL is the GameId:

```
https://retroachievements.org/game/10003   → Super Mario 64  (GameId = 10003)
https://retroachievements.org/game/10246   → Kirby 64        (GameId = 10246)
```

---

## Step 2 — Download the data via API

You need a RetroAchievements account to get an API key. After logging in, go to
`Settings → API Key` to copy it.

```bash
curl -s "https://retroachievements.org/API/API_GetGameExtended.php?z=YOUR_USER&y=YOUR_KEY&i=GAME_ID&f=3" \
  > game_data.json
```

Replace `YOUR_USER`, `YOUR_KEY`, and `GAME_ID` with the correct values.

To extract only what matters (title, description, points, and conditions for
each achievement):

```bash
jq '[.Sets[0].Achievements[] | {Title, Description, Points, MemAddr}]' game_data.json
```

---

## Step 3 — Understand the MemAddr format

Each achievement has a `MemAddr` field containing a condition string. Real
example from Kirby 64 ("Waddle On!"):

```
0xH0d6b98=0_0xH0d6b44=39_0xO0d6bcb=1
```

### Separators and condition prefixes

| Token | Meaning | JSON field |
|---|---|---|
| `_` | AND separator between conditions | (implicit — just list conditions in order) |
| `R:` | ResetIf — wipes all hit-count progress if satisfied | `"isResetIf": true` |
| `P:` | PauseIf — freezes hit counts this poll (nothing gained, nothing lost) | `"isPauseIf": true` |
| `T:` | Trigger — must be true at the exact poll of unlock, not counted as a unit | `"isTrigger": true` |
| `Z:` | ZeroReset / ResetNextIf — resets only the next condition's hit count | `"isResetNextIf": true` |
| `A:` | AddSource — adds this address's value to the left operand of the next condition | `"isAddSource": true` |
| `B:` | SubSource — subtracts this address's value from the left operand | `"isSubSource": true` |
| `I:` | AddAddress — treats this address's value as a pointer offset for the next condition | `"isAddAddress": true` |
| `C:` | AddHits — adds this condition's hit tally into the next hit-counted condition | `"isAddHits": true` |
| `D:` | SubHits — subtracts this condition's hit tally | `"isSubHits": true` |
| `N:` | AndNext — chains with the next condition using AND | `"chain": "and"` |
| `O:` | OrNext — chains with the next condition using OR | `"chain": "or"` |
| `S` (group separator) | OR alt-group — achievement unlocks when core + any one alt group done | `"altGroups": [...]` |
| `M:` | Measured — **not supported** (progress display only; for unlock purposes treat as a normal hit-counted condition) | — |

### Read size (address prefix)

| MemAddr token | `size` in JSON |
|---|---|
| `0xH` | `"byte"` (8-bit) |
| `0x ` (space) | `"word"` (16-bit) |
| `0xW` | `"word"` (24-bit) |
| `0xX` | `"dword"` (32-bit) |
| `0xM` | `"bit0"` |
| `0xN` | `"bit1"` |
| `0xO` | `"bit2"` |
| `0xP` | `"bit3"` |
| `0xQ` | `"bit4"` |
| `0xR` | `"bit5"` |
| `0xS` | `"bit6"` |
| `0xT` | `"bit7"` |
| `0xU` | `"nibbleLow"` |
| `0xV` | `"nibbleHigh"` |
| `0xK` | `"bcd"` (Binary-Coded Decimal — each nibble is one decimal digit) |

### Delta (previous value)

A `d` before the address prefix means "value from the previous poll":

| MemAddr | JSON |
|---|---|
| `d0xH0eb8a0` | `"compareTarget": "previousValue"` on the same condition |

When the delta appears on the **right-hand side** (`0xH addr < d0xH addr`),
translate as a condition with `"op": "lessThan"` and
`"compareTarget": "previousValue"`.

When the delta appears on the **left-hand side** (`d0xH addr = literal`),
translate as a condition with `"readPrevious": true` and `"value": <literal>`.
This reads the previous poll's value and compares it against a fixed number.

### Comparison operators

| MemAddr | `op` in JSON |
|---|---|
| `=` | `"equals"` |
| `!=` | `"notEquals"` |
| `>` | `"greaterThan"` |
| `<` | `"lessThan"` |
| `>=` | `"greaterOrEqual"` |
| `<=` | `"lessOrEqual"` |

### Hit count

`.N.` at the end of a condition maps to `targetHits`:

```
0xH0d6b44=27.5.   →   "targetHits": 5
```

---

## Step 4 — Translate to retro_os JSON

### Simple example — "Waddle On!" (Kirby 64)

Original MemAddr:
```
0xH0d6b98=0_0xH0d6b44=39_0xO0d6bcb=1
```

Translated:
```json
{
  "id": "waddle_on",
  "title": "Waddle On!",
  "description": "Defeat the possessed Waddle Dee and have him join your party",
  "points": 2,
  "conditions": [
    { "address": "0x0d6b98", "size": "byte", "op": "equals", "value": 0 },
    { "address": "0x0d6b44", "size": "byte", "op": "equals", "value": 39 },
    { "address": "0x0d6bcb", "size": "bit2", "op": "equals", "value": 1 }
  ]
}
```

### Example with ResetIf and hit count — "I Speak For The Trees!" (Kirby 64)

Original MemAddr:
```
R:0xH0d6e8c<d0x0d6e8c_R:0xH0d6b98!=0_0xH0d6b44=27.5._0xH0d6b44=24_R:0xH3387b2=1_R:0xH12e850!=0_0xH0e03f8=23
```

Translated:
```json
{
  "id": "i_speak_for_the_trees",
  "title": "I Speak For The Trees! Let It Grow!!",
  "description": "Defeat Whispy Woods without abilities or taking damage",
  "points": 1,
  "conditions": [
    { "address": "0x0d6e8c", "size": "byte", "op": "lessThan", "compareTarget": "previousValue", "isResetIf": true },
    { "address": "0x0d6b98", "size": "byte", "op": "notEquals", "value": 0, "isResetIf": true },
    { "address": "0x0d6b44", "size": "byte", "op": "equals", "value": 27, "targetHits": 5 },
    { "address": "0x0d6b44", "size": "byte", "op": "equals", "value": 24 },
    { "address": "0x3387b2", "size": "byte", "op": "equals", "value": 1, "isResetIf": true },
    { "address": "0x12e850", "size": "byte", "op": "notEquals", "value": 0, "isResetIf": true },
    { "address": "0x0e03f8", "size": "byte", "op": "equals", "value": 23 }
  ]
}
```

### What to do with unsupported conditions

The only condition type retro_os does **not** support is `M:` (Measured). This
type is mainly a UI hint (it exposes a "progress counter" in the RA website and
app) — for actual unlock logic it behaves like a regular hit-counted condition.

Options when you encounter `M:`:
1. **Treat as a normal condition** — translate it like any other condition with
   `targetHits` set. The unlock will behave correctly; only the "measured
   progress" display will be missing.
2. **Skip** the achievement if the `M:` semantics are critical and you don't
   want to approximate.

---

## Step 5 — Full field reference

### Achievement level

| Field | Required | Notes |
|---|---|---|
| `id` | yes | Stable unique key — never change after "publishing", it is used for saved progress |
| `title` | yes | Display name |
| `description` | yes | Display description |
| `points` | no (default 0) | Free-form score, no fixed convention |
| `conditions` | yes | List — the core group; all units must complete |
| `altGroups` | no | List of condition lists — achievement also requires **any one** alt group to be fully done (OR between alt groups). Mirrors RetroAchievements' `S`-separated groups |

### Condition level

| Field | Required | Values | Notes |
|---|---|---|---|
| `address` | yes | hex string, e.g. `"0x0eb8a0"` | 0-based RDRAM offset (same addressing as RetroArch's Cheat Search) |
| `size` | yes | `"bit0"`..`"bit7"`, `"nibbleLow"`, `"nibbleHigh"`, `"byte"`, `"word"`, `"tribyte"`, `"dword"`, `"bcd"` | bit/nibble reads request one byte and mask it; word/dword combine big-endian; bcd decodes each nibble as a decimal digit |
| `op` | yes (omit only for `isAddAddress`/`isAddSource`/`isSubSource`) | `"equals"`, `"notEquals"`, `"greaterThan"`, `"lessThan"`, `"greaterOrEqual"`, `"lessOrEqual"` | |
| `value` | required when `compareTarget` is `"literal"` | integer | Comparison target |
| `compareTarget` | no (default `"literal"`) | `"literal"` \| `"previousValue"` \| `"otherAddress"` | `"previousValue"` compares against this address's last-poll value; `"otherAddress"` compares against a different address (requires `compareAddress` + `compareSize`) |
| `compareAddress` | required when `compareTarget` is `"otherAddress"` | hex string | Address to read for the right-hand operand |
| `compareSize` | required when `compareTarget` is `"otherAddress"` | same values as `size` | |
| `compareReadPrevious` | no (default false) | bool | When `compareTarget` is `"otherAddress"`, read the compare address from the previous poll |
| `readPrevious` | no (default false) | bool | Read *this* condition's own address from the previous poll (delta on the left operand — `d0xH addr = literal`) |
| `isResetIf` | no (default false) | bool | If satisfied, wipes this entire achievement's hit-count progress and blocks unlock this poll |
| `isPauseIf` | no (default false) | bool | If satisfied, freezes all hit counts in this group this poll (nothing gained, nothing lost) |
| `isTrigger` | no (default false) | bool | Must be currently satisfied at the exact poll of unlock; not counted as a hit unit |
| `isResetNextIf` | no (default false) | bool | If satisfied, zeroes the hit count of the next terminal condition in this group only |
| `isAddAddress` | no (default false) | bool | Adds this address's value as a pointer offset to the next condition's address |
| `isAddSource` | no (default false) | bool | Adds this address's value to the left operand of the next real condition |
| `isSubSource` | no (default false) | bool | Subtracts this address's value from the left operand of the next real condition |
| `isAddHits` | no (default false) | bool | Folds this condition's hit tally into the next hit-counted condition |
| `isSubHits` | no (default false) | bool | Subtracts this condition's hit tally from the next hit-counted condition |
| `chain` | no (default `"none"`) | `"none"` \| `"and"` \| `"or"` | Combines this condition with the next using AND/OR before comparing to the terminal's hit count |
| `onlyOnChange` | no (default false) | bool | Edge-trigger: only counts on the false→true transition |
| `targetHits` | no (default no memory) | integer | How many times the condition must be satisfied (latches once reached, until a reset) |

---

## Step 6 — Where to put the file

The final file goes in:

```
<app data dir>/Consoles/<console>/Games/<game name>/game_achievements.json
```

Example for Kirby 64 on N64:

```
~/.local/share/retro_os/Consoles/Nintendo 64/Games/Kirby 64: The Crystal Shards/game_achievements.json
```

The example file `super_mario_64_achievements.json` in this same folder has 10
SM64 achievements translated from RA's real set, including `isResetIf`,
`compareTarget: "previousValue"`, and bit-level reads — good reference for
more complex achievements.
