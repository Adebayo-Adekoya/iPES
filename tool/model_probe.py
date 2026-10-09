"""Probe the on-device candidates for iPES smart search.

For each model it records, in build/eval/model_probe.json and model_probe.md:
- the ONNX files in the repo and their sizes
- the tokenizer.json settings (everything except the vocabulary itself)
- ONNX input and output names
- whether the ONNX pipeline (tokenizer -> ONNX -> pooling) matches
  sentence-transformers (cosine per sentence)

It also writes, for the Dart tests and the app:
- build/models/<slug>/tokenizer.json            (Dart tokenizer tests)
- build/eval/tokenizer_fixtures.json            (text -> expected token ids)
- build/eval/model_reference.json               (reference vectors)
"""

from __future__ import annotations

import json
import os
import shutil
import sys
import time
from pathlib import Path

import numpy as np

OUT = Path("build/eval")
MODELS_DIR = Path("build/models")

CANDIDATES = [
    {
        "slug": "e5-small",
        "name": "multilingual-E5-small",
        "repo": "Xenova/multilingual-e5-small",
        "st_id": "intfloat/multilingual-e5-small",
        "onnx": "onnx/model_quantized.onnx",
        "query": "query: {q}",
        "doc": "passage: {title}. {text}",
        "pooling": "mean",
    },
    {
        "slug": "embeddinggemma",
        "name": "EmbeddingGemma 300M",
        "repo": "onnx-community/embeddinggemma-300m-ONNX",
        "st_id": "google/embeddinggemma-300m",
        "onnx": "onnx/model_quantized.onnx",
        "query": "task: search result | query: {q}",
        "doc": "title: {title} | text: {text}",
        "pooling": "sentence_embedding",
    },
]

TRICKY = [
    "Hello world", "  leading and   multiple   spaces  ", "Tenancy Agreement - Flat 3B, East Legon",
    "ISBN 978-9988-01234-2 (2021)", "doi:10.5555/ipes.2024.017", "Réunion des parents d'élèves — été 2025",
    "Ɛkɔm de me: Twi words ɛ ɔ ŋ", "Ẹ kú àárọ̀ (Yoruba)", "naïve café façade coöperate", "Ｆｕｌｌｗｉｄｔｈ ＡＢＣ １２３",
    "emoji 📚🎵 and symbols © ® ™ € £ ₵", "tab\tand\nnewline", "UPPER lower MiXeD", "x", "",
    "GHS 200.00 for 125.4 kWh", "e-mail: someone@example.com", "C++ / C# / F#", "日本語のテキスト", "Привет мир",
    "what does my lease say about notice", "fridge guarantee", "قارئ الكتب",
]


def dump_tokenizer(path: Path) -> dict:
    data = json.loads(path.read_text())
    model = dict(data.get("model", {}))
    vocab = model.pop("vocab", None)
    merges = model.pop("merges", None)
    info = {
        "normalizer": data.get("normalizer"),
        "pre_tokenizer": data.get("pre_tokenizer"),
        "post_processor": data.get("post_processor"),
        "decoder": data.get("decoder"),
        "truncation": data.get("truncation"),
        "padding": data.get("padding"),
        "model": model,
        "vocab_size": len(vocab) if vocab is not None else None,
        "vocab_sample": (vocab[:5] if isinstance(vocab, list) else list(vocab.items())[:5]) if vocab else None,
        "merges_count": len(merges) if merges is not None else None,
        "merges_sample": merges[:5] if merges else None,
        "added_tokens": data.get("added_tokens", [])[:12],
        "added_tokens_count": len(data.get("added_tokens", [])),
    }
    # The precompiled charsmap is a large base64 blob; keep only its length.
    norm = info["normalizer"]
    if isinstance(norm, dict):
        for n in norm.get("normalizers", [norm]):
            if isinstance(n, dict) and "precompiled_charsmap" in n:
                n["precompiled_charsmap"] = f"<{len(n['precompiled_charsmap'] or '')} chars>"
    return info


def main() -> int:
    from huggingface_hub import HfApi, hf_hub_download
    from transformers import AutoTokenizer
    import onnxruntime as ort

    OUT.mkdir(parents=True, exist_ok=True)
    MODELS_DIR.mkdir(parents=True, exist_ok=True)
    search_set = json.loads((OUT / "search_set.json").read_text()) if (OUT / "search_set.json").exists() else None

    api = HfApi()
    probe: dict = {"onnxruntime": ort.__version__, "models": {}}
    fixtures: dict = {}
    reference: dict = {}

    for c in CANDIDATES:
        entry: dict = {"repo": c["repo"]}
        probe["models"][c["slug"]] = entry
        try:
            info = api.model_info(c["repo"], files_metadata=True)
            entry["gated"] = getattr(info, "gated", None)
            entry["files"] = sorted(
                [{"name": s.rfilename, "mb": round((s.size or 0) / 1e6, 1)} for s in info.siblings
                 if s.rfilename.endswith((".onnx", ".onnx_data", "tokenizer.json", "tokenizer_config.json",
                                          "config.json", "special_tokens_map.json"))],
                key=lambda f: f["name"])
        except Exception as e:
            entry["error"] = f"model_info: {e}"
            print(entry["error"])
            continue

        try:
            tok_path = Path(hf_hub_download(c["repo"], "tokenizer.json"))
            dest = MODELS_DIR / c["slug"]
            dest.mkdir(parents=True, exist_ok=True)
            shutil.copy(tok_path, dest / "tokenizer.json")
            entry["tokenizer"] = dump_tokenizer(tok_path)
            tok = AutoTokenizer.from_pretrained(c["repo"])
            entry["tokenizer_class"] = type(tok).__name__
            entry["special"] = {"bos": tok.bos_token, "eos": tok.eos_token, "pad": tok.pad_token,
                                "unk": tok.unk_token, "pad_id": tok.pad_token_id}
        except Exception as e:
            entry["error"] = f"tokenizer: {e}"
            print(entry["error"])
            continue

        # Fixture texts: tricky strings, prompted queries and documents.
        texts = list(TRICKY)
        if search_set:
            for q in search_set["queries"]:
                texts.append(c["query"].format(q=q["semanticText"] or q["query"]))
            for d in search_set["docs"]:
                texts.append(c["doc"].format(title=d["title"], text=d["text"]))
        texts += [c["query"].format(q=t) for t in TRICKY[:6]]
        enc = tok(texts, add_special_tokens=True, truncation=True, max_length=512)
        fixtures[c["slug"]] = [{"text": t, "ids": ids} for t, ids in zip(texts, enc["input_ids"])]
        entry["fixture_count"] = len(texts)

        # ONNX session and a parity check against sentence-transformers.
        try:
            t0 = time.time()
            # Download into a plain folder so external weight files sit next
            # to the .onnx file, as they will on the phone.
            local = MODELS_DIR / c["slug"]
            onnx_path = Path(hf_hub_download(c["repo"], c["onnx"], local_dir=local))
            data_name = c["onnx"] + "_data"
            if any(f["name"] == data_name for f in entry["files"]):
                hf_hub_download(c["repo"], data_name, local_dir=local)
                entry["onnx_data_mb"] = round((local / data_name).stat().st_size / 1e6, 1)
            entry["download_s"] = round(time.time() - t0, 1)
            entry["onnx_mb"] = round(onnx_path.stat().st_size / 1e6, 1)
            sess = ort.InferenceSession(str(onnx_path), providers=["CPUExecutionProvider"])
            entry["inputs"] = [{"name": i.name, "type": i.type, "shape": [str(s) for s in i.shape]} for i in sess.get_inputs()]
            entry["outputs"] = [{"name": o.name, "type": o.type, "shape": [str(s) for s in o.shape]} for o in sess.get_outputs()]

            sample = [c["query"].format(q="what does my lease say about notice"),
                      c["doc"].format(title="Tenancy Agreement", text="Either party may end this agreement by giving three months written notice."),
                      c["doc"].format(title="Groundnut Soup", text="Boil the chicken with onion and ginger."),
                      c["query"].format(q="power bill"),
                      c["doc"].format(title="Prepaid Electricity Receipt", text="Units purchased: 125.4 kWh"),
                      c["query"].format(q="Réunion des parents")]
            vecs = []
            names = [i.name for i in sess.get_inputs()]
            run_ms = []
            for s in sample:
                e = tok([s], return_tensors="np", truncation=True, max_length=512)
                feed = {}
                for n in names:
                    if n == "token_type_ids":
                        feed[n] = np.zeros_like(e["input_ids"], dtype=np.int64)
                    else:
                        feed[n] = e[n].astype(np.int64)
                t1 = time.time()
                outs = sess.run(None, feed)
                run_ms.append((time.time() - t1) * 1000)
                out_names = [o.name for o in sess.get_outputs()]
                if c["pooling"] == "sentence_embedding" and "sentence_embedding" in out_names:
                    v = outs[out_names.index("sentence_embedding")][0]
                else:
                    hidden = outs[0][0]
                    mask = e["attention_mask"][0][:, None].astype(np.float32)
                    v = (hidden * mask).sum(0) / mask.sum()
                v = v / np.linalg.norm(v)
                vecs.append(v)
            entry["onnx_ms_per_text_ci"] = round(float(np.median(run_ms)), 1)

            from sentence_transformers import SentenceTransformer
            st = SentenceTransformer(c["st_id"], device="cpu")
            ref = st.encode(sample, prompt="", normalize_embeddings=True, convert_to_numpy=True)
            cos = [float(np.dot(a, b)) for a, b in zip(vecs, ref)]
            entry["onnx_vs_sentence_transformers_cosine"] = [round(x, 4) for x in cos]
            reference[c["slug"]] = {
                "texts": sample,
                "vectors": [[round(float(x), 6) for x in v] for v in vecs],
                "dimensions": int(len(vecs[0])),
            }
        except Exception as e:
            entry["onnx_error"] = f"{type(e).__name__}: {str(e)[:400]}"
            print(entry["onnx_error"])

    (OUT / "model_probe.json").write_text(json.dumps(probe, indent=2, ensure_ascii=False))
    (OUT / "tokenizer_fixtures.json").write_text(json.dumps(fixtures, ensure_ascii=False))
    (OUT / "model_reference.json").write_text(json.dumps(reference))

    lines = ["# Model probe", ""]
    for slug, e in probe["models"].items():
        lines.append(f"## {slug} ({e['repo']})")
        for k in ("gated", "tokenizer_class", "fixture_count", "onnx_mb", "onnx_data_mb", "download_s", "onnx_ms_per_text_ci",
                  "onnx_vs_sentence_transformers_cosine", "error", "onnx_error"):
            if k in e:
                lines.append(f"- {k}: {e[k]}")
        lines.append(f"- inputs: {e.get('inputs')}")
        lines.append(f"- outputs: {e.get('outputs')}")
        lines.append("- files: " + ", ".join(f"{f['name']} ({f['mb']} MB)" for f in e.get("files", [])))
        lines.append("")
    (OUT / "model_probe.md").write_text("\n".join(lines))
    print("\n".join(lines))
    return 0


if __name__ == "__main__":
    sys.exit(main())
