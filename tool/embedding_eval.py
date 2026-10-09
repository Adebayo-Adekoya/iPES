"""Compare embedding models for iPES smart search.

Reads build/eval/search_set.json (written by test/eval/search_export_test.dart)
and scores each model the same way the app ranks results:

- semantic: rank the facet-allowed items by cosine similarity only
- hybrid:   reciprocal rank fusion (k = 60, top 100 of each list) of the app's
            keyword ranking and the model's semantic top 20, as in search.dart

Metrics match test/eval/evaluation_test.dart: nDCG@10 with graded relevance,
lift of hybrid over keyword-only, and known item (relevance 2) in the top 3.

Writes build/eval/embedding_report.md and build/eval/embedding_results.json.
Gated models need HF_TOKEN in the environment; a model that cannot be loaded
is reported as skipped rather than failing the run.
"""

from __future__ import annotations

import json
import math
import os
import sys
import time
from pathlib import Path

import numpy as np

OUT = Path("build/eval")
RRF_K = 60
SEMANTIC_TOP = 20

# name, Hugging Face id, query template, document template, truncate_dim, licence
MODELS = [
    ("EmbeddingGemma 300M (768)", "google/embeddinggemma-300m",
     "task: search result | query: {q}", "title: {title} | text: {text}", None, "Gemma Terms of Use"),
    ("EmbeddingGemma 300M (256)", "google/embeddinggemma-300m",
     "task: search result | query: {q}", "title: {title} | text: {text}", 256, "Gemma Terms of Use"),
    ("multilingual-E5-small (384)", "intfloat/multilingual-e5-small",
     "query: {q}", "passage: {title}. {text}", None, "MIT"),
]


def ndcg_at(ranked: list[str], rel: dict[str, int], k: int = 10) -> float:
    def dcg(gains: list[int]) -> float:
        return sum((2 ** g - 1) / math.log2(i + 2) for i, g in enumerate(gains[:k]))

    ideal = dcg(sorted(rel.values(), reverse=True))
    return 0.0 if ideal == 0 else dcg([rel.get(key, 0) for key in ranked]) / ideal


def top3(ranked: list[str], rel: dict[str, int]) -> float:
    return 1.0 if any(rel.get(key, 0) == 2 for key in ranked[:3]) else 0.0


def rrf(*lists: list[str]) -> list[str]:
    scores: dict[str, float] = {}
    for lst in lists:
        for rank, key in enumerate(lst[:100]):
            scores[key] = scores.get(key, 0.0) + 1.0 / (RRF_K + rank + 1)
    return [k for k, _ in sorted(scores.items(), key=lambda kv: -kv[1])]


def summarise(rows: list[dict], key: str) -> dict:
    def mean(xs):
        return float(np.mean(xs)) if xs else 0.0

    return {
        "ndcg10": mean([r[key]["ndcg"] for r in rows]),
        "ndcg10_meaning": mean([r[key]["ndcg"] for r in rows if r["kind"] == "meaning"]),
        "ndcg10_keyword_queries": mean([r[key]["ndcg"] for r in rows if r["kind"] == "keyword"]),
        "top3": mean([r[key]["top3"] for r in rows]),
    }


def main() -> int:
    data = json.loads((OUT / "search_set.json").read_text())
    docs = data["docs"]
    queries = data["queries"]
    keys = [d["key"] for d in docs]

    rows = []
    for q in queries:
        rel = {k: int(v) for k, v in q["relevance"].items()}
        row = {"query": q["query"], "kind": q["kind"]}
        for name, ranked in (("keyword", q["keyword"]), ("current", q["currentHybrid"])):
            row[name] = {"ndcg": ndcg_at(ranked, rel), "top3": top3(ranked, rel), "top": ranked[:3]}
        rows.append(row)

    results = {
        "queries": len(queries),
        "docs": len(docs),
        "baselines": {
            "Keyword only (BM25)": summarise(rows, "keyword"),
            "Current hybrid (hashing stand-in)": summarise(rows, "current"),
        },
        "models": {},
    }

    try:
        import torch
        from sentence_transformers import SentenceTransformer
    except ImportError as e:  # pragma: no cover
        print("sentence-transformers not installed:", e)
        return 1
    torch.set_num_threads(max(1, os.cpu_count() or 1))

    loaded: dict[str, object] = {}
    for name, hf_id, q_tpl, d_tpl, dim, licence in MODELS:
        try:
            if hf_id not in loaded:
                t0 = time.time()
                loaded[hf_id] = SentenceTransformer(hf_id, device="cpu")
                print(f"Loaded {hf_id} in {time.time() - t0:.1f}s")
            model = loaded[hf_id]
        except Exception as e:  # gated without token, network, etc.
            results["models"][name] = {"skipped": f"{type(e).__name__}: {str(e)[:300]}", "licence": licence}
            print(f"SKIPPED {name}: {e}")
            continue

        def enc(texts: list[str]) -> np.ndarray:
            v = model.encode(texts, prompt="", batch_size=8, convert_to_numpy=True,
                             normalize_embeddings=True, show_progress_bar=False)
            if dim:
                v = v[:, :dim]
                v = v / np.linalg.norm(v, axis=1, keepdims=True)
            return v

        doc_texts = [d_tpl.format(title=d["title"], text=d["text"]) for d in docs]
        t0 = time.time()
        doc_vecs = enc(doc_texts)
        doc_secs = time.time() - t0
        q_texts = [q_tpl.format(q=q["semanticText"] or q["query"]) for q in queries]
        t0 = time.time()
        q_vecs = enc(q_texts)
        q_ms = (time.time() - t0) * 1000 / len(q_texts)

        index = {k: i for i, k in enumerate(keys)}
        sem_key, hyb_key = f"{name}|semantic", f"{name}|hybrid"
        for row, q, qv in zip(rows, queries, q_vecs):
            rel = {k: int(v) for k, v in q["relevance"].items()}
            allowed = q["allowed"]
            sims = sorted(((float(doc_vecs[index[k]] @ qv), k) for k in allowed), reverse=True)
            semantic = [k for _, k in sims]
            if q["textEmpty"]:
                hybrid = q["keyword"]  # facet-only query: the app lists by recency
            else:
                hybrid = rrf(q["keyword"], semantic[:SEMANTIC_TOP])
            row[sem_key] = {"ndcg": ndcg_at(semantic, rel), "top3": top3(semantic, rel), "top": semantic[:3]}
            row[hyb_key] = {"ndcg": ndcg_at(hybrid, rel), "top3": top3(hybrid, rel), "top": hybrid[:3]}

        params = sum(p.numel() for p in model.parameters())
        results["models"][name] = {
            "hf_id": hf_id,
            "licence": licence,
            "dimensions": dim or int(doc_vecs.shape[1]),
            "max_tokens": int(getattr(model, "max_seq_length", 0) or 0),
            "parameters_millions": round(params / 1e6),
            "semantic": summarise(rows, sem_key),
            "hybrid": summarise(rows, hyb_key),
            "ci_cpu_doc_embed_ms": round(doc_secs * 1000 / len(docs), 1),
            "ci_cpu_query_embed_ms": round(q_ms, 1),
        }
        print(name, json.dumps(results["models"][name]["hybrid"]))

    kw = results["baselines"]["Keyword only (BM25)"]["ndcg10"]
    for m in results["models"].values():
        if "hybrid" in m:
            m["lift_over_keyword"] = (m["hybrid"]["ndcg10"] - kw) / kw if kw else 0.0
    cur = results["baselines"]["Current hybrid (hashing stand-in)"]
    cur["lift_over_keyword"] = (cur["ndcg10"] - kw) / kw if kw else 0.0
    results["perQuery"] = rows

    (OUT / "embedding_results.json").write_text(json.dumps(results, indent=2))

    def pct(x):
        return f"{x * 100:.1f}%"

    lines = [
        "# Embedding model comparison for iPES smart search",
        "",
        f"{len(queries)} judged queries over {len(docs)} sample items. Hybrid = keyword ranking fused with the "
        "model's semantic ranking (reciprocal rank fusion), as the app does. Targets: nDCG@10 ≥ 0.75, "
        "lift over keyword-only ≥ 15%, known item in top 3 ≥ 90%.",
        "",
        "| Ranker | Hybrid nDCG@10 | Lift over keyword | Top 3 | Vocabulary-mismatch nDCG | Semantic-only nDCG | Dims | Licence |",
        "| --- | --- | --- | --- | --- | --- | --- | --- |",
    ]
    b = results["baselines"]["Keyword only (BM25)"]
    lines.append(f"| Keyword only (BM25) | {b['ndcg10']:.3f} | — | {pct(b['top3'])} | {b['ndcg10_meaning']:.3f} | — | — | — |")
    lines.append(f"| Current stand-in (hashing) | {cur['ndcg10']:.3f} | {pct(cur['lift_over_keyword'])} | "
                 f"{pct(cur['top3'])} | {cur['ndcg10_meaning']:.3f} | — | 512 | — |")
    for name, m in results["models"].items():
        if "skipped" in m:
            lines.append(f"| {name} | skipped: {m['skipped'][:80]} | | | | | | {m['licence']} |")
            continue
        h, s = m["hybrid"], m["semantic"]
        lines.append(f"| {name} | {h['ndcg10']:.3f} | {pct(m['lift_over_keyword'])} | {pct(h['top3'])} | "
                     f"{h['ndcg10_meaning']:.3f} | {s['ndcg10']:.3f} | {m['dimensions']} | {m['licence']} |")
    lines += ["", "| Model | Parameters | Max input tokens | Embed one item (CI CPU) | Embed one query (CI CPU) |",
              "| --- | --- | --- | --- | --- |"]
    for name, m in results["models"].items():
        if "skipped" not in m:
            lines.append(f"| {name} | {m['parameters_millions']}M | {m['max_tokens']} | "
                         f"{m['ci_cpu_doc_embed_ms']} ms | {m['ci_cpu_query_embed_ms']} ms |")
    (OUT / "embedding_report.md").write_text("\n".join(lines) + "\n")
    print("\n".join(lines))
    return 0


if __name__ == "__main__":
    sys.exit(main())
