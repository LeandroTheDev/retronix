#!/usr/bin/env python3
"""
Convert RetroAchievements API JSON to retro_os game_achievements.json format.

Usage:
    python3 convert_achievements.py <input.json> <output_dir>

Achievements are SKIPPED (not partially converted) when they contain unsupported
condition types, to avoid false positives from incomplete logic:
  - Float reads: fF, fM, fN, fO, ...
  - Division operator: \/
  - Modulo operator: %
  - Multiplication modifier: *
  - K: (Remember) and {recall} — newer RA features not in the retro_os spec
  - Titles containing [VOID] or DEMOTED

Supported but treated as normal (no special JSON field):
  - M: (Measured) — translated as a regular condition with targetHits
  - Q: (Measured%) — same treatment as M:
"""

import re
import json
import sys
import os

# ── size prefix → retro_os size name ────────────────────────────────────────
SIZE_MAP = {
    '0xH': 'byte',
    '0x ': 'word',       # 16-bit
    '0xW': 'word',       # 24-bit (README maps both to "word")
    '0xX': 'dword',
    '0xM': 'bit0',
    '0xN': 'bit1',
    '0xO': 'bit2',
    '0xP': 'bit3',
    '0xQ': 'bit4',
    '0xR': 'bit5',
    '0xS': 'bit6',
    '0xT': 'bit7',
    '0xU': 'nibbleLow',
    '0xV': 'nibbleHigh',
    '0xK': 'bcd',
}

OP_MAP = {
    '=':  'equals',
    '!=': 'notEquals',
    '>':  'greaterThan',
    '<':  'lessThan',
    '>=': 'greaterOrEqual',
    '<=': 'lessOrEqual',
}

# Prefixes that produce boolean flags on the condition object.
# Tuple value → sets cond['chain']. None → no field (M:, Q: treated as normal).
# address-only prefixes (A:, B:, I:) — no comparison required.
PREFIX_FLAGS = {
    'R:': 'isResetIf',
    'P:': 'isPauseIf',
    'T:': 'isTrigger',
    'Z:': 'isResetNextIf',
    'A:': 'isAddSource',
    'B:': 'isSubSource',
    'I:': 'isAddAddress',
    'C:': 'isAddHits',
    'D:': 'isSubHits',
    'N:': ('chain', 'and'),
    'O:': ('chain', 'or'),
    'M:': None,
    'Q:': None,
}

# These flags mean the condition carries only an address, no comparison.
ADDR_ONLY_FLAGS = {'isAddAddress', 'isAddSource', 'isSubSource'}


def split_groups(memaddr):
    """Split MemAddr into [core, alt1, alt2, …] on the S group separator.

    The group separator S is a bare S NOT preceded by 'x' (unlike '0xS',
    which is the bit6 size prefix). Example split points: '=5S0x', 'eS0x'.
    """
    return re.split(r'(?<!x)S', memaddr)


def parse_operand(token):
    """Parse a left- or right-hand operand token.

    Returns (is_delta, size_key, hex_addr) for an address operand, or
    (None, None, int_value) for a literal integer, or (None, None, None)
    if the token is unsupported (float, etc.).
    """
    if token.startswith('f'):
        return None, None, None          # float — unsupported
    is_delta = token.startswith('d')
    if is_delta:
        token = token[1:]
    for k in sorted(SIZE_MAP, key=len, reverse=True):
        if token.startswith(k):
            return is_delta, k, token[len(k):]
    try:
        return None, None, int(token)
    except ValueError:
        return None, None, None


def parse_condition(raw):
    """Parse a single raw condition token into a dict.

    Returns a dict with a '_unsupported' key set to True when the condition
    uses a feature not supported by retro_os (caller must check and drop).
    Returns a dict with '_trivial' key for always-true constants like '1=1'.
    """
    cond = {}

    # Strip condition-type prefixes (may repeat for chains like O:N:...)
    while True:
        matched = False
        for pf, pv in PREFIX_FLAGS.items():
            if raw.startswith(pf):
                raw = raw[len(pf):]
                if isinstance(pv, tuple):
                    cond['chain'] = pv[1]
                elif pv:
                    cond[pv] = True
                # M: and Q: → no field added
                matched = True
                break
        if not matched:
            break

    # Hit count suffix  .N.
    hit_m = re.search(r'\.(\d+)\.$', raw)
    if hit_m:
        cond['targetHits'] = int(hit_m.group(1))
        raw = raw[:hit_m.start()]

    # Unsupported operators / newer RA tokens
    if (raw.startswith('f')
            or '\\/' in raw
            or '%' in raw
            or '*' in raw
            or '{recall}' in raw
            or raw.startswith('K:')):
        cond['_unsupported'] = True
        return cond

    # Address-only conditions (I:, A:, B:) — no comparison op needed
    if any(f in cond for f in ADDR_ONLY_FLAGS):
        is_delta, size_key, addr = parse_operand(raw)
        if size_key:
            cond['address'] = '0x' + addr
            cond['size'] = SIZE_MAP[size_key]
            if is_delta:
                cond['readPrevious'] = True
        else:
            cond['_unsupported'] = True
        return cond

    # Normal comparison condition
    op_match = re.search(r'(!=|>=|<=|>|<|=)', raw)
    if not op_match:
        cond['_unsupported'] = True
        return cond

    op_str  = op_match.group(1)
    lhs     = raw[:op_match.start()]
    rhs     = raw[op_match.end():]
    cond['op'] = OP_MAP[op_str]

    # Parse left-hand side
    is_delta_l, size_key_l, addr_l = parse_operand(lhs)
    if size_key_l is None:
        # Literal on LHS (e.g. "1=1") → trivial always-true condition
        cond['_trivial'] = True
        return cond

    cond['address'] = '0x' + addr_l
    cond['size']    = SIZE_MAP[size_key_l]
    if is_delta_l:
        cond['readPrevious'] = True

    # Parse right-hand side
    is_delta_r, size_key_r, addr_r = parse_operand(rhs)

    if size_key_r is None:
        # Literal value on RHS
        if addr_r is not None:
            cond['value'] = addr_r
        else:
            cond['_unsupported'] = True
        return cond

    # Address on RHS
    rhs_addr = '0x' + addr_r
    same_addr = (rhs_addr == cond['address']
                 and SIZE_MAP[size_key_r] == cond['size'])

    if is_delta_l:
        # d0xH addr OP 0xH addr  →  flip and use compareTarget: previousValue
        if same_addr:
            flip = {'greaterThan': 'lessThan', 'lessThan': 'greaterThan',
                    'greaterOrEqual': 'lessOrEqual', 'lessOrEqual': 'greaterOrEqual',
                    'equals': 'equals', 'notEquals': 'notEquals'}
            cond['op'] = flip[cond['op']]
            del cond['readPrevious']
            cond['compareTarget'] = 'previousValue'
        else:
            cond['compareTarget'] = 'otherAddress'
            cond['compareAddress'] = rhs_addr
            cond['compareSize']    = SIZE_MAP[size_key_r]
    else:
        if is_delta_r and same_addr:
            cond['compareTarget'] = 'previousValue'
        elif is_delta_r:
            cond['compareTarget']      = 'otherAddress'
            cond['compareAddress']     = rhs_addr
            cond['compareSize']        = SIZE_MAP[size_key_r]
            cond['compareReadPrevious'] = True
        else:
            cond['compareTarget'] = 'otherAddress'
            cond['compareAddress'] = rhs_addr
            cond['compareSize']    = SIZE_MAP[size_key_r]

    return cond


def convert_group(group_str):
    return [parse_condition(t.strip())
            for t in group_str.split('_') if t.strip()]


def has_unsupported(conds):
    return any(c.get('_unsupported') for c in conds)


def clean_conds(conds):
    return [{k: v for k, v in c.items()
             if k not in ('_trivial', '_unsupported')}
            for c in conds
            if not c.get('_trivial') and not c.get('_unsupported')]


def to_snake(title):
    s = re.sub(r'[^a-zA-Z0-9\s]', '', title).lower().strip()
    return re.sub(r'\s+', '_', s)


def convert(input_path, output_dir):
    with open(input_path, encoding='utf-8') as f:
        content = f.read()

    # Extract achievements via regex (tolerates corrupted/streaming JSON)
    pattern = re.compile(
        r'\{"ID":(\d+),"MemAddr":"((?:[^"\\]|\\.)*)","Title":"((?:[^"\\]|\\.)*)"'
        r',"Description":"((?:[^"\\]|\\.)*)","Points":(\d+)',
        re.DOTALL,
    )

    output  = []
    skipped = []

    for aid, memaddr, title, desc, pts in pattern.findall(content):
        # Skip voided / demoted achievements
        if '[VOID]' in title or 'DEMOTED' in title:
            skipped.append(f'[{aid}] VOID: {title}')
            continue

        groups        = split_groups(memaddr)
        core_raw      = convert_group(groups[0])
        alt_groups_raw = [convert_group(g) for g in groups[1:]]

        # Skip entire achievement if any group has unsupported conditions
        if any(has_unsupported(g) for g in [core_raw] + alt_groups_raw):
            skipped.append(f'[{aid}] UNSUP: {title}')
            continue

        core_conds = clean_conds(core_raw)
        alt_groups = [clean_conds(g) for g in alt_groups_raw]
        alt_groups = [g for g in alt_groups if g]

        # Fallback if core is empty after cleaning (e.g. only trivial 1=1)
        if not core_conds:
            core_conds = [{'address': '0x000000', 'size': 'byte',
                           'op': 'equals', 'value': 0}]

        ach = {
            'id':          to_snake(title),
            'title':       title,
            'description': desc,
            'points':      int(pts),
            'conditions':  core_conds,
        }
        if alt_groups:
            ach['altGroups'] = alt_groups

        output.append(ach)

    os.makedirs(output_dir, exist_ok=True)
    out_path = os.path.join(output_dir, 'game_achievements.json')
    with open(out_path, 'w', encoding='utf-8') as f:
        json.dump(output, f, indent=2, ensure_ascii=False)
        f.write('\n')

    print(f'Written {len(output)} achievements → {out_path}')
    if skipped:
        print(f'Skipped {len(skipped)}:')
        for s in skipped:
            print(f'  {s}')


if __name__ == '__main__':
    if len(sys.argv) != 3:
        print(__doc__)
        sys.exit(1)
    convert(sys.argv[1], sys.argv[2])
