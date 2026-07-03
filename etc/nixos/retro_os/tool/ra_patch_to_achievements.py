#!/usr/bin/env python3
"""Converts a RetroAchievements "patch" API response (the JSON body of a
`r=patch` dorequest.php call, e.g. what tool/clean_http_debug_dump.py
extracts from a raw capture) into this app's achievements.json format
(see lib/services/achievements/avaliadores/achievement_condition.dart).

The app's evaluator supports: independent AND'd conditions, ResetIf, PauseIf,
AndNext/OrNext chains, alt groups (core AND (alt1 OR alt2...)), previous-value
comparisons on either side of a condition (including against a *different*
address), AddAddress pointer indirection, AddSource/SubSource value
accumulators, AddHits/SubHits hit-count accumulators, and drops the purely
cosmetic Trigger/Measured flags (they mark UI hints in the RA client - a
"challenge indicator" and a progress-bar value - that this app doesn't
render, and don't change unlock logic). It has no concept of float/BE memory
sizes or operand math modifiers (e.g. "&511" bitmasking a value in place),
and this script doesn't know what the (undocumented, rare) "Q"/"Z" flags do.
Any achievement that needs one of those is skipped rather than silently
mistranslated, and reported at the end so a human can decide whether to
extend the evaluator further or hand-author that one.

Usage:
    python tool/ra_patch_to_achievements.py <patch.json> <achievements.json> [--merge]

--merge: if achievements.json already exists, keep its entries (matched by
title) untouched - preserves hand-curated ids/descriptions and, more
importantly, ids already referenced in a player's saved unlock state -
and only appends newly-convertible achievements not already present.
Without --merge, the output is just every convertible achievement fresh
from the patch.
"""
import json
import re
import sys

SIZE_MAP = {
    "H": "byte",
    " ": "word",
    "W": "tribyte",
    "X": "dword",
    "L": "nibbleLow",
    "U": "nibbleHigh",
    "M": "bit0",
    "N": "bit1",
    "O": "bit2",
    "P": "bit3",
    "Q": "bit4",
    "R": "bit5",
    "S": "bit6",
    "T": "bit7",
}

OP_MAP = {
    "=": "equals",
    "!=": "notEquals",
    "<": "lessThan",
    "<=": "lessOrEqual",
    ">": "greaterThan",
    ">=": "greaterOrEqual",
}

# Flags that only annotate a condition without changing whether it's part of
# the achievement's AND set (Trigger and Measured are UI-only in the RA
# client; this app renders neither, so they're dropped rather than tracked).
COSMETIC_FLAGS = {"T", "M"}
CHAIN_FLAGS = {"N": "and", "O": "or"}
# These don't compare anything themselves - they contribute a pointer offset
# (AddAddress) or fold into a running accumulator (AddSource/SubSource) that
# the *next* condition in the group consumes. RA syntax reflects that: they're
# often written as a bare flag+address with no operator/value at all (e.g.
# "I:0xW33b1f0"), so the op/value/hits portion of CONDITION_RE is optional.
VALUE_ONLY_FLAGS = {"I": "isAddAddress", "A": "isAddSource", "B": "isSubSource"}
# Unlike VALUE_ONLY_FLAGS, these still compare like a normal condition (and
# still need op/value) - they just also fold their own hit tally into the
# next non-AddHits/SubHits condition's hit count instead of being one unit
# on their own.
HIT_ACCUMULATOR_FLAGS = {"C": "isAddHits", "D": "isSubHits"}

CONDITION_RE = re.compile(
    r"^(?:(?P<flag>[A-Za-z]):)?"
    r"(?P<lprefix>d)?0x(?P<lsize>[A-Z ]?)(?P<laddr>[0-9a-f]+)"
    r"(?:(?P<op>!=|<=|>=|=|<|>)"
    r"(?P<rprefix>d)?(?:0x(?P<rsize>[A-Z ]?)(?P<raddr>[0-9a-f]+)|(?P<rlit>\d+))"
    r"(?:\.(?P<hits>\d+)\.)?)?$"
)

# Splits a MemAddr string into [core, alt1, alt2, ...] on RA's top-level "S"
# alt-group separator - but not the "0xS" bit6 size code, or the "S" that
# glues two conditions together inside a single Display: string (not
# relevant here, MemAddr never has those). Lookbehind excludes "0xS".
ALT_GROUP_SPLIT_RE = re.compile(r"(?<!0x)S")


def convert_condition(raw_condition):
    """Returns (condition_dict, None) on success or (None, reason)."""
    m = CONDITION_RE.match(raw_condition)
    if not m:
        return None, f"unparseable condition: {raw_condition!r}"
    g = m.groupdict()

    flag = g["flag"]
    if (
        flag
        and flag not in ("R", "P")
        and flag not in CHAIN_FLAGS
        and flag not in COSMETIC_FLAGS
        and flag not in VALUE_ONLY_FLAGS
        and flag not in HIT_ACCUMULATOR_FLAGS
    ):
        return None, f"unsupported flag {flag!r}: {raw_condition!r}"

    size = SIZE_MAP.get(g["lsize"])
    if size is None:
        return None, f"unsupported memory size {g['lsize']!r}: {raw_condition!r}"

    condition = {"address": "0x" + g["laddr"], "size": size}
    if g["lprefix"]:
        condition["readPrevious"] = True

    if flag in VALUE_ONLY_FLAGS:
        # No comparison of its own - ignore any op/value present (some games
        # write filler like "A:0xH1234=0"; it's meaningless here either way).
        condition[VALUE_ONLY_FLAGS[flag]] = True
        return condition, None

    if g["op"] is None:
        return None, f"missing operator/value (and not AddAddress/AddSource/SubSource): {raw_condition!r}"
    condition["op"] = OP_MAP[g["op"]]

    if g["rlit"] is not None:
        condition["value"] = int(g["rlit"])
    else:
        rsize = SIZE_MAP.get(g["rsize"])
        if rsize is None:
            return None, f"unsupported memory size {g['rsize']!r}: {raw_condition!r}"
        if g["raddr"] == g["laddr"] and rsize == size and g["rprefix"]:
            # Same address/size, right side is the delta -> comparing this
            # condition's own reading against its previous-poll value.
            condition["compareTarget"] = "previousValue"
        else:
            # Different address (or same address compared against its own
            # current value, which is unusual but representable the same
            # way) -> read that address/size directly, current or previous
            # per its own delta prefix.
            condition["compareTarget"] = "otherAddress"
            condition["compareAddress"] = "0x" + g["raddr"]
            condition["compareSize"] = rsize
            if g["rprefix"]:
                condition["compareReadPrevious"] = True

    if flag == "R":
        condition["isResetIf"] = True
    elif flag == "P":
        condition["isPauseIf"] = True
    elif flag in CHAIN_FLAGS:
        condition["chain"] = CHAIN_FLAGS[flag]
    elif flag in HIT_ACCUMULATOR_FLAGS:
        condition[HIT_ACCUMULATOR_FLAGS[flag]] = True
    # COSMETIC_FLAGS (T, M) intentionally drop the flag entirely.

    # Presence of the ".N." suffix at all is what matters, not its value -
    # even an explicit ".1." means "sticky once true" (persistent hit count),
    # which is NOT the same as no suffix at all ("must hold this exact poll,
    # no memory" - see AchievementCondition.targetHits's doc for why this
    # distinction is load-bearing).
    if g["hits"]:
        condition["targetHits"] = int(g["hits"])

    return condition, None


def convert_condition_group(group_text):
    """Converts one '_'-joined run of conditions (the core group, or a single
    alt group) into a list of condition dicts, or (None, reason) on failure."""
    conditions = []
    for raw_condition in group_text.split("_"):
        condition, reason = convert_condition(raw_condition)
        if condition is None:
            return None, reason
        conditions.append(condition)
    return conditions, None


def convert_mem_addr(mem_addr):
    """Returns ((core_conditions, alt_groups), None) on success or
    (None, reason) if this achievement uses a RetroAchievements feature the
    evaluator can't represent."""
    groups = ALT_GROUP_SPLIT_RE.split(mem_addr)
    core, reason = convert_condition_group(groups[0])
    if core is None:
        return None, reason

    alt_groups = []
    for alt_text in groups[1:]:
        alt_conditions, reason = convert_condition_group(alt_text)
        if alt_conditions is None:
            return None, reason
        alt_groups.append(alt_conditions)

    return (core, alt_groups), None


def slugify(title):
    slug = re.sub(r"[^a-z0-9]+", "_", title.lower()).strip("_")
    return re.sub(r"_+", "_", slug)


def main():
    args = [a for a in sys.argv[1:] if a != "--merge"]
    merge = "--merge" in sys.argv
    if len(args) < 2:
        print(
            "Usage: python tool/ra_patch_to_achievements.py <patch.json> <achievements.json> [--merge]",
            file=sys.stderr,
        )
        sys.exit(1)

    patch_path, output_path = args[0], args[1]
    with open(patch_path, encoding="utf-8") as f:
        patch = json.load(f)

    existing_by_title = {}
    existing_list = []
    if merge:
        try:
            with open(output_path, encoding="utf-8") as f:
                existing_list = json.load(f)
            existing_by_title = {a["title"]: a for a in existing_list}
        except FileNotFoundError:
            pass

    used_ids = {a["id"] for a in existing_list}
    added = []
    refreshed_count = 0
    skipped = []
    duplicate_count = 0
    # Titles aren't unique in RA patch data (e.g. "Treasure I" repeats once
    # per stage with different addresses) - only skip a patch achievement if
    # it exactly matches an *already-curated* title, never dedupe against
    # other patch achievements sharing a title.
    curated_titles = set(existing_by_title)
    handled_curated_titles = set()
    # RA lists the same achievement again in "bonus" subsets that re-include
    # core achievements toward their own completion total - same MemAddr,
    # same real check, so keep only the first copy.
    seen_mem_addrs = set()

    for game_set in patch.get("Sets", []):
        for achievement in game_set.get("Achievements", []):
            title = achievement["Title"]
            is_curated = title in curated_titles

            mem_addr = achievement["MemAddr"]
            if not is_curated:
                if mem_addr in seen_mem_addrs:
                    duplicate_count += 1
                    continue
                seen_mem_addrs.add(mem_addr)

            result, reason = convert_mem_addr(mem_addr)
            if result is None:
                if is_curated:
                    # Shouldn't happen (it converted fine before) - keep the
                    # hand-curated entry rather than dropping it.
                    if title not in handled_curated_titles:
                        added.append(existing_by_title[title])
                        handled_curated_titles.add(title)
                else:
                    skipped.append((title, reason))
                continue
            conditions, alt_groups = result

            if is_curated:
                # Re-parsing catches parser fixes (e.g. targetHits' explicit-
                # vs-absent bug) that predate a title's curation - refresh
                # conditions/altGroups but keep the human-authored id/title/
                # description/points (id especially: it's what a player's
                # saved unlock state references).
                if title in handled_curated_titles:
                    continue
                handled_curated_titles.add(title)
                curated = existing_by_title[title]
                entry = dict(curated)
                entry["conditions"] = conditions
                if alt_groups:
                    entry["altGroups"] = alt_groups
                elif "altGroups" in entry:
                    del entry["altGroups"]
                if entry != curated:
                    refreshed_count += 1
                added.append(entry)
                continue

            slug = slugify(title)
            unique_slug = slug
            n = 2
            while unique_slug in used_ids:
                unique_slug = f"{slug}_{n}"
                n += 1
            used_ids.add(unique_slug)

            entry = {
                "id": unique_slug,
                "title": title,
                "description": achievement.get("Description", ""),
                "points": achievement.get("Points", 0),
                "conditions": conditions,
            }
            if alt_groups:
                entry["altGroups"] = alt_groups
            added.append(entry)

    # Any curated title not found at all in this patch (shouldn't normally
    # happen) is kept as-is rather than silently dropped.
    for title, curated in existing_by_title.items():
        if title not in handled_curated_titles:
            added.append(curated)

    with open(output_path, "w", encoding="utf-8") as f:
        json.dump(added, f, indent=2, ensure_ascii=False)
        f.write("\n")

    print(f"{len(added)} achievement(s) written to {output_path} "
          f"({len(added) - len(existing_list)} newly added, {len(existing_list) - refreshed_count} unchanged, "
          f"{refreshed_count} curated entries had their conditions refreshed)")
    print(f"{duplicate_count} duplicate(s) skipped (same MemAddr re-listed in another subset)")
    print(f"{len(skipped)} achievement(s) skipped (need evaluator features this app doesn't support yet):")
    reason_counts = {}
    for _, reason in skipped:
        key = reason.split(":")[0]
        reason_counts[key] = reason_counts.get(key, 0) + 1
    for key, count in sorted(reason_counts.items(), key=lambda kv: -kv[1]):
        print(f"  {count:>3}  {key}")


if __name__ == "__main__":
    main()
