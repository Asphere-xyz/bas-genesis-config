// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.6;
pragma abicoder v2;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/cryptography/ECDSAUpgradeable.sol";

import "./interfaces/ICrossChainBridge.sol";
import "./interfaces/IERC20.sol";
import "./interfaces/IBridgeRegistry.sol";
import "./interfaces/IRelayHub.sol";

import "../common/ReceiptParser.sol";
import "../common/StringUtils.sol";

import "./BridgeRouter.sol";
import "./SimpleToken.sol";

contract CrossChainBridge is PausableUpgradeable, ReentrancyGuardUpgradeable, OwnableUpgradeable, ICrossChainBridge {

    mapping(uint256 => address) internal _bridgeAddressByChainId;
    mapping(bytes32 => bool) internal _usedProofs;
    mapping(address => address) internal _peggedTokenOrigin;
    uint256 internal _globalNonce;

    IRelayHub internal _basRelayHub;
    IBridgeRegistry internal _bridgeRegistry;
    Metadata internal _nativeTokenMetadata;
    SimpleTokenFactory internal _simpleTokenFactory;
    BridgeRouter internal _bridgeRouter;

    function initialize(
        IBridgeRegistry bridgeRegistry,
        IRelayHub basRelayHub,
        SimpleTokenFactory tokenFactory,
        BridgeRouter bridgeRouter,
        string memory nativeTokenSymbol,
        string memory nativeTokenName
    ) public initializer {
        __Pausable_init();
        __ReentrancyGuard_init();
        __Ownable_init();
        __CrossChainBridge_init(bridgeRegistry, basRelayHub, tokenFactory, bridgeRouter, nativeTokenSymbol, nativeTokenName);
    }

    function __CrossChainBridge_init(
        IBridgeRegistry bridgeRegistry,
        IRelayHub basRelayHub,
        SimpleTokenFactory tokenFactory,
        BridgeRouter bridgeRouter,
        string memory nativeTokenSymbol,
        string memory nativeTokenName
    ) internal {
        _bridgeRegistry = bridgeRegistry;
        _basRelayHub = basRelayHub;
        _simpleTokenFactory = tokenFactory;
        _nativeTokenMetadata = Metadata(
            StringUtils.stringToBytes32(nativeTokenSymbol),
            StringUtils.stringToBytes32(nativeTokenName),
            block.chainid,
        // generate unique address that will not collide with any contract address
            address(bytes20(keccak256(abi.encodePacked("CrossChainBridge:", nativeTokenSymbol))))
        );
        _bridgeRouter = bridgeRouter;
    }

    modifier onlyRelayHub() virtual {
        require(msg.sender == address(_basRelayHub));
        _;
    }

    function getTokenImplementation() public view override returns (address) {
        return _simpleTokenFactory.getImplementation();
    }

    function getRelayHub() external view returns (IRelayHub) {
        return _basRelayHub;
    }

    function setTokenFactory(SimpleTokenFactory simpleTokenFactory) public onlyOwner {
        SimpleTokenFactory oldValue = _simpleTokenFactory;
        _simpleTokenFactory = simpleTokenFactory;
        emit TokenFactoryChanged(address(oldValue), address(simpleTokenFactory));
    }

    function getNativeAddress() public view returns (address) {
        return _nativeTokenMetadata.origin;
    }

    function getOrigin(address token) internal view returns (uint256, address) {
        if (token == _nativeTokenMetadata.origin) {
            return (0, address(0x0));
        }
        try IERC20PeggedToken(token).getOrigin() returns (uint256 chain, address origin) {
            return (chain, origin);
        } catch {}
        return (0, address(0x0));
    }

    // HELPER FUNCTIONS

    function isPeggedToken(address toToken) public view override returns (bool) {
        return _peggedTokenOrigin[toToken] != address(0x00);
    }

    // DEPOSIT FUNCTIONS

    function deposit(uint256 toChain, address toAddress) public payable nonReentrant whenNotPaused override {
        _depositNative(toChain, toAddress, msg.value);
    }

    function deposit(address fromToken, uint256 toChain, address toAddress, uint256 amount) public nonReentrant whenNotPaused override {
        (uint256 chain, address origin) = getOrigin(fromToken);
        if (chain != 0) {
            // if we have pegged contract then its pegged token
            _depositPegged(fromToken, toChain, toAddress, amount, chain, origin);
        } else {
            // otherwise its erc20 token, since we can't detect is it erc20 token it can only return insufficient balance in case of any errors
            _depositErc20(fromToken, toChain, toAddress, amount);
        }
    }

    function _depositNative(uint256 toChain, address toAddress, uint256 totalAmount) internal {
        // sender is our from address because he is locking funds
        address fromAddress = address(msg.sender);
        // lets determine target bridge contract
        address toBridge = _bridgeRegistry.getBridgeAddress(toChain);
        require(toBridge != address(0x00), "bad chain");
        // we need to calculate peg token contract address with meta data
        address toToken = _bridgeRouter.peggedTokenAddress(address(toBridge), _nativeTokenMetadata.origin);
        // emit event with all these params
        emit DepositLocked(
            toChain,
            fromAddress, // who send these funds
            toAddress, // who can claim these funds in "toChain" network
            _nativeTokenMetadata.origin, // this is our current native token (e.g. ETH, MATIC, BNB, etc)
            toToken, // this is an address of our target pegged token
            totalAmount, // how much funds was locked in this contract
            _globalNonce,
            _nativeTokenMetadata // meta information about
        );
        _globalNonce++;
    }

    function _depositPegged(address fromToken, uint256 toChain, address toAddress, uint256 totalAmount, uint256 chain, address origin) internal {
        // sender is our from address because he is locking funds
        address fromAddress = address(msg.sender);
        // check allowance and transfer tokens
        require(IERC20Upgradeable(fromToken).balanceOf(fromAddress) >= totalAmount, "insufficient balance");
        uint256 scaledAmount = totalAmount;
        address toToken = _peggedDestinationErc20Token(fromToken, origin, toChain, chain);
        IERC20Mintable(fromToken).burn(fromAddress, scaledAmount);
        Metadata memory metaData = Metadata(
            StringUtils.stringToBytes32(IERC20Metadata(fromToken).symbol()),
            StringUtils.stringToBytes32(IERC20Metadata(fromToken).name()),
            chain,
            origin
        );
        // emit event with all these params
        emit DepositBurned(
            toChain,
            fromAddress, // who send these funds
            toAddress, // who can claim these funds in "toChain" network
            fromToken, // this is our current native token (can be ETH, CLV, DOT, BNB or something else)
            toToken, // this is an address of our target pegged token
            scaledAmount, // how much funds was locked in this contract
            _globalNonce,
            metaData
        );
        _globalNonce++;
    }

    function _depositErc20(address fromToken, uint256 toChain, address toAddress, uint256 totalAmount) internal {
        // sender is our from address because he is locking funds
        address fromAddress = address(msg.sender);
        // check allowance and transfer tokens
        {
            uint256 balanceBefore = IERC20(fromToken).balanceOf(address(this));
            uint256 allowance = IERC20(fromToken).allowance(fromAddress, address(this));
            require(totalAmount <= allowance, "insufficient allowance");
            require(IERC20(fromToken).transferFrom(fromAddress, address(this), totalAmount), "can't transfer");
            uint256 balanceAfter = IERC20(fromToken).balanceOf(address(this));
            // assert that enough coins were transferred to bridge
            require(balanceAfter >= balanceBefore + totalAmount, "incorrect behaviour");
        }
        // lets determine target bridge contract
        address toBridge = _bridgeRegistry.getBridgeAddress(toChain);
        require(toBridge != address(0x00), "bad chain");
        // lets pack ERC20 token meta data and scale amount to 18 decimals
        uint256 scaledAmount = _amountErc20Token(fromToken, totalAmount);
        address toToken = _bridgeRouter.peggedTokenAddress(address(toBridge), fromToken);
        Metadata memory metaData = Metadata(
            StringUtils.stringToBytes32(IERC20Metadata(fromToken).symbol()),
            StringUtils.stringToBytes32(IERC20Metadata(fromToken).name()),
            block.chainid,
            fromToken
        );
        // emit event with all these params
        emit DepositLocked(
            toChain,
            fromAddress, // who send these funds
            toAddress, // who can claim these funds in "toChain" network
            fromToken, // this is our current native token (can be ETH, CLV, DOT, BNB or something else)
            toToken, // this is an address of our target pegged token
            scaledAmount, // how much funds was locked in this contract
            _globalNonce,
            metaData // meta information about
        );
        _globalNonce++;
    }

    function _peggedDestinationErc20Token(address fromToken, address origin, uint256 toChain, uint originChain) internal view returns (address) {
        // lets determine target bridge contract
        address toBridge = _bridgeRegistry.getBridgeAddress(toChain);
        require(toBridge != address(0x00), "bad chain");
        // make sure token is supported
        require(_peggedTokenOrigin[fromToken] == origin, "non-pegged contract not supported");
        if (toChain == originChain) {
            return _peggedTokenOrigin[fromToken];
        }
        return _bridgeRouter.peggedTokenAddress(address(toBridge), origin);
    }

    function _amountErc20Token(address fromToken, uint256 totalAmount) internal view returns (uint256) {
        // lets pack ERC20 token meta data and scale amount to 18 decimals
        require(IERC20Metadata(fromToken).decimals() <= 18, "decimals overflow");
        totalAmount *= (10 ** (18 - IERC20Metadata(fromToken).decimals()));
        return totalAmount;
    }

    // WITHDRAWAL FUNCTIONS

    function withdraw(
        bytes[] calldata blockProofs,
        bytes calldata rawReceipt,
        bytes calldata proofPath,
        bytes calldata proofSiblings
    ) external nonReentrant whenNotPaused override {
        // we must parse and verify that tx and receipt matches
        (ReceiptParser.State memory state, ReceiptParser.PegInType pegInType) = ReceiptParser.parseTransactionReceipt(rawReceipt);
        require(state.chainId == block.chainid, "receipt points to another chain");
        // verify provided block proof
        require(_basRelayHub.checkReceiptProof(state.originChain, blockProofs, rawReceipt, proofSiblings, proofPath), "bad proof");
        // make sure origin contract is allowed
        _checkContractAllowed(state);
        // withdraw funds to recipient
        _withdraw(state, pegInType, state.receiptHash);
    }

    function _checkContractAllowed(ReceiptParser.State memory state) internal view virtual {
        require(_bridgeRegistry.getBridgeAddress(state.originChain) == state.contractAddress, "event from not allowed contract");
    }

    function _withdraw(ReceiptParser.State memory state, ReceiptParser.PegInType pegInType, bytes32 proofHash) internal {
        // make sure these proofs wasn't used before
        require(!_usedProofs[proofHash], "proof already used");
        _usedProofs[proofHash] = true;
        if (state.toToken == _nativeTokenMetadata.origin) {
            _withdrawNative(state);
        } else if (pegInType == ReceiptParser.PegInType.Lock) {
            _withdrawPegged(state, state.fromToken);
        } else if (state.toToken != state.originToken) {
            // origin token is not deployed by our bridge so collision is not possible
            _withdrawPegged(state, state.originToken);
        } else {
            _withdrawErc20(state);
        }
    }

    function _withdrawNative(ReceiptParser.State memory state) internal {
        payable(state.toAddress).transfer(state.totalAmount);
        //        revert(Strings.toString(state.totalAmount));
        emit WithdrawUnlocked(
            state.receiptHash,
            state.fromAddress,
            state.toAddress,
            state.fromToken,
            state.toToken,
            state.totalAmount
        );
    }

    function _getMetadata(ReceiptParser.State memory state) internal pure returns (ICrossChainBridge.Metadata memory) {
        ICrossChainBridge.Metadata memory metadata;
        assembly {
            metadata := add(state, 0x120)
        }
        return metadata;
    }

    function _withdrawPegged(ReceiptParser.State memory state, address /*origin*/) internal {
        // create pegged token if it doesn't exist
        Metadata memory metadata = _getMetadata(state);
        _factoryPeggedToken(state.toToken, metadata);
        // mint tokens
        IERC20Mintable(state.toToken).mint(state.toAddress, state.totalAmount);
        // emit peg-out event (its just informative event)
        emit WithdrawMinted(
            state.receiptHash,
            state.fromAddress,
            state.toAddress,
            state.fromToken,
            state.toToken,
            state.totalAmount
        );
    }

    function _withdrawErc20(ReceiptParser.State memory state) internal {
        // we need to rescale this amount
        uint8 decimals = IERC20Metadata(state.toToken).decimals();
        require(decimals <= 18, "decimals overflow");
        uint256 scaledAmount = state.totalAmount / (10 ** (18 - decimals));
        // transfer tokens and make sure behaviour is correct (just in case)
        uint256 balanceBefore = IERC20(state.toToken).balanceOf(state.toAddress);
        require(IERC20Upgradeable(state.toToken).transfer(state.toAddress, scaledAmount), "can't transfer");
        uint256 balanceAfter = IERC20(state.toToken).balanceOf(state.toAddress);
        require(balanceBefore <= balanceAfter, "incorrect behaviour");
        // emit peg-out event (its just informative event)
        emit WithdrawUnlocked(
            state.receiptHash,
            state.fromAddress,
            state.toAddress,
            state.fromToken,
            state.toToken,
            state.totalAmount
        );
    }

    // OWNER MAINTENANCE FUNCTIONS (owner functions will be reduced in future releases)

    function factoryPeggedToken(uint256 fromChain, Metadata calldata metaData) external onlyOwner override {
        // make sure this chain is supported
        require(_bridgeRegistry.getBridgeAddress(fromChain) != address(0x00), "bad contract");
        // calc target token
        address toToken = _bridgeRouter.peggedTokenAddress(address(this), metaData.origin);
        require(_peggedTokenOrigin[toToken] == address(0x00), "already exists");
        // deploy new token (its just a warmup operation)
        _factoryPeggedToken(toToken, metaData);
    }

    function _factoryPeggedToken(address toToken, Metadata memory metaData) internal returns (IERC20Mintable) {
        address fromToken = metaData.origin;
        // if pegged token exist we can just return its address
        if (_peggedTokenOrigin[toToken] != address(0x00)) {
            return IERC20Mintable(toToken);
        }
        // we must use delegate call because we need to deploy new contract from bridge contract to have valid address
        (bool success, bytes memory returnValue) = address(_bridgeRouter).delegatecall(
            abi.encodeWithSignature("factoryPeggedToken(address,address,(bytes32,bytes32,uint256,address),address)", fromToken, toToken, metaData, address(this))
        );
        if (!success) {
            // preserving error message
            uint256 returnLength = returnValue.length;
            assembly {
                revert(add(returnValue, 0x20), returnLength)
            }
        }
        // now we can mark this token as pegged
        _peggedTokenOrigin[toToken] = fromToken;
        // to token is our new pegged token
        return IERC20Mintable(toToken);
    }

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    function changeRouter(address router) public onlyOwner {
        require(router != address(0x0), "zero address disallowed");
        _bridgeRouter = BridgeRouter(router);
        // We don't have special event for router change since it's very special technical contract
        // In future changing router will be disallowed
    }
}
