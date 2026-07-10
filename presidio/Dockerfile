FROM mcr.microsoft.com/presidio-analyzer:2.2.358

# German model via *poetry run pip* — IMPORTANT: a plain "pip install" lands
# in /usr/local/... where no spacy exists (the image contains TWO Python
# environments!). The consequence would be an unpinned ~570 MB re-download on
# EVERY container start. Verified: with poetry run, no "Downloading..." line
# appears in the boot log.
# (--timeout/--retries: the wheel is ~570 MB — give slow connections a chance.)
RUN poetry run pip install --no-cache-dir --timeout 120 --retries 10 \
    https://github.com/explosion/spacy-models/releases/download/de_core_news_lg-3.8.0/de_core_news_lg-3.8.0-py3-none-any.whl

# English model — same install route for the same reason, pinned to the same
# spaCy version family (3.8.x) as the German model. EN runs on spaCy
# built-ins only (no custom recognizers, see conf/de/registry.yaml).
RUN poetry run pip install --no-cache-dir --timeout 120 --retries 10 \
    https://github.com/explosion/spacy-models/releases/download/en_core_web_md-3.8.0/en_core_web_md-3.8.0-py3-none-any.whl

# Presidio reads THREE separate config files through THREE env vars
# (app.py: ANALYZER_CONF_FILE + NLP_CONF_FILE + RECOGNIZER_REGISTRY_CONF_FILE).
# A consolidated single file is silently ignored — no warning, the defaults
# just win. (Cost three boot loops to diagnose.)
COPY conf/de/analyzer.yaml /app/conf/analyzer.yaml
COPY conf/de/nlp.yaml /app/conf/nlp.yaml
COPY conf/de/registry.yaml /app/conf/registry.yaml

ENV ANALYZER_CONF_FILE=/app/conf/analyzer.yaml
ENV NLP_CONF_FILE=/app/conf/nlp.yaml
ENV RECOGNIZER_REGISTRY_CONF_FILE=/app/conf/registry.yaml
