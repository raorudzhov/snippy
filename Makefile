# Snippy — a menu bar snippet manager for macOS.
#
# Usage:
#   make                 Build the Debug app as ./snippy.app
#   make release         Build the Release app as ./snippy.app
#   make run             Build and launch the app
#   make test            Run the Debug-only SwiftData self-test
#   make clean           Remove ./snippy.app and the temporary build directory
#   make help            Show available targets and variables
#
# Variables:
#   CONFIG           Debug (default) or Release
#   DERIVED_DATA     Temporary build directory (default: build)
#   DEVELOPMENT_TEAM Apple Developer team ID for signing (optional)
#   XCODEBUILD_FLAGS Extra arguments for xcodebuild
#
# Builds are staged in DERIVED_DATA, copied to ./snippy.app, and the staging
# directory is removed afterwards. Without DEVELOPMENT_TEAM, xcodebuild signs
# the app to run locally (ad-hoc), which is enough for development.
# See README.md for toolchain requirements.

APP_NAME         := snippy
APP_BUNDLE       := $(APP_NAME).app
PROJECT          := snippy.xcodeproj
SCHEME           := snippy
CONFIG           ?= Debug
DERIVED_DATA     ?= build
DEVELOPMENT_TEAM ?=
XCODEBUILD_FLAGS ?=

PRODUCT               = $(DERIVED_DATA)/Build/Products/$(CONFIG)/$(APP_NAME).app
DEVELOPMENT_TEAM_FLAG = $(if $(strip $(DEVELOPMENT_TEAM)),DEVELOPMENT_TEAM=$(strip $(DEVELOPMENT_TEAM)))
XCODEBUILD            = xcodebuild -project "$(PROJECT)" -scheme "$(SCHEME)" \
	-derivedDataPath "$(DERIVED_DATA)" $(DEVELOPMENT_TEAM_FLAG) $(XCODEBUILD_FLAGS)

.DEFAULT_GOAL := build
.PHONY: build release run test clean help

build: ## Build the app and place it at ./snippy.app (Debug by default)
	@echo "==> Building $(APP_NAME) ($(CONFIG))"
	@$(XCODEBUILD) -configuration "$(CONFIG)" build
	@rm -rf "$(APP_BUNDLE)"
	@ditto "$(PRODUCT)" "$(APP_BUNDLE)"
	@rm -rf "$(DERIVED_DATA)"
	@echo "==> Built $(APP_BUNDLE)"

release: CONFIG := Release
release: build ## Build the app in Release at ./snippy.app

run: build ## Build and launch the app
	@echo "==> Launching $(APP_BUNDLE)"
	@open "$(APP_BUNDLE)"

test: override CONFIG := Debug
test: build ## Run the Debug-only SwiftData self-test
	@"$(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)" --self-test

clean: ## Remove ./snippy.app and the temporary build directory
	@echo "==> Cleaning $(APP_BUNDLE) and $(DERIVED_DATA)"
	@$(XCODEBUILD) clean
	@rm -rf "$(DERIVED_DATA)" "$(APP_BUNDLE)"

help: ## Show this help
	@echo "Snippy build targets:"
	@echo
	@awk 'BEGIN {FS = ":.*## "} /^[a-zA-Z0-9_-]+:.*## / {printf "  make %-10s %s\n", $$1, $$2}' $(MAKEFILE_LIST)
	@echo
	@echo "Variables:"
	@echo "  CONFIG=$(CONFIG)"
	@echo "  DERIVED_DATA=$(DERIVED_DATA)"
	@echo "  DEVELOPMENT_TEAM=$(if $(strip $(DEVELOPMENT_TEAM)),$(DEVELOPMENT_TEAM),<unset: ad-hoc signing>)"
	@echo "  XCODEBUILD_FLAGS=$(XCODEBUILD_FLAGS)"
