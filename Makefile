.PHONY: build test bundle run check
build:
	bash scripts/build.sh
test:
	bash scripts/build.sh --test
bundle:
	bash scripts/bundle.sh
run: bundle
	open "dist/ChatGPT Usage.app"
check: build
	.build/direct/ChatGPTUsage --check
