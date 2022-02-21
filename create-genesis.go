package main

import (
	_ "embed"
	"encoding/json"
	"fmt"
	"io/fs"
	"io/ioutil"
	"math/big"

	"github.com/ethereum/go-ethereum/accounts/abi"
	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/common/hexutil"
	"github.com/ethereum/go-ethereum/consensus"
	"github.com/ethereum/go-ethereum/core"
	"github.com/ethereum/go-ethereum/core/rawdb"
	"github.com/ethereum/go-ethereum/core/state"
	"github.com/ethereum/go-ethereum/core/types"
	"github.com/ethereum/go-ethereum/core/vm"
	"github.com/ethereum/go-ethereum/ethdb/memorydb"
	"github.com/ethereum/go-ethereum/params"
	"github.com/ethereum/go-ethereum/trie"
)

type artifactData struct {
	Bytecode         string `json:"bytecode"`
	DeployedBytecode string `json:"deployedBytecode"`
}

type dummyChainContext struct {
}

func (d *dummyChainContext) Engine() consensus.Engine {
	return nil
}

func (d *dummyChainContext) GetHeader(h common.Hash, n uint64) *types.Header {
	return nil
}

func createExtraData(validators []common.Address) []byte {
	extra := make([]byte, 32+20*len(validators)+65)
	for i, v := range validators {
		copy(extra[32+20*i:], v.Bytes())
	}
	return extra
}

func simulateSystemContract(genesis *core.Genesis, systemContract common.Address, rawArtifact []byte, constructor []byte) error {
	artifact := &artifactData{}
	if err := json.Unmarshal(rawArtifact, artifact); err != nil {
		return err
	}
	bytecode := append(hexutil.MustDecode(artifact.Bytecode), constructor...)
	// simulate constructor execution
	ethdb := rawdb.NewDatabase(memorydb.New())
	db := state.NewDatabaseWithConfig(ethdb, &trie.Config{})
	statedb, err := state.New(common.Hash{}, db, nil)
	if err != nil {
		return err
	}
	block := genesis.ToBlock(nil)
	blockContext := core.NewEVMBlockContext(block.Header(), &dummyChainContext{}, &common.Address{})
	txContext := core.NewEVMTxContext(
		types.NewMessage(common.Address{}, &systemContract, 0, big.NewInt(0), 10_000_000, big.NewInt(0), []byte{}, nil, false),
	)
	evm := vm.NewEVM(blockContext, txContext, statedb, genesis.Config, vm.Config{})
	deployedBytecode, _, err := evm.CreateWithAddress(vm.AccountRef(common.Address{}), bytecode, 10_000_000, big.NewInt(0), systemContract)
	if err != nil {
		return err
	}
	contractState := statedb.GetOrNewStateObject(systemContract)
	storage := contractState.GetDirtyStorage()
	// read state changes from state database
	genesisAccount := core.GenesisAccount{
		Code:    deployedBytecode,
		Storage: storage,
		Balance: big.NewInt(0),
		Nonce:   0,
	}
	if genesis.Alloc == nil {
		genesis.Alloc = make(core.GenesisAlloc)
	}
	genesis.Alloc[systemContract] = genesisAccount
	return nil
}

var stakingAddress = common.HexToAddress("0x0000000000000000000000000000000000001000")
var slashingIndicatorAddress = common.HexToAddress("0x0000000000000000000000000000000000001001")
var systemRewardAddress = common.HexToAddress("0x0000000000000000000000000000000000001002")
var contractDeployerAddress = common.HexToAddress("0x0000000000000000000000000000000000007001")
var governanceAddress = common.HexToAddress("0x0000000000000000000000000000000000007002")
var intermediarySystemAddress = common.HexToAddress("0xfffffffffffffffffffffffffffffffffffffffe")

//go:embed build/contracts/Staking.json
var stakingRawArtifact []byte

//go:embed build/contracts/SlashingIndicator.json
var slashingIndicatorRawArtifact []byte

//go:embed build/contracts/SystemReward.json
var systemRewardRawArtifact []byte

//go:embed build/contracts/ContractDeployer.json
var contractDeployerRawArtifact []byte

//go:embed build/contracts/Governance.json
var governanceRawArtifact []byte

func newArguments(typeNames ...string) abi.Arguments {
	var args abi.Arguments
	for i, tn := range typeNames {
		abiType, err := abi.NewType(tn, tn, nil)
		if err != nil {
			panic(err)
		}
		args = append(args, abi.Argument{Name: fmt.Sprintf("%d", i), Type: abiType})
	}
	return args
}

type consensusParams struct {
	ActiveValidatorsLength   uint32
	EpochBlockInterval       uint32
	MisdemeanorThreshold     uint32
	FelonyThreshold          uint32
	ValidatorJailEpochLength uint32
	UndelegatePeriod         uint32
}

type genesisConfig struct {
	Genesis         *core.Genesis
	Deployers       []common.Address
	Validators      []common.Address
	SystemTreasury  common.Address
	ConsensusParams consensusParams
	VotingPeriod    int64
	Faucet          map[common.Address]string
}

func invokeConstructorOrPanic(genesis *core.Genesis, contract common.Address, rawArtifact []byte, typeNames []string, params []interface{}) {
	ctor, err := newArguments(typeNames...).Pack(params...)
	if err != nil {
		panic(err)
	}
	if err := simulateSystemContract(genesis, contract, rawArtifact, ctor); err != nil {
		panic(err)
	}
}

func createGenesisConfig(config genesisConfig, targetFile string) error {
	genesis := config.Genesis
	// extra data
	genesis.ExtraData = createExtraData(config.Validators)
	genesis.Config.Parlia.Epoch = uint64(config.ConsensusParams.EpochBlockInterval)
	// execute system contracts
	invokeConstructorOrPanic(genesis, stakingAddress, stakingRawArtifact, []string{"address[]", "uint32", "uint32", "uint32", "uint32", "uint32", "uint32"}, []interface{}{
		config.Validators,
		config.ConsensusParams.ActiveValidatorsLength,
		config.ConsensusParams.EpochBlockInterval,
		config.ConsensusParams.MisdemeanorThreshold,
		config.ConsensusParams.FelonyThreshold,
		config.ConsensusParams.ValidatorJailEpochLength,
		config.ConsensusParams.UndelegatePeriod,
	})
	invokeConstructorOrPanic(genesis, slashingIndicatorAddress, slashingIndicatorRawArtifact, []string{}, []interface{}{})
	invokeConstructorOrPanic(genesis, systemRewardAddress, systemRewardRawArtifact, []string{"address"}, []interface{}{
		config.SystemTreasury,
	})
	invokeConstructorOrPanic(genesis, contractDeployerAddress, contractDeployerRawArtifact, []string{"address[]"}, []interface{}{
		config.Deployers,
	})
	invokeConstructorOrPanic(genesis, governanceAddress, governanceRawArtifact, []string{"uint256"}, []interface{}{
		big.NewInt(config.VotingPeriod),
	})
	// create system contract
	genesis.Alloc[intermediarySystemAddress] = core.GenesisAccount{
		Balance: big.NewInt(0),
	}
	// apply faucet
	for key, value := range config.Faucet {
		balance, ok := new(big.Int).SetString(value[2:], 16)
		if !ok {
			return fmt.Errorf("failed to parse number (%s)", value)
		}
		genesis.Alloc[key] = core.GenesisAccount{
			Balance: balance,
		}
	}
	// save to file
	newJson, _ := json.MarshalIndent(genesis, "", "  ")
	return ioutil.WriteFile(targetFile, newJson, fs.ModePerm)
}

func defaultGenesisConfig(chainId int64) *core.Genesis {
	chainConfig := &params.ChainConfig{
		ChainID:             big.NewInt(chainId),
		HomesteadBlock:      big.NewInt(0),
		EIP150Block:         big.NewInt(0),
		EIP155Block:         big.NewInt(0),
		EIP158Block:         big.NewInt(0),
		ByzantiumBlock:      big.NewInt(0),
		ConstantinopleBlock: big.NewInt(0),
		PetersburgBlock:     big.NewInt(0),
		IstanbulBlock:       big.NewInt(0),
		MuirGlacierBlock:    big.NewInt(0),
		RamanujanBlock:      big.NewInt(0),
		NielsBlock:          big.NewInt(0),
		MirrorSyncBlock:     big.NewInt(0),
		BrunoBlock:          big.NewInt(0),
		Parlia: &params.ParliaConfig{
			Period: 3,
			// epoch length is managed by consensus params
		},
	}
	return &core.Genesis{
		Config:     chainConfig,
		Nonce:      0,
		Timestamp:  0x5e9da7ce,
		ExtraData:  nil,
		GasLimit:   0x2625a00,
		Difficulty: big.NewInt(0x01),
		Mixhash:    common.Hash{},
		Coinbase:   common.Address{},
		Alloc:      nil,
		Number:     0x00,
		GasUsed:    0x00,
		ParentHash: common.Hash{},
	}
}

var devnetConfig = genesisConfig{
	Genesis: defaultGenesisConfig(1337),
	// who is able to deploy smart contract from genesis block
	Deployers: []common.Address{
		common.HexToAddress("0xbAdCab1E02FB68dDD8BBB0A45Cc23aBb60e174C8"),
	},
	// list of default validators
	Validators: []common.Address{
		common.HexToAddress("0x00a601f45688dba8a070722073b015277cf36725"),
	},
	SystemTreasury: common.HexToAddress("0x00a601f45688dba8a070722073b015277cf36725"),
	ConsensusParams: consensusParams{
		ActiveValidatorsLength:   1,
		EpochBlockInterval:       100,
		MisdemeanorThreshold:     10,
		FelonyThreshold:          100,
		ValidatorJailEpochLength: 1,
		UndelegatePeriod:         0,
	},
	// owner of the governance
	VotingPeriod: 20, // 1 minute
	// faucet
	Faucet: map[common.Address]string{
		common.HexToAddress("0xbAdCab1E02FB68dDD8BBB0A45Cc23aBb60e174C8"): "0x21e19e0c9bab2400000", // dmitry
		common.HexToAddress("0x57BA24bE2cF17400f37dB3566e839bfA6A2d018a"): "0x21e19e0c9bab2400000", // chiliz
		common.HexToAddress("0xEbCf9D06cf9333706E61213F17A795B2F7c55F1b"): "0x21e19e0c9bab2400000", // chiliz
	},
}

var testnetConfig = genesisConfig{
	Genesis: defaultGenesisConfig(17242),
	// who is able to deploy smart contract from genesis block (it won't generate event log)
	Deployers: []common.Address{},
	// list of default validators (it won't generate event log)
	Validators: []common.Address{
		common.HexToAddress("0x08fae3885e299c24ff9841478eb946f41023ac69"),
		common.HexToAddress("0x751aaca849b09a3e347bbfe125cf18423cc24b40"),
		common.HexToAddress("0xa6ff33e3250cc765052ac9d7f7dfebda183c4b9b"),
		common.HexToAddress("0x49c0f7c8c11a4c80dc6449efe1010bb166818da8"),
		common.HexToAddress("0x8e1ea6eaa09c3b40f4a51fcd056a031870a0549a"),
	},
	SystemTreasury: common.HexToAddress(""),
	ConsensusParams: consensusParams{
		ActiveValidatorsLength:   25,    // suggested values are (3k+1, where k is honest validators, even better): 7, 13, 19, 25, 31...
		EpochBlockInterval:       28800, // better to use 1 day epoch (86400/3=28800, where 3s is block time)
		MisdemeanorThreshold:     50,    // after missing this amount of blocks per day validator losses all daily rewards (penalty)
		FelonyThreshold:          150,   // after missing this amount of blocks per day validator goes in jail for N epochs
		ValidatorJailEpochLength: 7,     // how many epochs validator should stay in jail (7 epochs = ~7 days)
		UndelegatePeriod:         6,     // allow claiming funds only after 6 epochs (~7 days)
	},
	// owner of the governance
	VotingPeriod: 60, // 3 minutes
	// faucet
	Faucet: map[common.Address]string{
		common.HexToAddress("0x00a601f45688dba8a070722073b015277cf36725"): "0x21e19e0c9bab2400000",    // governance
		common.HexToAddress("0xbAdCab1E02FB68dDD8BBB0A45Cc23aBb60e174C8"): "0x21e19e0c9bab2400000",    // dmitry
		common.HexToAddress("0x57BA24bE2cF17400f37dB3566e839bfA6A2d018a"): "0x21e19e0c9bab2400000",    // chiliz
		common.HexToAddress("0xEbCf9D06cf9333706E61213F17A795B2F7c55F1b"): "0x21e19e0c9bab2400000",    // chiliz
		common.HexToAddress("0xb891fe7b38f857f53a7b5529204c58d5c487280b"): "0x52b7d2dcc80cd2e4000000", // faucet (10kk)
	},
}

func main() {
	if err := createGenesisConfig(devnetConfig, "devnet.json"); err != nil {
		panic(err)
	}
	if err := createGenesisConfig(testnetConfig, "testnet.json"); err != nil {
		panic(err)
	}
}
