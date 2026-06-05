-- 027: drop the 2-param overload of buyer_dispute_transfer.
-- Migration 011 added a 5-param version with all params after p_transfer_id
-- defaulted; client calls with only p_transfer_id were resolving ambiguously
-- between the two. Drop the older 2-param signature; clients land on the
-- 5-param function unambiguously.

BEGIN;
DROP FUNCTION IF EXISTS public.buyer_dispute_transfer(uuid, uuid);
COMMIT;
