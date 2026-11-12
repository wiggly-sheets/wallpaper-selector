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
APP_BUNDLE := $(DIST_DIR)/$(APP_NAME).app
INSTALL_DIR ?= $(HOME)/Applications
INSTALL_APP := $(INSTALL_DIR)/$(APP_NAME).app
RELEASE_DIR := release
DMG := $(RELEASE_DIR)/$(PRODUCT_NAME)-$(VERSION).dmg
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

.PHONY: help build test verify app install run dmg release-artifacts \
	release-notes release clean

.DEFAULT_GOAL := help

## help — list every target

help:
	@printf '%s\n' \
		'Wallpaper Selector — build targets.' \
		'' \
		'  help                  List every target (default).' \
		'  build                 Build the Swift package in the development configuration.' \
		'  test                  Run the changelog check and the SwiftPM test suite.' \
		'  verify                Check the bundle: architecture, SDK, version and signature.' \
		'  app                   Build the app bundle into dist/Wallpaper Selector.app.' \
		'  dmg                   Build the disk image release/WallpaperSelector-<version>.dmg.' \
		'  release-artifacts     Build the disk image and its checksum file, then verify the checksum.' \
		'  release-notes VERSION=x.y.z  Print the changelog section of a version.' \
		'  release VERSION=x.y.z  Bump the changelog, test, build, verify, commit and tag.' \
		'  install               Copy the app bundle into ~/Applications.' \
		'  run                   Install the app bundle and launch it.' \
		'  clean                 Remove .build/, dist/ and release/.' \
		'' \
		'Notes' \
		'  The product is Apple silicon only, so it offers no per-architecture target.' \
		'  The version of a release comes from the command line: make release VERSION=1.2.3.' \
		'  A build without a version uses 0.0.0-local. That version is a placeholder for a' \
		'  local dry run, and a build that carries it must never be published.' \
		'  The release publishes WallpaperSelector-<version>.dmg and' \
		'  WallpaperSelector-<version>.dmg.sha256. The names must not change, because the' \
		'  Homebrew tap matches the assets by name.' \
		'  The checksum file holds one line per asset: the digest, two spaces, the bare file name.' \
		'  CHANGELOG.md follows the shared shape: an [Unreleased] section with Added, Changed,' \
		'  Deprecated, Removed, Fixed or Security headings. `make test` checks it.' \
		'  `make release` refuses a dirty working tree and a version whose tag already exists.' \
		'  It moves [Unreleased] to the version, runs the tests, builds and verifies the' \
		'  artifacts, commits the bump, creates the annotated tag and prints the push' \
		'  commands. It never pushes.' \
		'  Signing stays ad-hoc: identity "-", no certificate, no notarization.' \
		'  create-dmg is needed for the dmg target: brew install create-dmg.'

## build — build the package in the development configuration

build:
	swift build -c $(CONFIGURATION)

## test — the test suite

test:
	./scripts/changelog.sh check
	swift test

## verify — check the built bundle

verify:
	@test -d "$(APP_BUNDLE)" || { \
		echo "error: $(APP_BUNDLE) is missing. Run make app first."; \
		exit 1; \
	}
	@binary="$(APP_BUNDLE)/Contents/MacOS/$(PRODUCT_NAME)"; \
	archs="$$(lipo -archs "$$binary")"; \
	echo "Architectures: $$archs"; \
	test "$$archs" = "arm64" || { \
		echo "error: expected an arm64 binary, got $$archs."; \
		exit 1; \
	}
	@binary="$(APP_BUNDLE)/Contents/MacOS/$(PRODUCT_NAME)"; \
	sdk="$$(vtool -show-build "$$binary" | awk '$$1 == "sdk" { print $$2; exit }')"; \
	echo "Recorded SDK: $${sdk:-none}"; \
	if [ -z "$$sdk" ]; then \
		echo "error: the binary records no SDK version."; \
		exit 1; \
	fi; \
	awk -v sdk="$$sdk" 'BEGIN { exit !(sdk + 0 >= 26.0) }' || { \
		echo "error: the binary records SDK $$sdk; Liquid Glass needs 26.0 or newer."; \
		exit 1; \
	}
	@version="$$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$(APP_BUNDLE)/Contents/Info.plist")"; \
	echo "Bundle version: $$version (expected $(VERSION))"; \
	test "$$version" = "$(VERSION)" || { \
		echo "error: the bundle reports $$version, but $(VERSION) was expected."; \
		exit 1; \
	}
	codesign --verify --deep --strict "$(APP_BUNDLE)"
	@echo "Verified $(APP_BUNDLE)."

## app — the bundle the product ships

app: build
	rm -rf "$(APP_BUNDLE)"
	mkdir -p "$(APP_BUNDLE)/Contents/MacOS" "$(APP_BUNDLE)/Contents/Resources"
	cp "$(shell swift build -c $(CONFIGURATION) --show-bin-path)/$(PRODUCT_NAME)" "$(APP_BUNDLE)/Contents/MacOS/$(PRODUCT_NAME)"
	cp Support/Info.plist "$(APP_BUNDLE)/Contents/Info.plist"
	/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $(VERSION)" "$(APP_BUNDLE)/Contents/Info.plist"
	/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $(BUILD_NUMBER)" "$(APP_BUNDLE)/Contents/Info.plist"
	cp SwiftWallpaperSelector/Sources/WallpaperSelector/Resources/AppIcon.icns "$(APP_BUNDLE)/Contents/Resources/AppIcon.icns"
	cp -R "$(shell swift build -c $(CONFIGURATION) --show-bin-path)"/$(PRODUCT_NAME)_*.bundle "$(APP_BUNDLE)/Contents/Resources/"
	codesign --force --sign - "$(APP_BUNDLE)"

## install — copy the bundle into the applications folder

install: app
	mkdir -p "$(INSTALL_DIR)"
	rm -rf "$(INSTALL_APP)"
	cp -R "$(APP_BUNDLE)" "$(INSTALL_APP)"

## run — install the bundle and launch it

run: install
	open "$(INSTALL_APP)"

## dmg — the disk image

dmg: CONFIGURATION := release
dmg: app
	rm -rf "$(RELEASE_DIR)"
	mkdir -p "$(STAGING_DIR)"
	cp -R "$(APP_BUNDLE)" "$(STAGING_DIR)/$(APP_NAME).app"
	$(CREATE_DMG) --volname "$(APP_NAME)" --volicon "$(DMG_ICON)" --background "$(DMG_BACKGROUND)" --window-size 660 440 --icon-size 110 --text-size 12 --icon "$(APP_NAME).app" 170 250 --app-drop-link 490 250 --hide-extension "$(APP_NAME).app" --no-internet-enable $(CREATE_DMG_FINALIZE_FLAGS) "$(DMG)" "$(STAGING_DIR)"
	if [ -n "$(CREATE_DMG_FINALIZE_FLAGS)" ]; then hdiutil convert "$(DMG)" -format UDZO -o "$(DMG).final"; mv "$(DMG).final.dmg" "$(DMG)"; fi

## release-artifacts — the disk image and the checksum file the tap expects

release-artifacts: dmg
	cd "$(RELEASE_DIR)" && shasum -a 256 "$(notdir $(DMG))" > "$(notdir $(DMG)).sha256"
	@cd "$(RELEASE_DIR)" && shasum -a 256 -c "$(notdir $(DMG)).sha256"
	@echo "Wrote $(RELEASE_DIR)/$(notdir $(DMG)) and $(RELEASE_DIR)/$(notdir $(DMG)).sha256"

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
