package main

import (
	_ "embed"
	"encoding/json"
	"fmt"
	systemcontract2 "github.com/ethereum/go-ethereum/common/systemcontract"
	"github.com/ethereum/go-ethereum/eth/tracers"
	"io/fs"
	"io/ioutil"
	"math/big"
	"reflect"
	"strings"
	"unicode"
	"unsafe"

	_ "github.com/ethereum/go-ethereum/eth/tracers/native"

	"github.com/ethereum/go-ethereum/crypto"

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

func readDirtyStorageFromState(f *state.StateObject) state.Storage {
	var result map[common.Hash]common.Hash
	rs := reflect.ValueOf(*f)
	rf := rs.FieldByName("dirtyStorage")
	rs2 := reflect.New(rs.Type()).Elem()
	rs2.Set(rs)
	rf = rs2.FieldByName("dirtyStorage")
	rf = reflect.NewAt(rf.Type(), unsafe.Pointer(rf.UnsafeAddr())).Elem()
	ri := reflect.ValueOf(&result).Elem()
	ri.Set(rf)
	return result
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
	tracer, err := tracers.New("callTracer", nil)
	if err != nil {
		return err
	}
	evm := vm.NewEVM(blockContext, txContext, statedb, genesis.Config, vm.Config{
		Debug:  true,
		Tracer: tracer,
	})
	deployedBytecode, _, err := evm.CreateWithAddress(vm.AccountRef(common.Address{}), bytecode, 10_000_000, big.NewInt(0), systemContract)
	if err != nil {
		for _, c := range deployedBytecode[64:] {
			if c >= 32 && c <= unicode.MaxASCII {
				print(string(c))
			}
		}
		println()
		return err
	}
	storage := readDirtyStorageFromState(statedb.GetOrNewStateObject(systemContract))
	// read state changes from state database
	genesisAccount := core.GenesisAccount{
		Code:    deployedBytecode,
		Storage: storage.Copy(),
		Balance: big.NewInt(0),
		Nonce:   0,
	}
	if genesis.Alloc == nil {
		genesis.Alloc = make(core.GenesisAlloc)
	}
	genesis.Alloc[systemContract] = genesisAccount
	// make sure ctor working fine (better to fail here instead of in consensus engine)
	errorCode, _, err := evm.Call(vm.AccountRef(common.Address{}), systemContract, hexutil.MustDecode("0xe1c7392a"), 10_000_000, big.NewInt(0))
	if err != nil {
		for _, c := range errorCode[64:] {
			if c >= 32 && c <= unicode.MaxASCII {
				print(string(c))
			}
		}
		println()
		return err
	}
	return nil
}

var stakingAddress = common.HexToAddress("0x0000000000000000000000000000000000001000")
var slashingIndicatorAddress = common.HexToAddress("0x0000000000000000000000000000000000001001")
var systemRewardAddress = common.HexToAddress("0x0000000000000000000000000000000000001002")
var stakingPoolAddress = common.HexToAddress("0x0000000000000000000000000000000000007001")
var governanceAddress = common.HexToAddress("0x0000000000000000000000000000000000007002")
var chainConfigAddress = common.HexToAddress("0x0000000000000000000000000000000000007003")
var runtimeUpgradeAddress = common.HexToAddress("0x0000000000000000000000000000000000007004")
var deployerProxyAddress = common.HexToAddress("0x0000000000000000000000000000000000007005")
var intermediarySystemAddress = common.HexToAddress("0xfffffffffffffffffffffffffffffffffffffffe")

//go:embed build/contracts/Staking.json
var stakingRawArtifact []byte

//go:embed build/contracts/StakingPool.json
var stakingPoolRawArtifact []byte

//go:embed build/contracts/ChainConfig.json
var chainConfigRawArtifact []byte

//go:embed build/contracts/SlashingIndicator.json
var slashingIndicatorRawArtifact []byte

//go:embed build/contracts/SystemReward.json
var systemRewardRawArtifact []byte

//go:embed build/contracts/Governance.json
var governanceRawArtifact []byte

//go:embed build/contracts/RuntimeUpgrade.json
var runtimeUpgradeRawArtifact []byte

//go:embed build/contracts/DeployerProxy.json
var deployerProxyRawArtifact []byte

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
	MinValidatorStakeAmount  *big.Int
	MinStakingAmount         *big.Int
}

type genesisConfig struct {
	Genesis         *core.Genesis
	Deployers       []common.Address
	Validators      []common.Address
	SystemTreasury  common.Address
	ConsensusParams consensusParams
	VotingPeriod    int64
	Faucet          map[common.Address]string
	CommissionRate  int64
	InitialStakes   map[common.Address]string
}

func invokeConstructorOrPanic(genesis *core.Genesis, contract common.Address, rawArtifact []byte, typeNames []string, params []interface{}) {
	ctor, err := newArguments(typeNames...).Pack(params...)
	if err != nil {
		panic(err)
	}
	sig := crypto.Keccak256([]byte(fmt.Sprintf("ctor(%s)", strings.Join(typeNames, ","))))[:4]
	ctor = append(sig, ctor...)
	ctor, err = newArguments("bytes").Pack(ctor)
	if err != nil {
		panic(err)
	}
	fmt.Printf(" + calling constructor: address=%s sig=%s ctor=%s\n", contract.Hex(), hexutil.Encode(sig), hexutil.Encode(ctor))
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
	var initialStakes []*big.Int
	initialStakeTotal := big.NewInt(0)
	for _, v := range config.Validators {
		rawInitialStake, ok := config.InitialStakes[v]
		if !ok {
			return fmt.Errorf("initial stake is not found for validator: %s", v.Hex())
		}
		initialStake, err := hexutil.DecodeBig(rawInitialStake)
		if err != nil {
			return err
		}
		initialStakes = append(initialStakes, initialStake)
		initialStakeTotal.Add(initialStakeTotal, initialStake)
	}
	invokeConstructorOrPanic(genesis, stakingAddress, stakingRawArtifact, []string{"address[]", "uint256[]", "uint16"}, []interface{}{
		config.Validators,
		initialStakes,
		uint16(config.CommissionRate),
	})
	invokeConstructorOrPanic(genesis, chainConfigAddress, chainConfigRawArtifact, []string{"uint32", "uint32", "uint32", "uint32", "uint32", "uint32", "uint256", "uint256"}, []interface{}{
		config.ConsensusParams.ActiveValidatorsLength,
		config.ConsensusParams.EpochBlockInterval,
		config.ConsensusParams.MisdemeanorThreshold,
		config.ConsensusParams.FelonyThreshold,
		config.ConsensusParams.ValidatorJailEpochLength,
		config.ConsensusParams.UndelegatePeriod,
		config.ConsensusParams.MinValidatorStakeAmount,
		config.ConsensusParams.MinStakingAmount,
	})
	invokeConstructorOrPanic(genesis, slashingIndicatorAddress, slashingIndicatorRawArtifact, []string{}, []interface{}{})
	invokeConstructorOrPanic(genesis, stakingPoolAddress, stakingPoolRawArtifact, []string{}, []interface{}{})
	invokeConstructorOrPanic(genesis, systemRewardAddress, systemRewardRawArtifact, []string{"address"}, []interface{}{
		config.SystemTreasury,
	})
	invokeConstructorOrPanic(genesis, governanceAddress, governanceRawArtifact, []string{"uint256"}, []interface{}{
		big.NewInt(config.VotingPeriod),
	})
	invokeConstructorOrPanic(genesis, runtimeUpgradeAddress, runtimeUpgradeRawArtifact, []string{"address"}, []interface{}{
		systemcontract2.EvmHookRuntimeUpgradeAddress,
	})
	invokeConstructorOrPanic(genesis, deployerProxyAddress, deployerProxyRawArtifact, []string{"address[]"}, []interface{}{
		config.Deployers,
	})
	// create system contract
	genesis.Alloc[intermediarySystemAddress] = core.GenesisAccount{
		Balance: big.NewInt(0),
	}
	// set staking allocation
	stakingAlloc := genesis.Alloc[stakingAddress]
	stakingAlloc.Balance = initialStakeTotal
	genesis.Alloc[stakingAddress] = stakingAlloc
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
		RuntimeUpgradeBlock: big.NewInt(0),
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

var localNetConfig = genesisConfig{
	Genesis: defaultGenesisConfig(1337),
	// who is able to deploy smart contract from genesis block
	Deployers: []common.Address{
		common.HexToAddress("0x00a601f45688dba8a070722073b015277cf36725"),
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
		MinValidatorStakeAmount:  hexutil.MustDecodeBig("0xde0b6b3a7640000"), // 1 ether
		MinStakingAmount:         hexutil.MustDecodeBig("0xde0b6b3a7640000"), // 1 ether
	},
	InitialStakes: map[common.Address]string{
		common.HexToAddress("0x00a601f45688dba8a070722073b015277cf36725"): "0x3635c9adc5dea00000", // 1000 eth
	},
	// owner of the governance
	VotingPeriod: 20, // 1 minute
	// faucet
	Faucet: map[common.Address]string{
		common.HexToAddress("0x00a601f45688dba8a070722073b015277cf36725"): "0x21e19e0c9bab2400000",
		common.HexToAddress("0x57BA24bE2cF17400f37dB3566e839bfA6A2d018a"): "0x21e19e0c9bab2400000",
		common.HexToAddress("0xEbCf9D06cf9333706E61213F17A795B2F7c55F1b"): "0x21e19e0c9bab2400000",
	},
}

var devNetConfig = genesisConfig{
	Genesis: defaultGenesisConfig(14000),
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
		ActiveValidatorsLength:   25,   // suggested values are (3k+1, where k is honest validators, even better): 7, 13, 19, 25, 31...
		EpochBlockInterval:       1200, // better to use 1 day epoch (86400/3=28800, where 3s is block time)
		MisdemeanorThreshold:     50,   // after missing this amount of blocks per day validator losses all daily rewards (penalty)
		FelonyThreshold:          150,  // after missing this amount of blocks per day validator goes in jail for N epochs
		ValidatorJailEpochLength: 7,    // how many epochs validator should stay in jail (7 epochs = ~7 days)
		UndelegatePeriod:         6,    // allow claiming funds only after 6 epochs (~7 days)

		MinValidatorStakeAmount: hexutil.MustDecodeBig("0xde0b6b3a7640000"), // how many tokens validator must stake to create a validator (in ether)
		MinStakingAmount:        hexutil.MustDecodeBig("0xde0b6b3a7640000"), // minimum staking amount for delegators (in ether)
	},
	InitialStakes: map[common.Address]string{
		common.HexToAddress("0x08fae3885e299c24ff9841478eb946f41023ac69"): "0x3635c9adc5dea00000", // 1000 eth
		common.HexToAddress("0x751aaca849b09a3e347bbfe125cf18423cc24b40"): "0x3635c9adc5dea00000", // 1000 eth
		common.HexToAddress("0xa6ff33e3250cc765052ac9d7f7dfebda183c4b9b"): "0x3635c9adc5dea00000", // 1000 eth
		common.HexToAddress("0x49c0f7c8c11a4c80dc6449efe1010bb166818da8"): "0x3635c9adc5dea00000", // 1000 eth
		common.HexToAddress("0x8e1ea6eaa09c3b40f4a51fcd056a031870a0549a"): "0x3635c9adc5dea00000", // 1000 eth
	},
	// owner of the governance
	VotingPeriod: 60, // 3 minutes
	// faucet
	Faucet: map[common.Address]string{
		common.HexToAddress("0x00a601f45688dba8a070722073b015277cf36725"): "0x21e19e0c9bab2400000",    // governance
		common.HexToAddress("0xb891fe7b38f857f53a7b5529204c58d5c487280b"): "0x52b7d2dcc80cd2e4000000", // faucet (10kk)
	},
}

func main() {
	println("building local net")
	if err := createGenesisConfig(localNetConfig, "localnet.json"); err != nil {
		panic(err)
	}
	println()
	println("building dev net")
	if err := createGenesisConfig(devNetConfig, "devnet.json"); err != nil {
		panic(err)
	}
	println()
}
