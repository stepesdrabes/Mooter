APP    := Mooter
BUNDLE := build/$(APP).app

.PHONY: build run install dev clean

build:
	swift build -c release
	mkdir -p $(BUNDLE)/Contents/MacOS $(BUNDLE)/Contents/Resources
	cp .build/release/$(APP) $(BUNDLE)/Contents/MacOS/$(APP)
	strip -x $(BUNDLE)/Contents/MacOS/$(APP)
	cp Support/Info.plist $(BUNDLE)/Contents/Info.plist
	cp Support/AppIcon.icns $(BUNDLE)/Contents/Resources/AppIcon.icns
	codesign --force -s - $(BUNDLE)

run: build
	pkill -x $(APP) || true
	open $(BUNDLE)

install: build
	pkill -x $(APP) || true
	rm -rf /Applications/$(APP).app
	cp -R $(BUNDLE) /Applications/
	open /Applications/$(APP).app

dev:
	swift run

clean:
	rm -rf .build build
