-- Remove the admin entry point. Recorded venue approvals and audits are retained.
drop function if exists ops.approve_venue(uuid,text,text);
