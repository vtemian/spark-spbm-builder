include VERSIONS

TARGET ?= $(CURDIR)/build
BUILD_DIR := $(TARGET)
SRC_DIR := $(BUILD_DIR)/spbm-$(SPBM_VERSION)

BUILD_DIST := $(shell lsb_release -sc 2>/dev/null || echo noble)

ifdef GITHUB_REF_TYPE
ifeq ($(GITHUB_REF_TYPE),tag)
	BUILD_VERSION ?= ~ppa$(GITHUB_REF_NAME:v%=%)
else
	BUILD_VERSION ?= ~ppa$(GITHUB_RUN_NUMBER)+$(GITHUB_REF_NAME)
endif
else
	BUILD_VERSION ?= $(shell date +'~ppa%Y%m%d+%H%M%S')
endif

DEB_VERSION := $(SPBM_VERSION)-$(BUILD_DIST)$(BUILD_VERSION)

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
	tar -czf $(BUILD_DIR)/spbm_$(SPBM_VERSION).orig.tar.gz \
		-C $(BUILD_DIR) spbm-$(SPBM_VERSION)
	cp -r debian-spbm $(SRC_DIR)/debian
	sed -i.bak '1s|.*|spbm ($(DEB_VERSION)) $(BUILD_DIST); urgency=low|' \
		$(SRC_DIR)/debian/changelog && rm -f $(SRC_DIR)/debian/changelog.bak
	@echo "  prepared $(SRC_DIR) as $(DEB_VERSION)"

deb: prepare ## Build the binary package (needs a Debian/Ubuntu host)
	cd $(SRC_DIR) && dpkg-buildpackage -us -uc -b
	@ls -1 $(BUILD_DIR)/*.deb 2>/dev/null | sed 's|^|  built |'

source: prepare ## Build a signed source package for dput to a PPA
	cd $(SRC_DIR) && debuild -S -sa

clean: ## Remove everything built
	rm -rf $(BUILD_DIR)
