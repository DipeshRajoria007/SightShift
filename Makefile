# SightShift build commands. Requires Xcode 16 or later.
APP_NAME    := SightShift
BUNDLE_ID   := app.sightshift.SightShift
CONFIG      ?= Release
BUILD_DIR   := build
DERIVED     := $(BUILD_DIR)/DerivedData
APP         := $(BUILD_DIR)/$(APP_NAME).app
INSTALL_DIR ?= /Applications

.PHONY: all build run install test project icon site og-image serve-site reset-permissions clean

all: build

## Regenerate SightShift.xcodeproj from project.yml (needs `brew install xcodegen`).
project:
	xcodegen generate

SightShift.xcodeproj/project.pbxproj: project.yml
	@if command -v xcodegen >/dev/null; then xcodegen generate --quiet; else touch $@; fi

## Build and sign build/SightShift.app.
build: SightShift.xcodeproj/project.pbxproj
	xcodebuild -project SightShift.xcodeproj -scheme $(APP_NAME) -configuration $(CONFIG) \
		-destination 'generic/platform=macOS' -derivedDataPath $(DERIVED) CODE_SIGNING_ALLOWED=NO -quiet build
	rm -rf $(APP)
	cp -R $(DERIVED)/Build/Products/$(CONFIG)/$(APP_NAME).app $(APP)
	scripts/sign.sh $(APP)

## Build and launch from the build folder.
run: build
	-pkill -x $(APP_NAME); sleep 0.5
	open $(APP)

## Build, copy to /Applications (override with INSTALL_DIR=~/Applications) and launch.
install: build
	-pkill -x $(APP_NAME); sleep 0.5
	rm -rf "$(INSTALL_DIR)/$(APP_NAME).app"
	cp -R $(APP) "$(INSTALL_DIR)/"
	open "$(INSTALL_DIR)/$(APP_NAME).app"

## Run the unit tests for the gaze model and decision logic.
test:
	cd Packages/SightShiftCore && swift test

## Regenerate the app icon.
icon:
	swift scripts/make-icon.swift App/Resources/Assets.xcassets/AppIcon.appiconset

## Regenerate the website's guide, privacy and blog pages from scripts/site_pages.py.
site:
	python3 scripts/site_pages.py

## Render the website's social preview card with Google Chrome.
og-image:
	"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless=new --hide-scrollbars \
		--window-size=1200,630 --screenshot=website/assets/img/og-image.png "file://$(CURDIR)/scripts/og-image.html"

## Preview the website at http://localhost:8000/SightShift/ (the same path as on GitHub Pages).
serve-site:
	@mkdir -p build/site && ln -sfn "$(CURDIR)/website" build/site/SightShift
	@echo "Serving http://localhost:8000/SightShift/"
	cd build/site && python3 -m http.server 8000

## Make macOS forget SightShift's Camera and Accessibility permissions.
reset-permissions:
	-tccutil reset Accessibility $(BUNDLE_ID)
	-tccutil reset Camera $(BUNDLE_ID)

clean:
	rm -rf $(BUILD_DIR)
