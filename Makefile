# TransReader Swift — Makefile
# Build output is a signed .app bundle under build/

APP_NAME     := TransReader
BUNDLE_ID    := com.transreader.swift
VERSION      := 1.0
BUILD_NUMBER := 1

SPM_BUILD_DIR := .build
OUT_DIR      := build
APP_DIR      := $(OUT_DIR)/$(APP_NAME).app
CONTENTS_DIR := $(APP_DIR)/Contents
MACOS_DIR    := $(CONTENTS_DIR)/MacOS
RESOURCES_DIR:= $(CONTENTS_DIR)/Resources
ENTITLEMENTS := $(OUT_DIR)/entitlements.plist
INSTALL_DIR  := /Applications
EXECUTABLE   := $(MACOS_DIR)/TransReaderSwift

SWIFT_BUILD_FLAGS :=

.PHONY: all build bundle sign run run-debug install uninstall clean help

all: sign ## Build, bundle, and sign (default)

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

build: ## Compile with Swift Package Manager
	@echo "▸ Building TransReaderSwift..."
	swift build $(SWIFT_BUILD_FLAGS)

bundle: build ## Create .app bundle (only copies binary if changed)
	@mkdir -p "$(MACOS_DIR)" "$(RESOURCES_DIR)"
	@# Only copy + re-sign if source .swift files are newer than the bundle executable
	@SRC="$(SPM_BUILD_DIR)/debug/TransReaderSwift"; \
	if [ -f "$(SPM_BUILD_DIR)/release/TransReaderSwift" ]; then \
		SRC="$(SPM_BUILD_DIR)/release/TransReaderSwift"; \
	fi; \
	if [ ! -f "$(EXECUTABLE)" ] || [ "$$SRC" -nt "$(EXECUTABLE)" ]; then \
		echo "▸ Binary updated, refreshing bundle..."; \
		cp "$$SRC" "$(EXECUTABLE)"; \
		touch "$(OUT_DIR)/.needs-sign"; \
	else \
		echo "▸ Bundle up to date."; \
	fi
	@# Always ensure Info.plist exists
	@if [ ! -f "$(CONTENTS_DIR)/Info.plist" ]; then \
		printf '%s\n' \
			'<?xml version="1.0" encoding="UTF-8"?>' \
			'<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' \
			'<plist version="1.0">' \
			'<dict>' \
			'  <key>CFBundleIdentifier</key>'  '<string>$(BUNDLE_ID)</string>' \
			'  <key>CFBundleName</key>'        '<string>$(APP_NAME)</string>' \
			'  <key>CFBundleDisplayName</key>' '<string>$(APP_NAME)</string>' \
			'  <key>CFBundleExecutable</key>'  '<string>TransReaderSwift</string>' \
			'  <key>CFBundleVersion</key>'     '<string>$(BUILD_NUMBER)</string>' \
			'  <key>CFBundleShortVersionString</key>' '<string>$(VERSION)</string>' \
			'  <key>CFBundlePackageType</key>' '<string>APPL</string>' \
			'  <key>LSUIElement</key>'         '<true/>' \
			'</dict>' \
			'</plist>' > "$(CONTENTS_DIR)/Info.plist"; \
		touch "$(OUT_DIR)/.needs-sign"; \
	fi
	@if [ ! -f "$(ENTITLEMENTS)" ]; then \
		printf '%s\n' \
			'<?xml version="1.0" encoding="UTF-8"?>' \
			'<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' \
			'<plist version="1.0">' \
			'<dict>' \
			'  <key>com.apple.security.app-sandbox</key>' '<false/>' \
			'</dict>' \
			'</plist>' > "$(ENTITLEMENTS)"; \
		touch "$(OUT_DIR)/.needs-sign"; \
	fi

sign: bundle ## Ad-hoc codesign (only if binary changed)
	@if [ -f "$(OUT_DIR)/.needs-sign" ]; then \
		echo "▸ Signing $(APP_NAME).app (ad-hoc)..."; \
		codesign --force --deep --sign - --entitlements "$(ENTITLEMENTS)" "$(APP_DIR)"; \
		rm -f "$(OUT_DIR)/.needs-sign"; \
	else \
		echo "▸ Signature up to date, skipping."; \
	fi

run: all ## Build + launch the app
	@echo "▸ Launching $(APP_NAME)..."
	@open "$(APP_DIR)"

run-debug: all ## Build + launch with terminal logs visible
	@echo "▸ Launching $(APP_NAME) (debug, logs in terminal)..."
	@"$(APP_DIR)/Contents/MacOS/TransReaderSwift"

install: all ## Copy .app to /Applications
	@echo "▸ Installing $(APP_NAME).app → $(INSTALL_DIR)/"
	@rm -rf "$(INSTALL_DIR)/$(APP_NAME).app"
	cp -R "$(APP_DIR)" "$(INSTALL_DIR)/$(APP_NAME).app"
	@echo "✓ Installed to $(INSTALL_DIR)/$(APP_NAME).app"

uninstall: ## Remove from /Applications
	@echo "▸ Removing $(INSTALL_DIR)/$(APP_NAME).app..."
	rm -rf "$(INSTALL_DIR)/$(APP_NAME).app"
	@echo "✓ Uninstalled"

clean: ## Remove build artifacts
	@echo "▸ Cleaning..."
	swift package clean
	rm -rf "$(OUT_DIR)"
	@echo "✓ Clean"
