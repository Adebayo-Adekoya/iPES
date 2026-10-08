# iPES — intelligent Personal E-Library Systems (prototype)

Working prototype of the iPES (intelligent personal e-library) core flow for phones and tablets:
**import an item → auto-catalogue it → review → search → export** in library-standard formats.

Spec and designs: see the iPES product specification and the iPES App Screens canvas.

## What works

| Step | What the prototype does |
| --- | --- |
| Import | Pick any files (file_picker). Duplicates are detected by SHA-256. |
| Auto-catalogue | Reads EPUB package metadata and text, PDF Info/XMP, page count and Flate-compressed text, MP3 ID3v2 tags, photo EXIF dates, text/Markdown/HTML, and file-name patterns. Finds ISBNs (ISO 2108 check digits) and DOIs, guesses language, writes a short summary, and scores every field with its source and confidence. |
| Auto-classify | Suggests up to three Dewey classes and subject terms (rules tier). |
| Review | Fields below 0.70 confidence are highlighted; the user edits and accepts. |
| Search | Hybrid ranking: BM25 keyword scores + meaning-based vectors, merged by reciprocal rank fusion; "videos from 2024"-style facets; best-passage answers. |
| Export | MARC 21 (ISO 2709 `.mrc`), MARCXML, Dublin Core XML (OAI-DC) and JSON-LD, ISO 690 citations. |
| Layout | Material 3 window size classes: phone (bottom bar), medium (rail), tablet landscape (list + record side by side). |

## Prototype stand-ins (by design)

- **Meaning-based search** uses `HashingEmbedder` (hashed stems, trigrams and a concept lexicon) instead of EmbeddingGemma. Swap by implementing `TextEmbedder`.
- **No LLM drafting yet**: the rules tier runs everywhere; `DraftEnhancer` is the hook for the optional on-device model.
- **Storage** is a JSON file in app-private storage (in memory on the web), not encrypted SQLite.
- **No OCR or speech-to-text**: scanned images and audio rely on embedded metadata and file names.
- **Module builder** is not in this prototype.

## Layout

```
lib/core/     pure Dart: record model, extractors, cataloguer, classifier, search, exports, library
lib/core/sample/  file builders (EPUB, PDF, MP3, JPEG) and the sample corpus with gold metadata
lib/app/      Flutter UI: adaptive shell, library, review, search, record, export
test/core/    unit tests      test/widget/  widget and end-to-end flow tests
test/eval/    evaluation against spec sections 11–12 → build/eval/report.md
```

## Run

Platform folders are generated, not committed:

```
flutter create --org org.ipes --project-name ipes --platforms android,ios,web .
rm -f test/widget_test.dart
flutter pub get
flutter test            # all tests, including the evaluation
flutter run             # on a connected phone, tablet or Chrome
```

CI (`.github/workflows/ci.yml`) analyzes, tests, runs the evaluation and builds an Android APK and the web demo on every push.
