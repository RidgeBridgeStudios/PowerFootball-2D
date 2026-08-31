---
description: Context window hygiene and token conservation rules
---

# Context Hygiene & Token Discipline

1. Use targeted slicing (`tools/codebase_slice.py`) instead of reading whole multi-thousand line files.
2. Query the semantic index (`tools/semantic_search.py`) for specific topics.
3. Compute blast radius (`tools/dump_dep_graph.py --blast-radius <file>`) prior to modifying shared entities or autoloads.
4. Keep session logs compact (`tools/compact_errata.py`).
