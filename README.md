# document-pii-pipeline

![License: MIT](https://img.shields.io/badge/License-MIT-green)
![Data: stays local](https://img.shields.io/badge/Data-stays_local-blue)

> **OCR → PII masking → LLM.** The document stays local, the PII never
> reaches the model. Works with German and English documents.

## Why

Legal and insurance documents are PII by nature — names, addresses, birth
dates, IBANs are not the exception in these texts, they are the content.
Sending them verbatim to a cloud LLM is off the table in most professional
contexts; running a capable LLM fully on-premise is out of reach for most
small teams.

The middle path is an old idea: **encapsulate the sensitive part.** OCR and
PII detection run locally. Identifying values are swapped for numbered
placeholders before anything leaves the machine, and swapped back after the
answer returns. The model reasons about `[PERSON_1]` and never learns who
that is.

```python
# the whole round trip — the runnable version: examples/llm-roundtrip.sh
spans = analyze(text)                 # POST /analyze  (local container)
masked, mapping = mask(text, spans)   # [PERSON_1], [IBAN_CODE_1], …
answer = ask_llm(prompt, masked)      # the ONLY step that leaves the machine
final = restore(answer, mapping)      # placeholders → real values, locally
```

The simplicity is the point. There is no framework here and no service to
build: an off-the-shelf analyzer container (Presidio), string slicing for
the masking, browser OCR (tesseract.js) — and one mapping table that must
stay on your disk. Use it as a blueprint for your own stack.

Getting there, however, cost a handful of silent failures: configs that are
read but ignored, person hits that vanish between two layers, an OCR
default that halves recall without ever erroring. Those are
[the five traps](#the-five-traps) — the reason this repo exists. German
configs are battle-tested; the structure is language-agnostic.

![Animated walk through the demo's five tabs on a sample John Doe policy letter: the OCR text, the detected PII highlighted by type, the masked text with numbered placeholders, the LLM's response still full of placeholders, and the re-identified answer with its local mapping table.](./assets/demo-pipeline.gif)

*One document, five states — the demo walks the pipeline: detect, mask,
send, re-identify. The mapping table never leaves the machine.*

## Prerequisites

**Docker Compose ≥ 2.24** — that is the whole list (2.24 is where the
`env_file: required: false` syntax landed, which keeps the stack starting
without a `.env`). No Python, no Node on your machine: everything runs
inside the containers, and the spaCy models are baked into the image rather
than downloaded at runtime.

## Setup

```bash
git clone https://github.com/thomasbln/document-pii-pipeline.git
cd document-pii-pipeline
docker compose up --build
```

On the first run: the build pulls the analyzer image plus two pinned spaCy
models (~600 MB, once). Boot takes ~90 seconds — the analyzer loads its NLP
models eagerly at startup; wait for **"PII detection: ready"** on the demo
page. OCR happens in your browser (tesseract.js fetches its language data
from a CDN on first use); the recognized text is only ever POSTed to the
analyzer container on your own machine.

Then open **http://localhost:8080**. For an immediate result, press
**Try German sample** — or drop a ready-made PDF from
[examples/test-documents/](examples/test-documents/), or your own photo or
PDF. To build a safe test document from scratch, see
[examples/generate-test-documents.md](examples/generate-test-documents.md).
The demo runs without a key; the send button then reports "not configured".

When you are done: `docker compose down`.

### The LLM step (optional, but it is the point)

Sending the masked text to a model is a one-time setup:

```bash
cp .env.example .env
$EDITOR .env    # set LLM_API_KEY — plus LLM_BASE_URL / LLM_MODEL if you are
                # not on OpenAI (Anthropic and a local Ollama are shown in the file)
docker compose up -d --force-recreate caddy
```

The key is attached server-side by the local proxy and never reaches the
browser. Without a `.env` the demo still works up to the masked-text tab;
the LLM step simply reports "not configured".

### Prefer the API?

The analyzer speaks plain JSON:

```bash
# German text: "Max Mustermann lives in Berlin."
curl -s -X POST http://localhost:8080/analyze \
  -H 'Content-Type: application/json' \
  -d '{"text": "Max Mustermann wohnt in Berlin.", "language": "de",
       "entities": ["PERSON", "LOCATION"]}'
# → character spans, one per hit:
#   [{"entity_type": "PERSON",   "start": 0,  "end": 14, "score": 0.85, …},
#    {"entity_type": "LOCATION", "start": 24, "end": 30, "score": 0.85, …}]
```

Full smoke tests — including the `allow_list` and the documented false
positive — live in [examples/curl-examples.sh](examples/curl-examples.sh).

## How it works

```
┌────────────────────────── your machine ──────────────────────────┐
│                                                                  │
│  photo/PDF ─► tesseract.js ─► raw text ─► Presidio ─► PII spans  │
│              (OCR in the     POST          analyzer        │     │
│               browser)       /analyze      (Docker, de/en  │     │
│                                             NER + regex)   │     │
│                                                            │     │
│   masked text — numbered placeholders ◄────────────────────┘     │
│      │                                                           │
│      │     re-identified answer ◄── local re-substitution ◄─┐    │
│      │     (the mapping table never leaves this machine)    │    │
└──────┼──────────────────────────────────────────────────────┼────┘
       ▼                                                      │
  your LLM (cloud or local) ─── response with placeholders ───┘
  sees "[PERSON_1], born [DE_BIRTHDATE_1]" — never the real values
```

PDFs work too — a digital PDF's text layer is extracted directly in the
browser (skipping OCR entirely), while scanned PDFs are rendered to images
and go through the same OCR.

The compose stack runs two containers:

- **`presidio-analyzer`** — [Microsoft Presidio](https://github.com/microsoft/presidio)
  with pinned German and English spaCy models and custom recognizers
  (`DE_ADDRESS`, `DE_BIRTHDATE`, `EN_BIRTHDATE`); English requests
  otherwise run on the built-ins.
- **`caddy`** — serves the static demo page *and* reverse-proxies
  `/analyze` to the analyzer under one origin (`http://localhost:8080`).
  Deliberate, not decoration: opening the demo from `file://` against a
  published analyzer port fails on CORS. So the analyzer publishes no host
  port at all, and the demo works out of the box.

The masking itself is string slicing: the analyzer returns character spans,
the client replaces them with numbered placeholders and keeps the mapping
table local — the round trip sketched [at the top](#why). The demo's legend
doubles as a minimal masking policy: choose per entity type what the LLM
may see; unchecked types stay readable in the text.

## What's in the repo

```
document-pii-pipeline/
├── docker-compose.yml   ← the two containers, and why the analyzer has no host port
├── .env.example         ← optional LLM config; the key stays server-side
├── assets/              ← the pipeline demo GIF
├── caddy/
│   └── Caddyfile        ← serves the demo, proxies /analyze and /llm on one origin
├── presidio/
│   ├── Dockerfile       ← pinned image, models baked in, not downloaded (see trap 4)
│   └── conf/de/         ← the battle-tested German core; also enables English
│       ├── analyzer.yaml  ← languages (de, en) and the 0.4 score threshold
│       ├── nlp.yaml       ← spaCy models and the PER→PERSON mapping (see trap 2)
│       └── registry.yaml  ← the custom DE and EN recognizers (see trap 3)
├── demo/
│   └── index.html       ← the whole demo, one static file: OCR, masking, LLM, restore
└── examples/
    ├── curl-examples.sh ← five smoke tests, incl. allow_list and the false positive
    ├── llm-roundtrip.sh ← mask locally, send masked, re-substitute locally
    ├── test-documents/  ← four ready-made PDFs, Mustermann/Doe class
    └── generate-test-documents.md  ← prompts for building your own safe test documents
```

The `conf/de/` directory is language-scoped on purpose. English works out
of the box via spaCy's built-ins; the battle-tested custom recognizers are
the German ones. **Contributions of `conf/fr/`, `conf/es/`, … with
battle-tested configs for other languages are very welcome.**

## The five traps

Each one: **symptom → cause → fix**. Jump to your symptom:

1. [Config mounted, recognizers missing, no error](#1-presidio-reads-three-config-files-via-three-env-vars-a-consolidated-one-is-silently-ignored)
2. [German names, zero `PERSON` hits](#2-spacys-german-models-emit-the-label-per-without-a-perperson-mapping-you-get-zero-person-hits)
3. [`TypeError` on boot after adding recognizers](#3-type-custom-does-not-exist-the-loader-passes-yaml-fields-verbatim-into-the-constructor)
4. [570 MB re-downloaded on every start](#4-plain-pip-install-in-the-image-lands-in-the-wrong-python-environment)
5. [OCR recall stuck around 50%](#5-tesseractjs-defaults-to-psm-6-which-halves-recall-on-document-layouts)

### 1. Presidio reads THREE config files via THREE env vars — a consolidated one is silently ignored

One clean, consolidated YAML boots green and is never read — the defaults
win silently, no warning, no error. The entrypoint only reads three
separate files through three separate env vars:

```dockerfile
ENV ANALYZER_CONF_FILE=/app/conf/analyzer.yaml
ENV NLP_CONF_FILE=/app/conf/nlp.yaml
ENV RECOGNIZER_REGISTRY_CONF_FILE=/app/conf/registry.yaml
```

### 2. spaCy's German models emit the label `PER` — without a `PER→PERSON` mapping you get zero person hits

German text with obvious names returns zero `PERSON` entities while IBANs
and emails still work — the pipeline looks "mostly fine", which is what
makes this one treacherous. spaCy DE labels persons `PER`; Presidio filters
against `PERSON` and silently drops every hit. Map the labels in `nlp.yaml`
— and write `labels_to_ignore` out explicitly instead of trusting an image
default that can drift between versions:

```yaml
ner_model_configuration:
  model_to_presidio_entity_mapping:
    PER: PERSON        # spaCy DE emits "PER" — without this line: zero person hits
    LOC: LOCATION
    GPE: LOCATION
    ORG: ORGANIZATION
```

### 3. `type: custom` does not exist — the loader passes YAML fields verbatim into the constructor

Boot crash after adding custom recognizers per the docs page:

```
TypeError: PatternRecognizer.__init__() got an unexpected keyword argument 'type'
```

The loader forwards every field of a type-less entry straight into the
constructor — a custom recognizer is marked by the **absence** of `type`.
Two more quirks, confirmed against the schema example shipped inside the
image (which beats the docs page): `supported_language` is **singular** for
custom entries, and regex backslashes are double-escaped in double-quoted
YAML:

```yaml
# Custom recognizer: NO "type" field — its absence is what marks it as custom.
- name: "DE Address Recognizer"
  supported_language: "de"          # singular for custom entries!
  supported_entity: "DE_ADDRESS"
  patterns:
    - name: "street with number"    # German street suffixes: -straße, -weg, -platz, ...
      regex: "([A-ZÄÖÜ][\\wäöüß.-]*(?:straße|strasse|str\\.|weg|allee|platz|gasse|ring|damm|ufer)\\s+\\d{1,4}[a-z]?)"
      score: 0.6
```

The tip that generalizes: don't iterate blind `docker compose up` loops —
run the service manually inside the container for the real traceback, and
read the schema example shipped in the artifact before trusting the docs.

### 4. Plain `pip install` in the image lands in the wrong Python environment

The image builds fine, but every container start re-downloads the ~570 MB
German model. The Presidio image contains two Python environments, and a
plain `pip install` lands in the one the application never looks at.
Install through the app's own environment, pinned — inside the image at
build time, nothing touches your machine:

```dockerfile
# in presidio/Dockerfile
RUN poetry run pip install --no-cache-dir \
    https://github.com/explosion/spacy-models/releases/download/de_core_news_lg-3.8.0/de_core_news_lg-3.8.0-py3-none-any.whl
```

Verification: no `Downloading...` line in the boot log anymore.

### 5. tesseract.js defaults to PSM 6 — which halves recall on document layouts

On phone photos of real documents, recall on the fields that matter sits
around 50% — it looks like "tesseract just isn't good enough" and tempts
you toward a cloud vision API. It is a segmentation artifact: tesseract.js
applies the Tesseract **API default PSM 6** (single uniform block), not the
CLI default PSM 3 that tutorials suggest. Set PSM 11 (sparse text)
explicitly:

```js
await worker.setParameters({
  tessedit_pageseg_mode: Tesseract.PSM.SPARSE_TEXT, // PSM 11
});
```

In a sweep over the same photo set this took critical-field recall from
**~50% to 100%**, comb-field numbers included. (Same sweep: the `best`
traineddata scored zero points over `fast` at 2.2× the runtime.) The rule
behind the trap: **library defaults are a measurement subject, not a
given.**

## Honest limitations

Read this before trusting the pipeline with anything sensitive.

- **A missed entity is a leak.** This is *pseudonymization*, not
  anonymization: anything the recognizers miss goes to the LLM verbatim.
  Risk reduction, not a guarantee — do not call it "anonymized" in a GDPR
  sense.
- **OCR is the ceiling.** Handwriting is out of scope, comb/box fields
  fragment even print. Check the raw-text tab (low-confidence words are
  grayed) before trusting the masked output.
- **Known false negatives.** `DE_ADDRESS` matches streets by suffix;
  suffix-less names (`Am Hang 3`) pass through — a deliberate trade-off
  against false positives.
- **Over-masking happens too.** Leading-zero dot-dates can be co-masked as
  `PHONE_NUMBER`, and NER spans can swallow an adjacent field label across
  a line break. Both fail-safe: nothing leaks.
- **Scores are not confidence.** spaCy hits arrive at a flat 0.85 — a false
  positive scores exactly like a real name. Don't build thresholds on it;
  use the request-side `allow_list` (see `examples/curl-examples.sh`).
- **The English path is not battle-tested.** `EN_BIRTHDATE` has no eval
  corpus yet; `EN_ADDRESS` does not exist — contributions welcome.
- **Language auto-detection is a heuristic.** Short texts can misdetect —
  use the manual override next to the detected language.
- **Placeholder collisions.** Presidio does not number placeholders; demo
  and script number them client-side and keep the mapping local.

## Platform notes

The analyzer image is amd64-only (upstream ships no ARM build):

- **Windows / Linux on Intel or AMD** — runs natively.
- **Apple Silicon (M-series Macs)** — runs via Docker's built-in emulation:
  works out of the box, the first boot is just slower.
- **ARM Linux** — not supported.

## License

MIT.

Built by [Thomas Rehmer](https://github.com/thomasbln). If you work with
legal documents and LLMs, you may also be interested in
[Lex Orchestra](https://github.com/thomasbln/Lex-Orchestra).
