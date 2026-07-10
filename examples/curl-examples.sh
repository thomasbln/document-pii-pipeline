#!/usr/bin/env bash
# Smoke tests for the local analyzer, sent through the same-origin proxy the
# demo uses. Start the stack first:
#
#     docker compose up --build
#
# The first boot takes ~90 s (the NLP models load eagerly at startup) —
# until then /health answers 502.
#
# Tip: append `| jq` to any analyze call for readable output (optional).

set -euo pipefail

BASE_URL="${BASE_URL:-http://localhost:8080}"

echo "=== 1. Health check ==="
# Returns 200 once the models are loaded.
curl -s "$BASE_URL/health"
echo; echo

echo "=== 2. Minimal German analyze ==="
# German text: "Max Mustermann lives in Berlin."
# Expected: one PERSON span (Max Mustermann), one LOCATION span (Berlin).
curl -s -X POST "$BASE_URL/analyze" \
  -H 'Content-Type: application/json' \
  -d '{
    "text": "Max Mustermann wohnt in Berlin.",
    "language": "de",
    "entities": ["PERSON", "LOCATION"]
  }'
echo; echo

echo "=== 3. Full German smoke probe — WITHOUT allow_list ==="
# German insurance-letter snippet. It contains: a policyholder name
# (Max Mustermann), a labeled birth date, street + zip/city, the policy
# number label "Versicherungsschein-Nummer" ("insurance policy number"),
# phone, email, a test IBAN, and a contract expiry date.
#
# EXPECTED FALSE POSITIVE: the label "Versicherungsschein-Nummer" comes back
# as PERSON with score 0.85 — the exact same flat score a real name gets.
# This is the documented "scores are not confidence" case (README, honest
# limitations). Example 4 shows how the allow_list suppresses it.
curl -s -X POST "$BASE_URL/analyze" \
  -H 'Content-Type: application/json' \
  -d '{
    "text": "Versicherungsnehmer: Max Mustermann, Geburtsdatum: 15.08.1985, Musterweg 15, 53113 Bonn. Versicherungsschein-Nummer: L-123456. Tel: 030 1234567, max@example.com, IBAN DE89370400440532013000. Ablauf der Vertragslaufzeit am 28.02.2036.",
    "language": "de",
    "entities": ["PERSON", "LOCATION", "IBAN_CODE", "PHONE_NUMBER", "EMAIL_ADDRESS", "DE_ADDRESS", "DE_BIRTHDATE"]
  }'
echo; echo

echo "=== 4. Same probe — WITH allow_list ==="
# The allow_list entries must match the German document labels VERBATIM —
# that is why these two strings stay German.
# Expected differences to example 3:
#   - NO PERSON span on "Versicherungsschein-Nummer" (false positive gone)
#   - still: DE_ADDRESS spans on "Musterweg 15" AND "53113 Bonn"
#   - still: DE_BIRTHDATE on the labeled birth date only — the expiry date
#     ("28.02.2036") is NOT matched, the recognizer is label-anchored
#   - PHONE_NUMBER scores exactly 0.4 and sits right at the default
#     threshold; if it is missing, lower default_score_threshold to 0.35
curl -s -X POST "$BASE_URL/analyze" \
  -H 'Content-Type: application/json' \
  -d '{
    "text": "Versicherungsnehmer: Max Mustermann, Geburtsdatum: 15.08.1985, Musterweg 15, 53113 Bonn. Versicherungsschein-Nummer: L-123456. Tel: 030 1234567, max@example.com, IBAN DE89370400440532013000. Ablauf der Vertragslaufzeit am 28.02.2036.",
    "language": "de",
    "entities": ["PERSON", "LOCATION", "IBAN_CODE", "PHONE_NUMBER", "EMAIL_ADDRESS", "DE_ADDRESS", "DE_BIRTHDATE"],
    "allow_list": ["Versicherungsschein-Nummer", "Versicherungsnehmer"]
  }'
echo; echo

echo "=== 5. English analyze — built-ins + EN_BIRTHDATE ==="
# English runs on the spaCy built-ins plus ONE custom recognizer:
# EN_BIRTHDATE, label-anchored like its German sibling (functional, not
# battle-tested). There is still no EN_ADDRESS — expect fewer entity types
# than in the German examples.
# Expected: EN_BIRTHDATE covers "Date of birth: 15 August 1985"; the expiry
# date ("28 February 2036") is NOT matched — the recognizer is label-anchored.
curl -s -X POST "$BASE_URL/analyze" \
  -H 'Content-Type: application/json' \
  -d '{
    "text": "John Doe lives at 123 Main Street, Springfield. Date of birth: 15 August 1985. Phone: (217) 555-0142, john.doe@example.com. The policy expires on 28 February 2036.",
    "language": "en",
    "entities": ["PERSON", "LOCATION", "EMAIL_ADDRESS", "PHONE_NUMBER", "EN_BIRTHDATE"]
  }'
echo
