SCRIPTS := $(shell find scripts iso -name "*.sh") $(wildcard iso/airootfs/usr/local/bin/*)

.PHONY: check
check:
	shellcheck -x $(SCRIPTS)
