# Pending migrations — NOT in the auto-apply path

Files here are written and reviewed but deliberately **not** applied, and are
kept out of `supabase/migrations/` so that `supabase migration up` or a CI
replay cannot apply them by accident.

## 043_profiles_select_column_restriction.sql — REMOVED (superseded)

The draft that lived here was never applied and its intent — restricting
base-table SELECT on `public.profiles` to a public-safe column set — was
delivered by applied migrations **052**, **062** and **068**. The file is
archived for the historical record at
`docs/archive/superseded-043_profiles_select_column_restriction.sql`.
Do not move it back into any migration path.
