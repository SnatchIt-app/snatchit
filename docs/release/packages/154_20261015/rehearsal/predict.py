#!/usr/bin/env python3
"""predict.py — derive the expected post-states of 154, 155, 156, the data step, and 154's rollback
from a measured pre154 state (A, 2026-10-15). Run BEFORE any apply; the outputs are the predictions.

usage: predict.py <pre154.txt> <lists.json> <out_dir> [<n_hidden>]
  lists.json : the environment's predicted list hashes, computed by ONE read-only query on that
               database (the existing rows plus the literal rows each migration adds; see README §Expected):
               {"grants_154": "...", "grants_156": "...", "trg_154": "...", "trg_155": "...", "trg_156": "...",
                "cols_156": "..."}
  n_hidden   : rows the data step hides (113 in production and in the rehearsal fixture).

Every other new value is a constant of the frozen files: ledger rows are md5/length of the file bytes
(pkg.py stores the raw file as statements[1]); function/policy/check hashes were read from a fresh local
replay of the gate tip + the frozen 154-156 (Homebrew PG 17, a154f_green after the review fixes), the same
major version as production (17.6). Keys not named here are predicted UNCHANGED — that includes every fixed
money/listing hash. The ownership keys are derived from the measured pre state: the three readers are predicted
to be owned by the owner of listings (the apply transport runs as that role: production MCP/Management API
current_user = postgres, which owns listings; 152's functions are owned by postgres) and to bypass RLS exactly
as that role does (owner_role); listing_visibility is predicted owned by it, RLS on, no FORCE.
Review fix (2026-10-15): 154 adds is_public(listings) (anon-execute) and the widened invariant; 155 adds
set_listing_ends_at_from_duration() + trg_listing_ends_at_from_duration; new keys hidden_open_or_held, rls_*,
owner_role, fnown_*.
"""
import hashlib, json, sys
from pathlib import Path

HERE = Path(__file__).resolve().parent.parent
FILES = {"154": ("20261015000000", "listing_public_visibility"),
         "155": ("20261015000100", "listing_duration_72h"),
         "156": ("20261015000200", "listing_proof_owner_waiver")}

FN = {  # md5(pg_get_functiondef) | md5(prosrc) — a154f_green (review fixes), search_path public, extensions
    "fn_public.get_profile_trust_stats(p_user_id uuid)":
        "def:2d62da92f7d33d86e0d15d976f69e960|src:697c82a24b47b7e5920a64aa7e80672a|secdef=true|cfg=search_path=public",
    "fn_public.listing_is_public(p_listing_id uuid)":
        "def:9287ac68d8d8a7824bcee41bbf664eba|src:d3dc687af51c3aca9ea4f1ca92292265|secdef=true|cfg=search_path=\"\"",
    "fn_public.listing_private_party(p_listing_id uuid)":
        "def:f5769c49f235935553d95d9763f64c21|src:51c885097315ccafd04e26b716c6f695|secdef=true|cfg=search_path=\"\"",
    "fn_public.guard_hidden_listing_not_live()":
        "def:1869c7f31c2fdf950cb4ec2e3686c31f|src:b193b43541f1bd27d5aa2deac3437332|secdef=true|cfg=search_path=\"\"",
    "fn_public.is_public(listings)":
        "def:9b816a1a5f8e07311ca5559d28aa14b5|src:b891d14415f717b794a56fc0588a3363|secdef=false|cfg=search_path=\"\"",
    "fn_public.set_listing_ends_at_from_duration()":
        "def:1ee19ef6347efaeaeb2485424df1087f|src:e62e82d36cb96db98c85540c8dfe0193|secdef=false|cfg=search_path=\"\"",
    "fn_public.guard_listing_proof_waiver()":
        "def:d78a70dbe8756ac8223d3484e62d0cc5|src:6c52273216086bb7388678703dc07430|secdef=true|cfg=search_path=\"\"",
    "fn_public.current_user_is_admin()":
        "def:fd284d77070f1a2c1054b4065e865da9|src:028f6b00d6d0bb0fd151485d67343647|secdef=true|cfg=search_path=\"\"",
}
POL_NEW = {
    "pol_listings.listings_select_visible": "SELECT|{anon,authenticated}|cba0ffbb244fcdb5801a4114a8ba4a57|d41d8cd98f00b204e9800998ecf8427e",
    "pol_bids.bids_select_visible": "SELECT|{anon,authenticated}|bf373b0b04578b109b60045d048d7f7c|d41d8cd98f00b204e9800998ecf8427e",
}
POL_GONE = ("pol_listings.listings_select_all", "pol_bids.bids_select_all")
T154 = ["listings.trg_hidden_listing_not_live:O:19:guard_hidden_listing_not_live()",
        "listing_visibility.trg_listing_visibility_not_live:O:7:guard_hidden_listing_not_live()"]
T155 = T154 + ["listings.trg_listing_ends_at_from_duration:O:23:set_listing_ends_at_from_duration()"]
T156 = T155 + ["listings.trg_guard_listing_proof_waiver:O:23:guard_listing_proof_waiver()"]
TRG_154, TRG_155, TRG_156 = (",".join(sorted(t)) for t in (T154, T155, T156))   # str sort = COLLATE "C" (ASCII)
READERS = ("public.listing_is_public(uuid)", "public.listing_private_party(uuid)", "public.is_public(public.listings)")
LV_TABLE = "true|policies:0|grants:service_role:DELETE,service_role:INSERT,service_role:SELECT"
WAIVER_CHECKS = ("listings_proof_waiver_all_or_none:5dfdcb9541b9c9e54e5b029a303911ad,"
                 "listings_proof_waiver_reason_check:abaad037782bfa31b92d52269587f106")
DURATION_72 = "CHECK ((duration_hours = ANY (ARRAY[1, 3, 6, 12, 24, 48, 72])))"


def load(p):
    return dict(l.split("=", 1) for l in Path(p).read_text(encoding="utf-8").split("\n") if l and not l.startswith("#"))


def ledger(st, n):
    v, name = FILES[n]
    body = (HERE / f"frozen/migrations/{v}_{name}.sql").read_bytes()
    st["ledger_count"] = str(int(st["ledger_count"]) + 1)
    st["ledger_max"] = v
    st[f"ledger_{n}"] = f"{name}|claude-a/owner-authorised-{n}|1|{hashlib.md5(body).hexdigest()}|{len(body)}"


def census(st, t=0, f=0, p=0, g=0):
    a = [int(x) for x in st["census"].split("|")]
    st["census"] = "|".join(str(x) for x in (a[0] + t, a[1] + f, a[2] + p, a[3] + g))


def dump(st, path, header):
    Path(path).write_text("\n".join([f"# {h}" for h in header] + [f"{k}={st[k]}" for k in sorted(st)]) + "\n", encoding="utf-8")


def main(pre_path, lists_path, out, n_hidden=113):
    L = json.loads(Path(lists_path).read_text())
    pre = load(pre_path)
    out = Path(out)
    # 154
    s = dict(pre)
    ledger(s, "154"); census(s, t=1, f=4, g=2)
    for k in ("fn_public.get_profile_trust_stats(p_user_id uuid)", "fn_public.listing_is_public(p_listing_id uuid)",
              "fn_public.listing_private_party(p_listing_id uuid)", "fn_public.guard_hidden_listing_not_live()",
              "fn_public.is_public(listings)"):
        s[k] = FN[k]
    s["exec_public.listing_is_public(uuid)"] = "anon:true,authenticated:true,service_role:true"
    s["exec_public.listing_private_party(uuid)"] = "anon:true,authenticated:true,service_role:true"
    s["exec_public.is_public(public.listings)"] = "anon:true,authenticated:true,service_role:true"
    s["exec_public.guard_hidden_listing_not_live()"] = "anon:false,authenticated:false,service_role:true"
    owner, sup, byp = (x.split("=")[-1] for x in pre["owner_role"].split("|"))
    lv_rls = f"{owner}|rls=true|force=false"
    s["rls_listing_visibility"] = lv_rls; s["hidden_open_or_held"] = "0"
    for r in READERS:
        s[f"fnown_{r}"] = f"{owner}|owner_of_listings=true|bypasses_rls={'true' if 'true' in (sup, byp) else 'false'}"
    for k in POL_GONE: s.pop(k)
    s.update(POL_NEW)
    s["triggers_listings_bids_lv"] = L["trg_154"]; s["triggers_154_156"] = TRG_154
    s["lv_table"] = LV_TABLE; s["lv_rows"] = "0"
    s["grants_anon_authenticated"] = L["grants_154"]
    post154 = dict(s)
    # 155
    ledger(s, "155"); census(s, f=1, g=1); s["duration_check"] = DURATION_72
    s["fn_public.set_listing_ends_at_from_duration()"] = FN["fn_public.set_listing_ends_at_from_duration()"]
    s["exec_public.set_listing_ends_at_from_duration()"] = "anon:false,authenticated:false,service_role:true"
    s["triggers_listings_bids_lv"] = L["trg_155"]; s["triggers_154_156"] = TRG_155
    post155 = dict(s)
    # 156
    ledger(s, "156"); census(s, f=2, g=1)
    s["fn_public.guard_listing_proof_waiver()"] = FN["fn_public.guard_listing_proof_waiver()"]
    s["fn_public.current_user_is_admin()"] = FN["fn_public.current_user_is_admin()"]
    s["exec_public.guard_listing_proof_waiver()"] = "anon:false,authenticated:false,service_role:true"
    s["exec_public.current_user_is_admin()"] = "anon:false,authenticated:true,service_role:true"
    s["triggers_listings_bids_lv"] = L["trg_156"]; s["triggers_154_156"] = TRG_156
    s["waiver_checks"] = WAIVER_CHECKS; s["listings_columns"] = L["cols_156"]
    s["grants_anon_authenticated"] = L["grants_156"]
    post156 = dict(s)
    # data step
    h = dict(post156)
    h["lv_rows"] = str(n_hidden)
    for k in ("anon_listings", "anon_bids", "nonparty_listings", "nonparty_bids"):
        h[k] = "0"
    # 154's rollback (from post154): everything back to pre154 except the KEPT table
    rb = dict(pre)
    census(rb, t=1); rb["lv_table"] = LV_TABLE; rb["lv_rows"] = "0"
    rb["rls_listing_visibility"] = lv_rls; rb["hidden_open_or_held"] = "0"
    src = f"derived by rehearsal/predict.py from {Path(pre_path).name} + {Path(lists_path).name}"
    dump(post154, out / "post154.txt", [f"PREDICTED post-154 state: {src}"])
    dump(post155, out / "post155.txt", [f"PREDICTED post-155 state: {src}"])
    dump(post156, out / "post156.txt", [f"PREDICTED post-156 state: {src}"])
    dump(h, out / "post_hide.txt", [f"PREDICTED state after the data step (hide {n_hidden}): {src}"])
    dump(rb, out / "rb154.txt", [f"PREDICTED state after 154's rollback (listing_visibility kept; data keys are ignored by pkg.py): {src}"])
    print(f"[predict] wrote post154/post155/post156/post_hide/rb154 under {out}")


if __name__ == "__main__":
    a = sys.argv[1:]
    if len(a) < 3: sys.exit(__doc__)
    main(a[0], a[1], a[2], int(a[3]) if len(a) > 3 else 113)
