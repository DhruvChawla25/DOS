# Shell files ShellCheck covers (run from the repo root: some modules use
# `# shellcheck source=lib/dos.sh`). Missing directories are skipped.
# scripts/dos-update is a symlink to the rootfs copy (find -L follows it).
SCRIPTS := $(sort $(shell find lib modules tests iso/airootfs/usr/share/dos/rootfs -type f -name '*.sh' 2>/dev/null) \
             $(shell find -L commands scripts iso/airootfs/usr/local/bin iso/airootfs/usr/share/dos/rootfs/usr/local/bin -type f 2>/dev/null))

.PHONY: check shellcheck contract test-install test-modules list-scripts

## check: ShellCheck every script, then the module/command contract
check: shellcheck contract

shellcheck:
	shellcheck -x $(SCRIPTS)

contract:
	bash tests/check-contract.sh

## test-install: dos-install safety test on loop devices (Linux, root)
test-install:
	sudo bash tests/install-safety.sh

## test-modules: run every module as you with DOS_TEST=1
test-modules:
	bash tests/run-modules.sh

list-scripts:
	@printf '%s\n' $(SCRIPTS)
