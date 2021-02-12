SHELL = /bin/bash
.SHELLFLAGS := -eu -o pipefail -c

MAKEFLAGS += --warn-undefined-variables
MAKEFLAGS += --no-builtin-rules

SHELLCHECK_VERSION := 0.7.1
ECLINT_VERSION     := 2.3.1

.PHONY: all

# -->                   -->                   --> DEFAULT

all:
	@ ./scripts/init-poolsrv.sh

# -->                   -->                   --> TESTS

lint: eclint shellcheck

eclint:
	@ ./scripts/tests/eclint.sh

shellcheck:
	@ ./scripts/tests/shellcheck.sh

install_linters:
	@ sudo curl -S -L \
		"https://github.com/hadolint/hadolint/releases/download/v$(HADOLINT_VERSION)/hadolint-$(shell uname -s)-$(shell uname -m)" -o /usr/local/bin/hadolint
	@ sudo curl -S -L \
		"https://github.com/koalaman/shellcheck/releases/download/v$(SHELLCHECK_VERSION)/shellcheck-v$(SHELLCHECK_VERSION).linux.x86_64.tar.xz" | tar -xJ
	@ sudo curl -S -L \
		"https://github.com/editorconfig-checker/editorconfig-checker/releases/download/$(ECLINT_VERSION)/ec-linux-amd64.tar.gz" | tar -xaz
	@ sudo chmod +rx /usr/local/bin/hadolint
	@ sudo mv "shellcheck-v$(SHELLCHECK_VERSION)/shellcheck" /usr/bin/
	@ sudo mv bin/ec-linux-amd64 /usr/bin/eclint
	@ sudo chmod +x /usr/bin/eclint
	@ sudo rm -rf "shellcheck-v$(SHELLCHECK_VERSION)" bin
