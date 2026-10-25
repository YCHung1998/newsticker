# FastBullTicker 建置：helper（Rust）→ app（組裝 bundle）→ sign（ad-hoc 簽名並驗證）→ test。
# 只支援 arm64；不 notarize、不沙盒。簽名順序由內而外：先 helper、再 bundle；不遞迴簽名。
APP_NAME   := FastBullTicker
BUILD_DIR  := build
APP        := $(BUILD_DIR)/$(APP_NAME).app
MACOS_DIR  := $(APP)/Contents/MacOS
HELPER_SRC := ticker-connect/target/release/ticker-connect
HELPER_DST := $(MACOS_DIR)/ticker-connect

.PHONY: all helper app sign test clean verify stop release

all: helper app sign

# 規則：每次 build 之前舊的實例必須先處理掉（stop），或用 `make release TAG=vX.Y.Z` 標新 tag 後再 build，
# 讓每個產物都對得上一個明確的版本。build 出的 Info.plist 帶 BuildRevision（git describe）。
stop:
	@sh scripts/stop-old.sh

helper:
	cd ticker-connect && cargo build --release
	@lipo -archs $(HELPER_SRC) | grep -qx arm64 || { echo "error: $(HELPER_SRC) 不是 arm64"; exit 1; }

app: stop
	@test -x $(HELPER_SRC) || { echo "error: 找不到 $(HELPER_SRC)，請先 make helper"; exit 1; }
	swift build -c release --arch arm64 --product $(APP_NAME)
	rm -rf $(APP)
	mkdir -p $(MACOS_DIR)
	cp "$$(swift build -c release --arch arm64 --show-bin-path)/$(APP_NAME)" $(MACOS_DIR)/$(APP_NAME)
	cp $(HELPER_SRC) $(HELPER_DST)
	cp Resources/Info.plist $(APP)/Contents/Info.plist
	plutil -lint $(APP)/Contents/Info.plist
	/usr/libexec/PlistBuddy -c "Add :BuildRevision string $$(git describe --tags --always --dirty)" $(APP)/Contents/Info.plist
	@echo "built revision: $$(git describe --tags --always --dirty)"

sign:
	@test -d $(APP) || { echo "error: 找不到 $(APP)，請先 make app"; exit 1; }
	codesign --force --sign - $(HELPER_DST)
	codesign --force --sign - $(APP)
	$(MAKE) verify

verify:
	codesign --verify --strict --verbose=2 $(HELPER_DST)
	codesign --verify --strict --verbose=2 $(APP)

test:
	swift test

clean:
	rm -rf $(BUILD_DIR)

# make release TAG=v0.3.0：工作樹必須乾淨、tag 不能已存在；建立註解 tag 後完整 build。不 push。
release:
	@test -n "$(TAG)" || { echo "usage: make release TAG=vX.Y.Z"; exit 1; }
	@test -z "$$(git status --porcelain)" || { echo "error: 工作樹不乾淨，請先 commit"; exit 1; }
	@git rev-parse -q --verify "refs/tags/$(TAG)" >/dev/null && { echo "error: tag $(TAG) 已存在"; exit 1; } || true
	git tag -a "$(TAG)" -m "FastBullTicker $(TAG)"
	$(MAKE) all
