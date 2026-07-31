#!/usr/bin/env bash
# One-shot production Stripe health check (2026-07-30 incident).
# Reports key shape, Stripe auth result, live webhook config, and Connect
# account modes. Never prints secret material.
set -euo pipefail
ANON="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImhxeWN3bnRwZm96dG9pbmVtcW5zIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzEzNzkyMDgsImV4cCI6MjA4Njk1NTIwOH0.rIhpma8iyXorXRxWUVMqpT2Csimdj2hedtPzuzV6C_E"
curl -s -X POST "https://hqycwntpfoztoinemqns.supabase.co/functions/v1/diag-stripe-env" \
  -H "Authorization: Bearer $ANON" -H "Content-Type: application/json" -d '{}'
echo
