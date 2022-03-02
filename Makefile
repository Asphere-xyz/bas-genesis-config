.PHONY: install
install:
	yarn

.PHONY: compile
compile:
	yarn compile && node build-abi.js

.PHONY: create-genesis
create-genesis:
	go run ./create-genesis.go

.PHONY: all
all: install compile create-genesis
