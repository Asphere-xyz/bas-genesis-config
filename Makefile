build: *
	yarn compile && node build-abi.js
	go run ./create-genesis.go

all: build
