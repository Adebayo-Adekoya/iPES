# iPES prototype evaluation

Generated 2026-10-09T18:37:56.363447Z by `test/eval/evaluation_test.dart`.

| Area | Metric | Measured | Target | Status |
| --- | --- | --- | --- | --- |
| Auto-cataloguing | Field accuracy: title, creator, date, identifier | 99.2% | ≥ 90% | Met |
| Auto-cataloguing | · title (184 items with a known value) | 99.5% | — | Info |
| Auto-cataloguing | · creator (163 items with a known value) | 99.4% | — | Info |
| Auto-cataloguing | · date (145 items with a known value) | 98.6% | — | Info |
| Auto-cataloguing | · identifier (40 items with a known value) | 100.0% | — | Info |
| Auto-cataloguing | Drafts accepted with ≤ 1 edit | 99.5% | ≥ 75% | Met |
| Performance | Draft record for a 20-page PDF, no LLM (CI machine) | 29 ms | ≤ 2 s | Met |
| Smart search | nDCG@10, 38 judged queries (hybrid) | 0.904 | ≥ 0.75 | Met |
| Smart search | Lift over keyword-only (keyword nDCG 0.844) | 7.1% | ≥ 15% | Not met |
| Smart search | · vocabulary-mismatch queries: hybrid vs keyword | 0.754 vs 0.596 | — | Info |
| Smart search | Known item in top 3 results | 97.4% | ≥ 90% | Met |
| Auto-classify | Correct main class (hundreds) in top 3 suggestions | 89.2% | ≥ 85% | Met |
| Auto-classify | · correct division (tens) in top 3 | 78.3% | — | Info |
| Conformance | MARC 21 ISO 2709 round trip / MARCXML / Dublin Core XML (188 records) | 100.0% / 100.0% / 100.0% | 100% | Met |
| Collection health | Core Dublin Core fields filled per item | 82.4% | ≥ 85% | Not met |
| Performance | Keyword search p95, 20,000 items (CI machine) | 15.6 ms | ≤ 150 ms | Met |
| Performance | Smart (hybrid) search p95, 20,000 items (CI machine) | 51.7 ms | ≤ 500 ms | Met |
| Performance | Index build for 20,000 items (one-off) | 7.1 s | — | Info |
| Usability | System Usability Scale | — | ≥ 80 | Not measured |
| Usability | Custom module created unaided in ≤ 3 min | — (module builder not in prototype) | ≥ 80% | Not measured |
| Engagement | 30-day retention; store rating | — (needs beta) | ≥ 35%; ≥ 4.5 | Not measured |
| Reliability | Crash-free sessions | — (needs beta) | ≥ 99.5% | Not measured |

Limits: synthetic corpus written alongside the cataloguer (accuracy is optimistic); the meaning-based ranker is a hashing stand-in for EmbeddingGemma; timings are from the CI machine, not a phone. Two cataloguing bugs found by the first run on this corpus were fixed, so it is not a held-out test set.
