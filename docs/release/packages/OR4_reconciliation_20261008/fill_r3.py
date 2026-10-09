#!/usr/bin/env python3
"""Fill R3_record_refund.sql.tmpl. Usage: fill_r3.py OUT KEY=VALUE ...

Every {{KEY}} in the template must be supplied, and every supplied key must occur in the template. Values are written
verbatim inside SQL literals, so a value containing a quote or a brace is refused. Prints the output's sha256.
"""
import hashlib
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
TMPL = os.path.join(HERE, "R3_record_refund.sql.tmpl")
SAFE = re.compile(r"^[A-Za-z0-9_:+., #/()-]*$")


def main(argv):
    if len(argv) < 2:
        sys.exit("usage: fill_r3.py OUT KEY=VALUE ...")
    out, pairs = argv[0], argv[1:]
    text = open(TMPL).read()
    wanted = set(re.findall(r"\{\{([A-Z_]+)\}\}", text))
    vals = {}
    for p in pairs:
        k, sep, v = p.partition("=")
        if not sep or k not in wanted or k in vals:
            sys.exit(f"bad or duplicate key: {k!r}")
        if not SAFE.match(v):
            sys.exit(f"unsafe characters in {k}")
        vals[k] = v
    missing = wanted - set(vals)
    if missing:
        sys.exit(f"missing keys: {sorted(missing)}")
    for k, v in vals.items():
        text = text.replace("{{" + k + "}}", v)
    if "{{" in text or "}}" in text:
        sys.exit("unfilled marker remains")
    with open(out, "w") as f:
        f.write(text)
    print(hashlib.sha256(text.encode()).hexdigest(), out)


if __name__ == "__main__":
    main(sys.argv[1:])
