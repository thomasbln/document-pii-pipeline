# Generating test documents

**Want to skip this?** Four ready-made test PDFs live in
[test-documents/](test-documents/) — two German, two English, all with
fictional companies and Mustermann/Doe-class data. Drag one onto the demo
and you are done. The prompts below remain for building your own variants
and for the photo path (print → photograph).

The demo wants a photo of a document — but **never test with real documents
or real personal data**. Feed one of the prompts below to any LLM to get a
realistic, fully fictional test document instead. Everything in these
prompts is Max-Mustermann / John-Doe-class placeholder data.

Two prompts are German and two are English — the German documents exercise
the battle-tested custom recognizers, the English ones exercise the
built-ins-only path.

## 1. German insurance letter with a claim report

Produces a German insurance letter carrying the label
"Versicherungsschein-Nummer" ("insurance policy number"). This **triggers
the documented false positive**: without an allow_list, the label itself is
tagged PERSON at score 0.85. The demo sends the allow_list, so the label
survives there — run example 3 in `curl-examples.sh` to see the raw effect.

German prompt (asks for: a fictional insurance letter confirming a received
claim report, with policy number, name/address, phone, email, test IBAN,
and an expiry date — invented data only):

> Erstelle ein fiktives Versicherungsschreiben einer erfundenen Versicherung
> an den Versicherungsnehmer Max Mustermann: Bestätigung einer eingegangenen
> Schadensmeldung. Das Schreiben enthält: eine Versicherungsschein-Nummer im
> Format L-123456, Name und Adresse des Versicherungsnehmers (erfundene
> deutsche Adresse mit Straße, Hausnummer, PLZ und Ort), eine Telefonnummer,
> eine E-Mail-Adresse, die Test-IBAN DE89370400440532013000 und ein
> Ablaufdatum der Vertragslaufzeit. Verwende ausschließlich erfundene Daten,
> keine echten Personen oder Firmen.

## 2. German medical invoice

Produces a German doctor's invoice with a labeled birth date AND a payment
due date. Watch in the demo: **the labeled birth date gets masked
(DE_BIRTHDATE), the due date survives** — the recognizer is label-anchored
on purpose.

German prompt (asks for: a fictional medical invoice with a labeled birth
date, address, invoice number, line items, and a due date — invented data
only):

> Erstelle eine fiktive Arztrechnung einer erfundenen Praxis an den Patienten
> Max Mustermann. Die Rechnung enthält: die Zeile "Geburtsdatum: 15.08.1985",
> eine erfundene deutsche Adresse mit Straße, Hausnummer, PLZ und Ort, eine
> Rechnungsnummer, drei fiktive Behandlungspositionen mit Beträgen und ein
> Zahlungsziel ("zahlbar bis") mit Datum. Verwende ausschließlich erfundene
> Daten, keine echten Personen oder Praxen.

## 3. English insurance claim letter

The English counterpart of prompt 1. English runs on spaCy built-ins plus
the label-anchored EN_BIRTHDATE — **expect fewer entity types than in the
German examples** (there is no EN_ADDRESS).

> Write a fictional insurance claim confirmation letter from a made-up
> insurance company to a policyholder named John Doe. Include: a policy
> number in the format L-123456, the policyholder's name and a fictional US
> address (street, city, state, ZIP), a phone number from the reserved 555
> range, an email address on example.com, and a policy expiry date. Use
> invented data only — no real people or companies.

## 4. English medical invoice

The English counterpart of prompt 2. The labeled birth date is caught by
EN_BIRTHDATE (label-anchored like its German sibling, functional but not
battle-tested) — **the birth date gets masked, the payment due date
survives**.

> Write a fictional medical invoice from a made-up clinic to a patient named
> John Doe. Include: a line "Date of birth: 15 August 1985", a fictional US
> address, an invoice number, three invented treatment line items with
> amounts, and a payment due date. Use invented data only — no real people
> or clinics.

## From text to test photo

Print the generated document — or simply display it on screen — and
photograph it with your phone. Feed that photo to the demo, not a clean
screenshot: the OCR settings are tuned for real photo conditions (skewed
pages, uneven lighting, sparse document layouts — see README, trap 5), and
a phone photo is what actually exercises them.
