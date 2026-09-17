.PHONY: all ci test lint verify

all: ci

# CI workflow target: executes fast verification gate and statistical test suite
ci: lint test
	@echo "=== CI Passed Successfully ==="

# Run fast static verification linters
lint:
	python3 tools/verify_gate.py --fast

# Run quick simulation regression test harness
test:
	python3 tools/test_quick_sim.py

# Full pre-turn verification battery
verify:
	python3 tools/verify_gate.py --full
