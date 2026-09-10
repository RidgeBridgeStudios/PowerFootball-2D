# Graphify Knowledge Graph Setup

## Installation
pip install graphifyy

## Initialization
graphify . --output graphify-out/graph.json

## Query Commands
- `graphify query "<symbol>"` - Find symbol and dependencies
- `graphify path <source> <target>` - Find dependency path
- `graphify explain <node>` - Explain node relationships

## Refresh
Run `graphify .` after major refactors to update the graph.