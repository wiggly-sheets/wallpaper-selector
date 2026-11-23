# Wallpaper Selector — build interface.
#
# `make` prints the list of targets. Every target is phony.

APP_NAME := Wallpaper Selector
PRODUCT_NAME := WallpaperSelector
CONFIGURATION ?= debug
# The version of a release comes from the command line: `make release VERSION=1.2.3`.
# A build without a version uses the placeholder below. The placeholder is not a
# release version, and a build that carries it must never be published.
LOCAL_VERSION := 0.0.0-local
VERSION ?= $(LOCAL_VERSION)
BUILD_NUMBER ?= 1
DIST_DIR := dist
# Each architecture builds in a scratch path of its own, so a build of one
# architecture never overwrites the product of the other one.
ARM_ARCH := arm64
INTEL_ARCH := x86_64
ARM_SCRATCH := .build/$(ARM_ARCH)
INTEL_SCRATCH := .build/$(INTEL_ARCH)
ARCHS := $(ARM_ARCH) $(INTEL_ARCH)
ARM_BUNDLE := $(DIST_DIR)/$(APP_NAME)-$(ARM_ARCH).app
INTEL_BUNDLE := $(DIST_DIR)/$(APP_NAME)-$(INTEL_ARCH).app
INSTALL_DIR ?= $(HOME)/Applications
INSTALL_APP := $(INSTALL_DIR)/$(APP_NAME).app
RELEASE_DIR := release
ARM_DMG := $(RELEASE_DIR)/$(PRODUCT_NAME)-$(VERSION)-$(ARM_ARCH).dmg
INTEL_DMG := $(RELEASE_DIR)/$(PRODUCT_NAME)-$(VERSION)-$(INTEL_ARCH).dmg
DMGS := $(ARM_DMG) $(INTEL_DMG)
CHECKSUMS := $(RELEASE_DIR)/checksums.txt
STAGING_DIR := $(RELEASE_DIR)/staging
CREATE_DMG ?= create-dmg
CREATE_DMG_FINALIZE_FLAGS ?= --skip-finalize
DMG_BACKGROUND := Support/Installer/dmg-background.png
DMG_ICON := SwiftWallpaperSelector/Sources/WallpaperSelector/Resources/AppIcon.icns

# The version of a release comes from the command line or from the environment,
# never from a file in the repository. The default of the Makefile is a
# placeholder, so a release without a version has nothing to release.
ifneq ($(filter command line environment,$(origin VERSION)),)
RELEASE_VERSION := $(VERSION)
else
RELEASE_VERSION :=
endif

# `install` and `run` copy the bundle of the host architecture.
ifeq ($(shell uname -m),$(INTEL_ARCH))
HOST_BUNDLE := $(INTEL_BUNDLE)
HOST_TARGET := app-intel
else
HOST_BUNDLE := $(ARM_BUNDLE)
HOST_TARGET := app-arm
endif

.PHONY: help build build-arm build-intel test verify app app-arm app-intel \
	install run dmg dmg-arm dmg-intel release-artifacts release-notes release \
	clean

.DEFAULT_GOAL := help

## help — list every target

help:
	@printf '%s\n' \
		'Wallpaper Selector — build targets.' \
		'' \
		'  help                  List every target (default).' \
		'  build                 Build the Swift package for arm64 and x86_64.' \
		'  build-arm             Build the Swift package for arm64.' \
		'  build-intel           Build the Swift package for x86_64.' \
		'  test                  Run the changelog check and the SwiftPM test suite.' \
		'  verify                Check both bundles: architecture, SDK, version and signature.' \
		'  app                   Build both app bundles into dist/.' \
		'  app-arm               Build the arm64 bundle into dist/Wallpaper Selector-arm64.app.' \
		'  app-intel             Build the x86_64 bundle into dist/Wallpaper Selector-x86_64.app.' \
		'  dmg                   Build both disk images into release/.' \
		'  dmg-arm               Build release/WallpaperSelector-<version>-arm64.dmg.' \
		'  dmg-intel             Build release/WallpaperSelector-<version>-x86_64.dmg.' \
		'  release-artifacts     Build both disk images and release/checksums.txt, then verify it.' \
		'  release-notes VERSION=x.y.z  Print the changelog section of a version.' \
		'  release VERSION=x.y.z  Bump the changelog, test, build, verify, commit and tag.' \
		'  install               Copy the host architecture bundle into ~/Applications.' \
		'  run                   Install the host architecture bundle and launch it.' \
		'  clean                 Remove .build/, dist/ and release/.' \
		'' \
		'Notes' \
		'  The app ships for Apple silicon and for Intel, one bundle per architecture.' \
		'  The version of a release comes from the command line: make release VERSION=1.2.3.' \
		'  A build without a version uses 0.0.0-local. That version is a placeholder for a' \
		'  local dry run, and a build that carries it must never be published.' \
		'  The release publishes WallpaperSelector-<version>-arm64.dmg,' \
		'  WallpaperSelector-<version>-x86_64.dmg and checksums.txt. The names must not' \
		'  change, because the Homebrew tap matches the assets by name.' \
		'  The checksum file holds one line per asset: the digest, two spaces, the bare file name.' \
		'  CHANGELOG.md follows the shared shape: an [Unreleased] section with Added, Changed,' \
		'  Deprecated, Removed, Fixed or Security headings. `make test` checks it.' \
		'  `make release` refuses a dirty working tree and a version whose tag already exists.' \
		'  It moves [Unreleased] to the version, runs the tests, builds and verifies the' \
		'  artifacts, commits the bump, creates the annotated tag and prints the push' \
		'  commands. It never pushes.' \
		'  Signing stays ad-hoc: identity "-", no certificate, no notarization.' \
		'  create-dmg is needed for the dmg targets: brew install create-dmg.'

## build — build the package for both architectures

build: build-arm build-intel

## build-arm — build the package for Apple silicon

build-arm:
	swift build -c $(CONFIGURATION) --arch $(ARM_ARCH) --scratch-path $(ARM_SCRATCH)

## build-intel — build the package for Intel

build-intel:
	swift build -c $(CONFIGURATION) --arch $(INTEL_ARCH) --scratch-path $(INTEL_SCRATCH)

## test — the test suite

test:
	./scripts/changelog.sh check
	swift test

## verify — check the built bundles

verify:
	@for arch in $(ARCHS); do \
		bundle="$(DIST_DIR)/$(APP_NAME)-$$arch.app"; \
		if [ ! -d "$$bundle" ]; then \
			echo "error: $$bundle is missing. Run make app first."; \
			exit 1; \
		fi; \
		binary="$$bundle/Contents/MacOS/$(PRODUCT_NAME)"; \
		archs="$$(lipo -archs "$$binary")"; \
		echo "$$bundle architectures: $$archs"; \
		if [ "$$archs" != "$$arch" ]; then \
			echo "error: expected a $$arch binary in $$bundle, got $$archs."; \
			exit 1; \
		fi; \
		sdk="$$(vtool -show-build "$$binary" | awk '$$1 == "sdk" { print $$2; exit }')"; \
		echo "$$bundle recorded SDK: $${sdk:-none}"; \
		if [ -z "$$sdk" ]; then \
			echo "error: $$binary records no SDK version."; \
			exit 1; \
		fi; \
		if ! awk -v sdk="$$sdk" 'BEGIN { exit !(sdk + 0 >= 26.0) }'; then \
			echo "error: $$binary records SDK $$sdk; Liquid Glass needs 26.0 or newer."; \
			exit 1; \
		fi; \
		version="$$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$$bundle/Contents/Info.plist")"; \
		echo "$$bundle version: $$version (expected $(VERSION))"; \
		if [ "$$version" != "$(VERSION)" ]; then \
			echo "error: $$bundle reports $$version, but $(VERSION) was expected."; \
			exit 1; \
		fi; \
		codesign --verify --deep --strict "$$bundle"; \
	done
	@echo "Verified every bundle under $(DIST_DIR)/."

# build_bundle BUNDLE ARCH SCRATCH — build one app bundle of one architecture.
define build_bundle
	rm -rf "$(1)"
	mkdir -p "$(1)/Contents/MacOS" "$(1)/Contents/Resources"
	cp "$$(swift build -c $(CONFIGURATION) --arch $(2) --scratch-path $(3) --show-bin-path)/$(PRODUCT_NAME)" "$(1)/Contents/MacOS/$(PRODUCT_NAME)"
	cp Support/Info.plist "$(1)/Contents/Info.plist"
	/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $(VERSION)" "$(1)/Contents/Info.plist"
	/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $(BUILD_NUMBER)" "$(1)/Contents/Info.plist"
	cp SwiftWallpaperSelector/Sources/WallpaperSelector/Resources/AppIcon.icns "$(1)/Contents/Resources/AppIcon.icns"
	cp -R "$$(swift build -c $(CONFIGURATION) --arch $(2) --scratch-path $(3) --show-bin-path)"/$(PRODUCT_NAME)_*.bundle "$(1)/Contents/Resources/"
	codesign --force --sign - "$(1)"
endef

## app — the bundles the product ships

app: app-arm app-intel

## app-arm — the bundle for Apple silicon

app-arm: build-arm
	$(call build_bundle,$(ARM_BUNDLE),$(ARM_ARCH),$(ARM_SCRATCH))

## app-intel — the bundle for Intel

app-intel: build-intel
	$(call build_bundle,$(INTEL_BUNDLE),$(INTEL_ARCH),$(INTEL_SCRATCH))

## install — copy the bundle of the host architecture into the applications folder

install: $(HOST_TARGET)
	mkdir -p "$(INSTALL_DIR)"
	rm -rf "$(INSTALL_APP)"
	cp -R "$(HOST_BUNDLE)" "$(INSTALL_APP)"

## run — install the bundle of the host architecture and launch it

run: install
	open "$(INSTALL_APP)"

# build_dmg BUNDLE DMG STAGING — pack one app bundle into one disk image.
define build_dmg
	rm -rf "$(3)" "$(2)"
	mkdir -p "$(3)"
	cp -R "$(1)" "$(3)/$(APP_NAME).app"
	$(CREATE_DMG) --volname "$(APP_NAME)" --volicon "$(DMG_ICON)" --background "$(DMG_BACKGROUND)" --window-size 660 440 --icon-size 110 --text-size 12 --icon "$(APP_NAME).app" 170 250 --app-drop-link 490 250 --hide-extension "$(APP_NAME).app" --no-internet-enable $(CREATE_DMG_FINALIZE_FLAGS) "$(2)" "$(3)"
	if [ -n "$(CREATE_DMG_FINALIZE_FLAGS)" ]; then hdiutil convert "$(2)" -format UDZO -o "$(2).final"; mv "$(2).final.dmg" "$(2)"; fi
endef

## dmg — the disk images

dmg: CONFIGURATION := release
dmg: dmg-arm dmg-intel

## dmg-arm — the disk image for Apple silicon

dmg-arm: CONFIGURATION := release
dmg-arm: app-arm
	$(call build_dmg,$(ARM_BUNDLE),$(ARM_DMG),$(STAGING_DIR)-$(ARM_ARCH))

## dmg-intel — the disk image for Intel

dmg-intel: CONFIGURATION := release
dmg-intel: app-intel
	$(call build_dmg,$(INTEL_BUNDLE),$(INTEL_DMG),$(STAGING_DIR)-$(INTEL_ARCH))

## release-artifacts — the disk images and the checksum file the tap expects

release-artifacts: dmg
	cd "$(RELEASE_DIR)" && shasum -a 256 $(notdir $(DMGS)) > $(notdir $(CHECKSUMS))
	@cd "$(RELEASE_DIR)" && shasum -a 256 -c $(notdir $(CHECKSUMS))
	@echo "Wrote $(DMGS) and $(CHECKSUMS)"

## release-notes — print the changelog section of a version

release-notes:
	@if [ -z "$(strip $(RELEASE_VERSION))" ]; then \
		echo "error: make release-notes needs a version, for example: make release-notes VERSION=1.2.3"; \
		exit 1; \
	fi
	@./scripts/changelog.sh notes "$(RELEASE_VERSION)"

## release — bump, test, build, verify, commit and tag, without pushing

release:
	@if [ -z "$(strip $(RELEASE_VERSION))" ]; then \
		echo "error: make release needs a version on the command line, for example:"; \
		echo "       make release VERSION=1.2.3"; \
		exit 1; \
	fi
	@APP_NAME="$(APP_NAME)" ./scripts/release.sh "$(RELEASE_VERSION)"

## clean — remove everything the build produces

clean:
	rm -rf .build "$(DIST_DIR)" "$(RELEASE_DIR)"
	@echo "Removed .build/, $(DIST_DIR)/ and $(RELEASE_DIR)/."
