.PHONY: help bootstrap lint test check

help:
	@echo "Available targets:"
	@echo "  make bootstrap  Initialize submodules and verify dev dependencies"
	@echo "  make lint       Run shell linting on Ferry-owned shell code"
	@echo "  make test       Run the Ferry test suite"
	@echo "  make check      Run lint + test"

bootstrap:
	@./scripts/bootstrap-dev.sh

lint:
	@./scripts/lint.sh

test:
	@./scripts/test.sh

check: lint test
