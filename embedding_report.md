# Embedding model comparison for iPES smart search

38 judged queries over 38 sample items. Hybrid = keyword ranking fused with the model's semantic ranking (reciprocal rank fusion), as the app does. Targets: nDCG@10 ≥ 0.75, lift over keyword-only ≥ 15%, known item in top 3 ≥ 90%.

| Ranker | Hybrid nDCG@10 | Lift over keyword | Top 3 | Vocabulary-mismatch nDCG | Semantic-only nDCG | Dims | Licence |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Keyword only (BM25) | 0.844 | — | 89.5% | 0.596 | — | — | — |
| Current stand-in (hashing) | 0.904 | 7.1% | 97.4% | 0.754 | — | 512 | — |
| EmbeddingGemma 300M (768) | 0.963 | 14.0% | 100.0% | 0.905 | 0.988 | 768 | Gemma Terms of Use |
| EmbeddingGemma 300M (256) | 0.959 | 13.6% | 100.0% | 0.905 | 0.963 | 256 | Gemma Terms of Use |
| multilingual-E5-small (384) | 0.971 | 15.0% | 100.0% | 0.929 | 0.939 | 384 | MIT |

| Model | Parameters | Max input tokens | Embed one item (CI CPU) | Embed one query (CI CPU) |
| --- | --- | --- | --- | --- |
| EmbeddingGemma 300M (768) | 308M | 2048 | 202.9 ms | 25.5 ms |
| EmbeddingGemma 300M (256) | 308M | 2048 | 200.2 ms | 25.4 ms |
| multilingual-E5-small (384) | 118M | 512 | 46.2 ms | 4.4 ms |

Merging rankings: nDCG@10 (lift over keyword) for each way of fusing keyword and semantic results.

| Model | equal | semantic x2 | semantic x3 | Semantic only |
| --- | --- | --- | --- | --- |
| EmbeddingGemma 300M (768) | 0.963 (14.0%) | 0.969 (14.8%) | 0.967 (14.5%) | 0.988 (17.0%) |
| EmbeddingGemma 300M (256) | 0.959 (13.6%) | 0.969 (14.7%) | 0.967 (14.5%) | 0.963 (14.1%) |
| multilingual-E5-small (384) | 0.971 (15.0%) | 0.970 (14.9%) | 0.970 (14.9%) | 0.939 (11.2%) |

With keyword-only at 0.844, the largest possible lift on this set is 18.4%.
