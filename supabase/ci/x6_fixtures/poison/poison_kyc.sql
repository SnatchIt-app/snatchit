-- POISON FIXTURE (T-CI-X6-03): deliberately selects a §2.3 never-exported field. Never applied.
select kyc_ref, phone_number from kernel.identity_ext;
