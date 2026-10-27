.PHONY: all build release app test clean run

all: app

build:
	swift build

release:
	./scripts/build_app.sh release

app:
	chmod +x scripts/build_app.sh
	./scripts/build_app.sh debug

test:
	swift test

run: app
	open build/Void.app

clean:
	swift package clean
	rm -rf build
