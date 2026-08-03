include VERSIONS

TARGET ?= $(CURDIR)/build
BUILD_DIR := $(TARGET)
SRC_DIR := $(BUILD_DIR)/spbm-$(SPBM_UPSTREAM)

BUILD_DIST := $(shell lsb_release -sc 2>/dev/null || echo noble)

# The key debsign signs with. GPG_KEY_ID is exported by CI after importing.
SIGNING_KEY ?= $(if $(GPG_KEY_ID),$(GPG_KEY_ID),vladtemian@gmail.com)

# Reproducible tarballs need GNU tar. macOS ships bsdtar, which rejects these
# flags, so they are only applied when GNU tar is what is actually running.
# CI is Ubuntu, so the archive Launchpad sees is always the reproducible one.
#
# The mtime is the upstream commit date rather than the epoch. dh_install
# preserves mtimes into the .deb, and Launchpad rejects a binary holding any
# file dated before 1975 — see SPBM_COMMIT_EPOCH in VERSIONS.
TAR ?= $(shell command -v gtar 2>/dev/null || echo tar)
TAR_REPRO := $(shell $(TAR) --version 2>/dev/null | grep -q GNU \
	&& echo "--sort=name --mtime=@$(SPBM_COMMIT_EPOCH) --owner=0 --group=0 --numeric-owner")

ifdef GITHUB_REF_TYPE
ifeq ($(GITHUB_REF_TYPE),tag)
	BUILD_VERSION ?= ~ppa$(GITHUB_REF_NAME:v%=%)
else
	BUILD_VERSION ?= ~ppa$(GITHUB_RUN_NUMBER)+$(GITHUB_REF_NAME)
endif
else
	BUILD_VERSION ?= $(shell date +'~ppa%Y%m%d+%H%M%S')
endif

DEB_VERSION := $(SPBM_UPSTREAM)-$(BUILD_DIST)$(BUILD_VERSION)

.DEFAULT_GOAL := help

.PHONY: help fetch prepare source deb clean

help: ## Show this help
	@grep -hE '^[a-z-]+:.*?## ' $(MAKEFILE_LIST) | awk -F':.*?## ' '{printf "  \033[36m%-10s\033[0m %s\n", $$1, $$2}'

fetch: $(BUILD_DIR)/spbm.tar.gz ## Download the pinned upstream source

$(BUILD_DIR)/spbm.tar.gz:
	mkdir -p $(BUILD_DIR)
	curl -fsSL '$(SPBM_URL)' -o $@

prepare: fetch ## Unpack upstream and lay the debian/ directory over it
	rm -rf $(SRC_DIR)
	mkdir -p $(SRC_DIR)
	tar -xzf $(BUILD_DIR)/spbm.tar.gz -C $(SRC_DIR) --strip-components=1
	# Repack as an orig tarball before debian/ exists. `3.0 (quilt)` requires
	# one for a source build, and it must not contain debian/ — GitHub's own
	# archive cannot be used directly because its top-level directory is named
	# after the commit rather than <package>-<version>.
	$(TAR) $(TAR_REPRO) \
		-czf $(BUILD_DIR)/spbm_$(SPBM_UPSTREAM).orig.tar.gz \
		-C $(BUILD_DIR) spbm-$(SPBM_UPSTREAM)
	cp -r debian-spbm $(SRC_DIR)/debian
	sed -i.bak '1s|.*|spbm ($(DEB_VERSION)) $(BUILD_DIST); urgency=low|' \
		$(SRC_DIR)/debian/changelog && rm -f $(SRC_DIR)/debian/changelog.bak
	@echo "  prepared $(SRC_DIR) as $(DEB_VERSION)"

deb: prepare ## Build the binary package (needs a Debian/Ubuntu host)
	cd $(SRC_DIR) && dpkg-buildpackage -us -uc -b
	@ls -1 $(BUILD_DIR)/*.deb 2>/dev/null | sed 's|^|  built |'

# Build unsigned, then sign as a separate step. debuild signs inline via gpg,
# which insists on a tty; splitting it lets debsign use a wrapper that supplies
# the passphrase from the environment.
source: prepare ## Build a signed source package for dput to a PPA
	cd $(SRC_DIR) && dpkg-buildpackage -d -S -sa -us -uc
	cd $(BUILD_DIR) && debsign -p $(CURDIR)/gpg-batch-wrapper.sh \
		--no-re-sign -k $(SIGNING_KEY) spbm_$(DEB_VERSION)_source.changes

clean: ## Remove everything built
	rm -rf $(BUILD_DIR)
