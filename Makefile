# Makefile for hide-comment development

.PHONY: help test doc lint format check install

help:
	@echo "Available targets:"
	@echo "  test     - Run all tests"
	@echo "  doc      - Generate documentation"
	@echo "  lint     - Run linting (requires stylua)"
	@echo "  format   - Format code (requires stylua)"
	@echo "  check    - Run all checks (test + lint)"

test:
	@echo "Running tests..."
	nvim --headless -u scripts/minimal_init.lua -l scripts/run_tests.lua

doc:
	@echo "Generating documentation..."
	nvim --headless -u scripts/minimal_init.lua -l scripts/gen_doc.lua

lint:
	@echo "Linting code..."
	stylua --check lua/ tests/ scripts/

format:
	@echo "Formatting code..."
	stylua lua/ tests/ scripts/

check: test lint
