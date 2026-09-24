#!/bin/zsh
# secret_digest_compare.zsh — compare a secret with a Supabase secret "Digest SHA256", without exposing it.
#
#   zsh scripts/owner/secret_digest_compare.zsh
#
# You type/paste two things when asked:
#   1. the digest shown by Supabase (64 hex characters; not secret, shown as you paste it)
#   2. the secret itself — read with echo OFF
# Where the secret goes: into one unexported shell variable, then through a pipe into /usr/bin/shasum.
#   - never on a command line (so not in shell history and not in `ps` process arguments):
#     `print` is a zsh builtin, and shasum/pbcopy receive no argument containing it;
#   - never written to a file, never printed, never exported to a child's environment;
#   - xtrace/verbose are forced off, so it cannot leak into a trace log.
# At the end the variable is unset and the clipboard is cleared (Return), unless you type k to keep it.
# Clipboard-history apps (Raycast, Alfred, Paste, …) keep their own copy: clear it there too.
emulate -L zsh
setopt no_xtrace no_verbose no_all_export
[[ -t 0 && -t 1 ]] || { print -u2 "Run this in an interactive terminal."; exit 2; }

read -r "digest?1/2  Supabase Digest SHA256 (paste; visible): "
digest=${${digest//[[:space:]]/}:l}
if (( ${#digest} != 64 )) || [[ $digest == *[^0-9a-f]* ]]; then
  print -u2 "That is not a 64-character hex digest. Nothing was compared."; exit 2
fi

typeset secret=""
read -rs "secret?2/2  Paste the secret (hidden), then Return: "; print
secret=${secret//[[:space:]]/}      # keys and signing secrets contain no whitespace
if [[ -z $secret ]]; then print -u2 "Nothing was pasted. Nothing was compared."; exit 2; fi

case $secret in
  sk_live_*) kind="Stripe secret key, LIVE" ;;
  rk_live_*) kind="Stripe restricted key, LIVE" ;;
  sk_test_*|rk_test_*) kind="Stripe key, TEST mode" ;;
  whsec_*)   kind="Stripe webhook signing secret" ;;
  https://*) kind="URL (the control row)" ;;
  *)         kind="not a recognised Stripe prefix" ;;
esac
len=${#secret}
exact=$(print -rn -- "$secret" | /usr/bin/shasum -a 256); exact=${exact%% *}
withnl=$(print -r -- "$secret" | /usr/bin/shasum -a 256); withnl=${withnl%% *}
secret=""; unset secret

print "Pasted value: $kind, $len characters."
if [[ $exact == $digest ]]; then
  print "RESULT: MATCH. Supabase stores exactly the value you pasted."
elif [[ $withnl == $digest ]]; then
  print "RESULT: MATCH WITH A TRAILING NEWLINE. Same value; the stored copy ends in a newline."
else
  print "RESULT: NO MATCH. See the checklist (G4) for what this can and cannot mean."
fi
unset exact withnl digest

read -r "keep?Press Return to clear the clipboard (or type k, then Return, to keep it): "
if [[ $keep != k ]]; then print -n "" | /usr/bin/pbcopy && print "Clipboard cleared."; else print "Clipboard kept."; fi
