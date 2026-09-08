# POISON FIXTURE (T-CI-X6-03) — a 22-column catalogue that must FAIL the =21 equality

### 2.2 The catalogue

| # | Field | Class | Grain | Source | Authorization |
|---|---|---|---|---|---|
| 1 | `customer_ref` | IDENT | holder | x | x |
| 2 | `display_name` | IDENT | holder | x | x |
| 3 | `is_purchaser` | IDENT | holder | x | x |
| 4 | `tickets_held` | IDENT | holder | x | x |
| 5 | `ticket_types` | OPS | holder | x | x |
| 6 | `source` | OPS | holder | x | x |
| 7 | `acquired_via` | OPS | holder | x | x |
| 8 | `checked_in` | OPS | holder | x | x |
| 9 | `admitted_at` | OPS | holder | x | x |
| 10 | `promoter_name` | OPS | holder | x | x |
| 11 | `promoter_code` | OPS | holder | x | x |
| 12 | `email` | CONTACT | holder | x | x |
| 13 | `first_seen_at` | IDENT | org CRM | x | x |
| 14 | `events_attended_count` | OPS | org CRM | x | x |
| 15 | `sessions_held_count` | OPS | org CRM | x | x |
| 16 | `order_ref` | MONEY | purchaser | x | x |
| 17 | `order_status` | MONEY | purchaser | x | x |
| 18 | `order_total` | MONEY | purchaser | x | x |
| 19 | `unit_price` | MONEY | purchaser | x | x |
| 20 | `refund_state` | MONEY | purchaser | x | x |
| 21 | `tickets_purchased` | MONEY | purchaser | x | x |
| 22 | `extra_column` | MONEY | purchaser | x | x |

### 2.3 The never-exported list
