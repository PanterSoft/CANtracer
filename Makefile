# Host OS picks the Flutter device; override with `make run OS=linux`.
UNAME := $(shell uname -s)
ifeq ($(UNAME),Darwin)
  OS ?= macos
else ifeq ($(UNAME),Linux)
  OS ?= linux
else
  OS ?= windows
endif

.PHONY: deps build run test analyze clean

deps:
	flutter pub get

build: deps
	flutter build $(OS) --release

run: deps
	flutter run -d $(OS)

test: deps
	flutter test

analyze: deps
	flutter analyze

clean:
	flutter clean
