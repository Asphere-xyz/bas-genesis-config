.PHONY: clean
clean:
	rm -rf ./build

.PHONY: install
install:
	yarn

.PHONY: compile
compile:
	yarn compile && node build-abi.js

.PHONY: test
test:
	yarn coverage

.PHONY: create-genesis
create-genesis:
	go run ./create-genesis.go

.PHONY: all
all: clean install compile create-genesis
