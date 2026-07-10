#!/usr/bin/env bash
# LLM round trip on the command line — the same path the demo takes:
#   Act 1 (LOCAL): /analyze + numbered masking; the mapping table stays on disk
#   Act 2 (SENT):  ONLY the masked text goes to the provider, through the
#                  local caddy proxy — the key is attached server-side from
#                  .env, this script never touches it
#   Act 3 (LOCAL): the response's placeholders are re-substituted locally
#
# Prerequisites: docker compose up (with a configured .env for act 2), jq.
set -euo pipefail

command -v jq >/dev/null 2>&1 || {
  echo "This script needs jq (macOS: brew install jq, Debian/Ubuntu: apt install jq)."
  exit 1
}

BASE_URL="${BASE_URL:-http://localhost:8080}"
LLM_MODEL="${LLM_MODEL:-gpt-4o-mini}"
MAPPING_FILE="mapping.txt"

# German sample text (Max-Mustermann-class insurance letter): policyholder
# name, labeled birth date, street + zip/city, phone, email, and a contract
# expiry date that must survive the masking.
TEXT="Versicherungsnehmer: Max Mustermann, Geburtsdatum: 15.08.1985, Musterweg 15, 53113 Bonn. Tel: 030 1234567, max@example.com. Ablauf der Vertragslaufzeit am 28.02.2036."

echo "=== Act 1 (LOCAL) — detect & mask ==="
SPANS=$(curl -s -X POST "$BASE_URL/analyze" -H 'Content-Type: application/json' \
  -d "$(jq -n --arg text "$TEXT" '{
    text: $text,
    language: "de",
    entities: ["PERSON","LOCATION","EMAIL_ADDRESS","PHONE_NUMBER","IBAN_CODE","DE_ADDRESS","DE_BIRTHDATE"],
    allow_list: ["Versicherungsschein-Nummer","Versicherungsnehmer"]
  }')")

# Numbered masking in jq: sort spans, skip overlapped ones (first span wins —
# the demo does full segment resolution; this keeps the script readable),
# then replace each span with [TYPE_N]. The same original string reuses its
# placeholder — without numbering, two [PERSON] placeholders would collide
# and re-substitution would be ambiguous.
MASKED_AND_MAP=$(jq -n --arg text "$TEXT" --argjson spans "$SPANS" '
  ($spans | sort_by(.start, -.score)) as $sorted
  | reduce $sorted[] as $s (
      {pos: 0, end: 0, out: "", counters: {}, seen: {}, map: []};
      if $s.start < .end then .
      else
        ($text[$s.start:$s.end]) as $orig
        | ($s.entity_type + ":" + $orig) as $k
        | (if .seen[$k] != null then .seen[$k]
           else "[" + $s.entity_type + "_" + (((.counters[$s.entity_type] // 0) + 1) | tostring) + "]"
           end) as $ph
        | {
            pos: $s.end,
            end: $s.end,
            out: (.out + $text[.pos:$s.start] + $ph),
            counters: (if .seen[$k] != null then .counters
                       else (.counters + {($s.entity_type): ((.counters[$s.entity_type] // 0) + 1)}) end),
            seen: (.seen + {($k): $ph}),
            map: (if .seen[$k] != null then .map else (.map + [{ph: $ph, orig: $orig}]) end)
          }
      end)
  | {masked: (.out + $text[.pos:]), map: .map}')

MASKED=$(jq -r '.masked' <<<"$MASKED_AND_MAP")

{
  echo "# this table never leaves the machine — pseudonymization lives and dies with it"
  jq -r '.map[] | .ph + "\t" + .orig' <<<"$MASKED_AND_MAP"
} > "$MAPPING_FILE"

echo "mapping table written to $MAPPING_FILE (stays local):"
cat "$MAPPING_FILE"
echo

echo "=== Act 2 (SENT) — this is ALL the provider sees ==="
echo "$MASKED"
echo
RESPONSE=$(curl -s -X POST "$BASE_URL/llm/v1/chat/completions" \
  -H 'Content-Type: application/json' \
  -d "$(jq -n \
        --arg model "$LLM_MODEL" \
        --arg prompt "Summarize this document in two sentences. Keep the placeholders exactly as they are." \
        --arg text "$MASKED" \
        '{model: $model, messages: [{role: "user", content: ($prompt + "\n\n" + $text)}]}')")

CONTENT=$(jq -r '.choices[0].message.content // empty' <<<"$RESPONSE" 2>/dev/null || true)
if [ -z "$CONTENT" ]; then
  echo "LLM call failed — is the .env configured?"
  echo "  (cp .env.example .env, set your key, restart: docker compose up)"
  echo "raw response (truncated): $(head -c 300 <<<"$RESPONSE")"
  exit 1
fi

echo "=== Act 3 (LOCAL) — response & local re-substitution ==="
echo "response (masked, as received from the provider):"
echo "$CONTENT"
echo
FINAL="$CONTENT"
while IFS=$'\t' read -r ph orig; do
  [ -z "$ph" ] && continue
  case "$ph" in "#"*) continue ;; esac
  FINAL=${FINAL//"$ph"/"$orig"}
done < "$MAPPING_FILE"
echo "response (re-identified locally — the names never left your machine):"
echo "$FINAL"
