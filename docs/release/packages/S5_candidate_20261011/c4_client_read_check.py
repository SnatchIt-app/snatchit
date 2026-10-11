#!/usr/bin/env python3
"""C4 static client-read check (FINAL_INTEGRATION_PLAN_20260925 §5.3 item 3).

"No client selects a column before it exists in production." Scans the app source
(app/, src/, packages/) for supabase-js calls and resolves every literal name against
a database whose schema equals production (the local pkg151_rehears clone, ledger 164):
  - .from('t')            -> table or view t exists in the active schema
  - .select('...')        -> every column / embedded relation in the select exists
  - filters (.eq/.neq/.in/.is/.gt/.gte/.lt/.lte/.like/.ilike/.order/.contains/...)
                          -> the filtered column exists
  - .insert/.update/.upsert({...}) object literals -> every key is a column
  - .rpc('f', {...})      -> a function f exists in the active schema whose argument
                             names include every key passed
  - .schema('s')          -> sets the active schema for the chain (default public)
Anything not literal (variables, spreads, template interpolation) is reported as
UNRESOLVED, never as a pass. Storage calls (`storage.from(bucket)`) are excluded.

Usage: c4_client_read_check.py <source-root> <psql-dbname> [--json OUT]
Exit 0 only when there are no MISSING findings.
"""
import json, os, re, subprocess, sys

FILTERS = {'eq', 'neq', 'in', 'is', 'gt', 'gte', 'lt', 'lte', 'like', 'ilike', 'order', 'contains',
           'containedBy', 'overlaps', 'textSearch', 'filter', 'match', 'not', 'rangeGt', 'rangeLt'}
WRITES = {'insert', 'update', 'upsert'}


def db_catalog(db):
    q = """
    select 'col', table_schema, table_name, column_name from information_schema.columns
     where table_schema in ('public','kernel','venue','catalog','venue_api','ops')
    union all
    select 'fn', n.nspname, p.proname, coalesce(array_to_string(p.proargnames, ','), '')
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname in ('public','kernel','venue','catalog','venue_api','ops')
    """
    out = subprocess.run(['psql', '-h', '127.0.0.1', '-U', 'postgres', '-d', db, '-X', '-At', '-F', '\t', '-c', q],
                         capture_output=True, text=True, check=True).stdout
    cols, fns = {}, {}
    for line in out.splitlines():
        kind, s, name, rest = line.split('\t')
        if kind == 'col':
            cols.setdefault((s, name), set()).add(rest)
        else:
            fns.setdefault((s, name), []).append(set(a for a in rest.split(',') if a))
    return cols, fns


def strip_comments(src):
    src = re.sub(r'/\*.*?\*/', lambda m: '\n' * m.group(0).count('\n'), src, flags=re.S)
    return re.sub(r'(^|[^:])//[^\n]*', r'\1', src)


def read_string(s, i):
    """s[i] is a quote; return (value, end_index, is_literal)."""
    q = s[i]; j = i + 1; buf = []
    while j < len(s):
        c = s[j]
        if c == '\\':
            buf.append(s[j:j + 2]); j += 2; continue
        if q == '`' and s.startswith('${', j):
            return None, j, False
        if c == q:
            return ''.join(buf), j + 1, True
        buf.append(c); j += 1
    return None, j, False


def chain_end(s, i):
    """Index just past the end of the expression statement starting at i."""
    depth = 0; j = i
    while j < len(s):
        c = s[j]
        if c in '\'"`':
            _, j, _ = read_string(s, j); continue
        if c in '([{': depth += 1
        elif c in ')]}':
            if depth == 0: return j
            depth -= 1
        elif c in ';,' and depth == 0: return j
        j += 1
    return j


def calls(chain):
    """Yield (method, argtext) for each .method( ... ) at chain depth 0."""
    for m in re.finditer(r'\.\s*([A-Za-z]+)\s*\(', chain):
        start = m.end(); depth = 1; j = start
        while j < len(chain) and depth:
            c = chain[j]
            if c in '\'"`':
                _, j, _ = read_string(chain, j); continue
            if c in '([{': depth += 1
            elif c in ')]}': depth -= 1
            j += 1
        yield m.group(1), chain[start:j - 1]


def first_string(arg):
    arg = arg.strip()
    if arg and arg[0] in '\'"`':
        v, _, lit = read_string(arg, 0)
        return v if lit else None
    return None


def object_keys(arg):
    arg = arg.strip()
    if not arg.startswith('{'):
        return None
    body = arg[1:arg.rfind('}')]
    keys, depth, cur = [], 0, ''
    for c in body + ',':
        if c in '([{': depth += 1
        elif c in ')]}': depth -= 1
        if c == ',' and depth == 0:
            part = cur.strip()
            if part.startswith('...'):
                return None
            if part:
                k = re.match(r"""^['"]?([A-Za-z_][A-Za-z0-9_]*)['"]?\s*(:|$)""", part)
                if not k:
                    return None
                keys.append(k.group(1))
            cur = ''
        else:
            cur += c
    return keys


def split_top(s):
    out, depth, cur = [], 0, ''
    for c in s:
        if c in '([{':
            depth += 1
        elif c in ')]}':
            depth -= 1
        if c == ',' and depth == 0:
            out.append(cur); cur = ''
        else:
            cur += c
    out.append(cur)
    return [x.strip() for x in out if x.strip()]


def check_select(sel, schema, table, cols, findings, where):
    for item in split_top(sel):
        if item == '*' or item.startswith('count'):
            continue
        m = re.match(r'^(?:([A-Za-z_][A-Za-z0-9_]*)\s*:\s*)?([A-Za-z_][A-Za-z0-9_]*)(?:!([A-Za-z_]+))?\s*\((.*)\)\s*$', item, re.S)
        if m:  # embedded resource: alias:relation!hint(cols)
            rel, inner = m.group(2), m.group(4)
            if (schema, rel) in cols:
                check_select(inner, schema, rel, cols, findings, where)
            else:
                findings.append(('UNRESOLVED', where, f'embedded relation {rel} (not a table/view name; FK-named?)'))
            continue
        name = re.split(r'::|->>|->', item.split(':')[-1].strip())[0].strip()
        if not re.match(r'^[A-Za-z_][A-Za-z0-9_]*$', name):
            findings.append(('UNRESOLVED', where, f'select item {item!r}')); continue
        if name not in cols.get((schema, table), set()):
            findings.append(('MISSING', where, f'column {schema}.{table}.{name} (select)'))


def scan(root, cols, fns):
    findings, counted = [], {'from': 0, 'rpc': 0}
    for dp, _, fs in os.walk(root):
        if 'node_modules' in dp or '__tests__' in dp:
            continue
        for f in fs:
            if not f.endswith(('.ts', '.tsx')) or '.test.' in f:
                continue
            path = os.path.join(dp, f); rel = os.path.relpath(path, root)
            src = strip_comments(open(path, encoding='utf-8').read())
            for m in re.finditer(r'(\.schema\(\s*[\'"]([a-z_]+)[\'"]\s*\)\s*)?\.(from|rpc)\s*\(', src):
                pre = src[max(0, m.start() - 12):m.start()]
                if m.group(3) == 'from' and re.search(r'storage\s*$', pre):
                    continue
                schema = m.group(2) or 'public'
                line = src.count('\n', 0, m.start()) + 1
                where = f'{rel}:{line}'
                # the call's own argument: scan from just inside '(' to its matching ')'
                j = m.end(); depth = 1
                while j < len(src) and depth:
                    c = src[j]
                    if c in '\'"`':
                        _, j, _ = read_string(src, j); continue
                    if c in '([{': depth += 1
                    elif c in ')]}': depth -= 1
                    j += 1
                arg0 = src[m.end():j - 1]
                rest = src[j:chain_end(src, j)]   # the rest of the chain after .from(...)/.rpc(...)
                name = first_string(arg0.split(',')[0]) if arg0.strip()[:1] in '\'"`' else None
                if m.group(3) == 'from':
                    if name is None:
                        if re.match(r'^\s*[A-Za-z_]', arg0) and not re.search(r'storage|Array|Buffer|utf8', pre + arg0):
                            findings.append(('UNRESOLVED', where, f'.from({arg0.strip()[:40]})'))
                        continue
                    counted['from'] += 1
                    if (schema, name) not in cols:
                        findings.append(('MISSING', where, f'table/view {schema}.{name}')); continue
                    for meth, arg in calls(rest):
                        if meth == 'select':
                            sel = first_string(arg)
                            if sel is None and arg.strip():
                                findings.append(('UNRESOLVED', where, 'non-literal select'))
                            elif sel:
                                check_select(sel, schema, name, cols, findings, where)
                        elif meth in FILTERS:
                            c = first_string(arg)
                            if c and meth not in ('or', 'filter', 'match', 'not'):
                                c0 = re.split(r'::|->>|->|\.', c)[0]
                                if c0 not in cols[(schema, name)]:
                                    findings.append(('MISSING', where, f'column {schema}.{name}.{c0} ({meth})'))
                        elif meth in WRITES:
                            ks = object_keys(arg)
                            if ks is None:
                                if arg.strip():
                                    findings.append(('UNRESOLVED', where, f'.{meth}(non-literal object)'))
                            else:
                                for k in ks:
                                    if k not in cols[(schema, name)]:
                                        findings.append(('MISSING', where, f'column {schema}.{name}.{k} ({meth})'))
                else:
                    if name is None:
                        findings.append(('UNRESOLVED', where, f'.rpc({arg0.strip()[:40]})')); continue
                    counted['rpc'] += 1
                    sigs = fns.get((schema, name))
                    if not sigs:
                        findings.append(('MISSING', where, f'function {schema}.{name}')); continue
                    parts = split_top(arg0)
                    keys = object_keys(parts[1]) if len(parts) > 1 else []
                    if keys is None:
                        findings.append(('UNRESOLVED', where, f'{schema}.{name} args not a literal object')); continue
                    p_keys = {k for k in keys}
                    if not any(p_keys <= s for s in sigs):
                        findings.append(('MISSING', where, f'function {schema}.{name} has no overload with args {sorted(p_keys)}'))
    return findings, counted


def main():
    root, db = sys.argv[1], sys.argv[2]
    cols, fns = db_catalog(db)
    findings, counted = scan(root, cols, fns)
    miss = [f for f in findings if f[0] == 'MISSING']
    unres = [f for f in findings if f[0] == 'UNRESOLVED']
    print(f'resolved: {counted["from"]} .from() chains, {counted["rpc"]} .rpc() calls; '
          f'MISSING {len(miss)}, UNRESOLVED {len(unres)}')
    for f in miss + unres:
        print(f'{f[0]:10s} {f[1]}  {f[2]}')
    if '--json' in sys.argv:
        json.dump({'counted': counted, 'findings': findings}, open(sys.argv[sys.argv.index('--json') + 1], 'w'), indent=1)
    sys.exit(1 if miss else 0)


if __name__ == '__main__':
    main()
