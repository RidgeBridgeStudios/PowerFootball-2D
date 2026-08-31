#!/usr/bin/env python3
"""
semantic_search.py — Zero-Dependency Local BM25 Knowledge Retrieval Tool.

Indexes all repository Markdown files (specs, rules, architectures, roadmaps) and GDScript
docstrings into an in-memory BM25 index, returning the top 3 most relevant context snippets
for any query.

Usage:
    python tools/semantic_search.py "defensive line depth"
    python tools/semantic_search.py --top-k 5 "pseudo 3d ball physics"
"""

from __future__ import annotations

import argparse
import math
import os
import re
import sys
from typing import Dict, List, Set, Tuple

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

STOPWORDS = {
    "a", "about", "above", "after", "again", "against", "all", "am", "an", "and", "any", "are",
    "as", "at", "be", "because", "been", "before", "being", "below", "between", "both", "but", "by",
    "could", "did", "do", "does", "doing", "down", "during", "each", "few", "for", "from", "further",
    "had", "has", "have", "having", "he", "her", "here", "hers", "herself", "him", "himself", "his",
    "how", "i", "if", "in", "into", "is", "it", "its", "itself", "just", "me", "more", "most", "my",
    "myself", "no", "nor", "not", "of", "off", "on", "once", "only", "or", "other", "ought", "our",
    "ours", "ourselves", "out", "over", "own", "same", "she", "should", "so", "some", "such", "than",
    "that", "the", "their", "theirs", "them", "themselves", "then", "there", "these", "they", "this",
    "those", "through", "to", "too", "under", "until", "up", "very", "was", "we", "were", "what",
    "when", "where", "which", "while", "who", "whom", "why", "with", "would", "you", "your", "yours",
    "yourself", "yourselves",
}


def tokenize(text: str) -> list[str]:
    words = re.findall(r"[a-zA-Z0-9_]+", text.lower())
    return [w for w in words if w not in STOPWORDS and len(w) > 1]


class DocumentChunk:
    __slots__ = ("file_path", "start_line", "end_line", "title", "content", "tokens", "token_counts")

    def __init__(self, file_path: str, start_line: int, end_line: int, title: str, content: str) -> None:
        self.file_path = file_path
        self.start_line = start_line
        self.end_line = end_line
        self.title = title
        self.content = content
        self.tokens = tokenize(content + " " + title)
        self.token_counts: dict[str, int] = {}
        for t in self.tokens:
            self.token_counts[t] = self.token_counts.get(t, 0) + 1


def chunk_markdown_file(filepath: str) -> list[DocumentChunk]:
    chunks: list[DocumentChunk] = []
    rel_path = os.path.relpath(filepath, ROOT).replace("\\", "/")

    with open(filepath, "r", encoding="utf-8", errors="replace") as f:
        lines = f.readlines()

    current_title = os.path.basename(filepath)
    current_lines: list[str] = []
    start_line = 1

    for idx, line in enumerate(lines, start=1):
        if line.startswith("# ") or line.startswith("## ") or line.startswith("### "):
            if current_lines:
                chunk_text = "".join(current_lines).strip()
                if len(chunk_text) > 30:
                    chunks.append(DocumentChunk(rel_path, start_line, idx - 1, current_title, chunk_text))
            current_title = line.strip().lstrip("#").strip()
            current_lines = [line]
            start_line = idx
        else:
            current_lines.append(line)

    if current_lines:
        chunk_text = "".join(current_lines).strip()
        if len(chunk_text) > 30:
            chunks.append(DocumentChunk(rel_path, start_line, len(lines), current_title, chunk_text))

    return chunks


def chunk_gdscript_docstrings(filepath: str) -> list[DocumentChunk]:
    chunks: list[DocumentChunk] = []
    rel_path = os.path.relpath(filepath, ROOT).replace("\\", "/")

    with open(filepath, "r", encoding="utf-8", errors="replace") as f:
        lines = f.readlines()

    current_doc: list[str] = []
    start_line = 0

    for idx, line in enumerate(lines, start=1):
        stripped = line.strip()
        if stripped.startswith("##"):
            if not current_doc:
                start_line = idx
            current_doc.append(stripped.lstrip("#").strip())
        elif current_doc:
            doc_text = " ".join(current_doc).strip()
            if len(doc_text) > 40:
                header = f"{os.path.basename(filepath)} (Line {start_line})"
                chunks.append(DocumentChunk(rel_path, start_line, idx - 1, header, doc_text))
            current_doc = []

    return chunks


class BM25Index:

    def __init__(self, chunks: list[DocumentChunk], k1: float = 1.5, b: float = 0.75) -> None:
        self.chunks = chunks
        self.k1 = k1
        self.b = b
        self.num_docs = len(chunks)
        self.avg_doc_len = sum(len(c.tokens) for c in chunks) / max(self.num_docs, 1)

        # Document frequencies
        self.df: dict[str, int] = {}
        for c in chunks:
            for term in c.token_counts.keys():
                self.df[term] = self.df.get(term, 0) + 1

        # Inverse Document Frequency (IDF)
        self.idf: dict[str, float] = {}
        for term, freq in self.df.items():
            # Standard Lucene/BM25 IDF formula
            self.idf[term] = math.log(1.0 + (self.num_docs - freq + 0.5) / (freq + 0.5))

    def query(self, query_str: str, top_k: int = 3) -> list[tuple[float, DocumentChunk]]:
        q_tokens = tokenize(query_str)
        if not q_tokens:
            return []

        scores: list[tuple[float, DocumentChunk]] = []

        for chunk in self.chunks:
            score = 0.0
            doc_len = len(chunk.tokens)
            len_norm = 1.0 - self.b + self.b * (doc_len / self.avg_doc_len)

            for qt in q_tokens:
                if qt not in chunk.token_counts:
                    continue
                tf = chunk.token_counts[qt]
                idf = self.idf.get(qt, 0.0)
                numerator = tf * (self.k1 + 1.0)
                denominator = tf + self.k1 * len_norm
                score += idf * (numerator / denominator)

            if score > 0.0:
                scores.append((score, chunk))

        scores.sort(key=lambda x: x[0], reverse=True)
        return scores[:top_k]


def build_corpus() -> list[DocumentChunk]:
    corpus: list[DocumentChunk] = []

    for dirpath, dirnames, filenames in os.walk(ROOT):
        dirnames[:] = [d for d in dirnames if not d.startswith(".")]
        for f in filenames:
            ext = os.path.splitext(f)[1].lower()
            fullpath = os.path.join(dirpath, f)
            if ext == ".md":
                corpus.extend(chunk_markdown_file(fullpath))
            elif ext == ".gd":
                corpus.extend(chunk_gdscript_docstrings(fullpath))

    # Also include .claude and .antigravity markdown files
    for hidden_dir in [".claude", ".antigravity"]:
        hidden_path = os.path.join(ROOT, hidden_dir)
        if os.path.isdir(hidden_path):
            for dirpath, _, filenames in os.walk(hidden_path):
                for f in filenames:
                    if f.endswith(".md"):
                        corpus.extend(chunk_markdown_file(os.path.join(dirpath, f)))

    return corpus


def main() -> int:
    parser = argparse.ArgumentParser(description="BM25 Semantic Retrieval for Rules & Codebase Specs.")
    parser.add_argument("query", nargs="+", help="Keyword or natural language query.")
    parser.add_argument("--top-k", type=int, default=3, help="Number of top snippets to return (default: 3).")
    args = parser.parse_args()

    query_str = " ".join(args.query)
    corpus = build_corpus()
    index = BM25Index(corpus)

    results = index.query(query_str, top_k=args.top_k)

    print(f"=== Semantic BM25 Search: '{query_str}' (Corpus: {len(corpus)} snippets) ===\n")

    if not results:
        print("No matching snippets found.")
        return 0

    for rank, (score, chunk) in enumerate(results, start=1):
        print(f"[{rank}] Score: {score:.3f} | {chunk.file_path}:{chunk.start_line}-{chunk.end_line} — {chunk.title}")
        # Format snippet with 4-space indent, max 6 lines preview
        lines = chunk.content.splitlines()
        preview = lines[:6]
        for l in preview:
            print(f"    {l}")
        if len(lines) > 6:
            print(f"    ... ({len(lines) - 6} more lines)")
        print()

    return 0


if __name__ == "__main__":
    sys.exit(main())
