module github.com/Ankr-network/bas-genesis-config

go 1.16

require (
	github.com/ethereum/go-ethereum v1.11.3
	github.com/gorilla/mux v1.8.0
)

replace github.com/ethereum/go-ethereum v1.11.3 => github.com/ankr-network/bas-template-bsc v0.0.0-20240201145122-1ef706cfb392

// replace github.com/ethereum/go-ethereum => ../

// These replacese are copied from the github.com/ankr-network/bas-template-bsc.
// For somereason go doesn't replace them automatically from the replaced repo.
replace (
	github.com/btcsuite/btcd => github.com/btcsuite/btcd v0.23.0
	github.com/cometbft/cometbft => github.com/bnb-chain/greenfield-tendermint v0.0.0-20230417032003-4cda1f296fb2
	github.com/grpc-ecosystem/grpc-gateway/v2 => github.com/prysmaticlabs/grpc-gateway/v2 v2.3.1-0.20210702154020-550e1cd83ec1
	github.com/syndtr/goleveldb v1.0.1 => github.com/syndtr/goleveldb v1.0.1-0.20210819022825-2ae1ddf74ef7
	github.com/tendermint/tendermint => github.com/bnb-chain/tendermint v0.31.15
)
