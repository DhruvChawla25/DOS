SCRIPTS := $(shell find scripts -name '*.sh')

.PHONY: check
check:
	shellcheck -x $(SCRIPTS)
