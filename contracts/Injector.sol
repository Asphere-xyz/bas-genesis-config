// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/Address.sol";

interface IEvmHooks {

    function registerDeployedContract(address account, address impl) external;

    function checkContractActive(address impl) external;
}

interface IDeployer is IEvmHooks {

    function isDeployer(address account) external view returns (bool);

    function isBanned(address account) external view returns (bool);

    function addDeployer(address account) external;

    function banDeployer(address account) external;

    function unbanDeployer(address account) external;

    function removeDeployer(address account) external;

    function getContractDeployer(address contractAddress) external view returns (uint8 state, address impl, address deployer);
}

interface IGovernance {
}

interface IParlia {

    function getValidators() external view returns (address[] memory);

    function deposit(address validator) external payable;

    function slash(address validator) external;
}

interface IStaking {

    function isValidatorAlive(address account) external view returns (bool);

    function isValidator(address account) external view returns (bool);

    function addValidator(address account) external;

    function removeValidator(address account) external;

    function getValidatorDelegation(address validator, address delegator) external view returns (
        uint256 delegatedAmount,
        uint64 atEpoch
    );

    function getValidatorStatus(address validator) external view returns (
        uint8 status,
        uint256 totalDelegated
    );

    function delegate(address validator) payable external;

    function undelegate(address validator, uint256 amount) payable external;

    function claimValidatorFee(address validator) external;

    function claimDelegatorFee(address validator) external;

    function getSystemFee() external view returns (uint256);
}

interface IVersional {

    function getVersion() external pure returns (uint256);
}

interface IInjector {

    function getDeployer() external view returns (IDeployer);

    function getGovernance() external view returns (IGovernance);

    function getParlia() external view returns (IParlia);
}

abstract contract InjectorContextHolder is IInjector, IVersional {

    bool private _init;
    uint256 private _operatingBlock;

    IDeployer private _deployer;
    IGovernance private _governance;
    IParlia private _parlia;

    uint256[50 - 4] private _gap;

    function init() public whenNotInitialized virtual {
        _deployer = IDeployer(0x0000000000000000000000000000000000000010);
        _governance = IGovernance(0x0000000000000000000000000000000000000020);
        _parlia = IParlia(0x0000000000000000000000000000000000000030);
    }

    function initManually(IDeployer deployer, IGovernance governance, IParlia parlia) public whenNotInitialized {
        _deployer = deployer;
        _governance = governance;
        _parlia = parlia;
    }

    modifier onlyFromCoinbase() {
        require(msg.sender == block.coinbase && tx.origin == block.coinbase, "InjectorContextHolder: only coinbase or governance");
        _;
    }

    modifier onlyFromCoinbaseOrGovernance() {
        // TODO: "remove this method in future by replacing it with normal mocks"
        require(msg.sender == block.coinbase || IGovernance(msg.sender) == getGovernance(), "InjectorContextHolder: only coinbase");
        _;
    }

    modifier onlyCoinbase() {
        require(msg.sender == block.coinbase, "InjectorContextHolder: only coinbase");
        _;
    }

    modifier onlyFromGovernance() {
        require(IGovernance(msg.sender) == getGovernance(), "InjectorContextHolder: only governance");
        _;
    }

    modifier onlyZeroGasPrice() {
        require(tx.gasprice == 0, "InjectorContextHolder: only zero gas price");
        _;
    }

    modifier whenNotInitialized() {
        require(!_init, "OnlyInit: already initialized");
        _;
        _init = true;
    }

    modifier whenInitialized() {
        require(_init, "OnlyInit: not initialized yet");
        _;
    }

    modifier onlyOncePerBlock() {
        require(block.number > _operatingBlock, "InjectorContextHolder: only once per block");
        _;
        _operatingBlock = block.number;
    }

    function getDeployer() public view whenInitialized override returns (IDeployer) {
        return _deployer;
    }

    function getGovernance() public view whenInitialized override returns (IGovernance) {
        return _governance;
    }

    function getParlia() public view whenInitialized override returns (IParlia) {
        return _parlia;
    }

    function isV1Compatible() public virtual pure returns (bool);
}

abstract contract InjectorContextHolderV1 is InjectorContextHolder {

    function getVersion() public pure virtual override returns (uint256) {
        return 0x01;
    }

    function isV1Compatible() public pure override returns (bool) {
        return getVersion() >= 0x01;
    }
}
