// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.6;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/cryptography/ECDSAUpgradeable.sol";

import "./interfaces/ICrossChainBridge.sol";
import "./interfaces/IERC20.sol";
import "./interfaces/IRelayHub.sol";

import "../common/ReceiptParser.sol";
import "../common/StringUtils.sol";

import "../InjectorContextHolder.sol";
import "./handler/ERC20TokenHandler.sol";

contract CrossChainBridge is InjectorContextHolder, ReentrancyGuardUpgradeable, ICrossChainBridge {

    IBridgeHandler internal immutable _erc20TokenHandler;

    mapping(bytes32 => bool) internal _usedProofs;
    mapping(address => address) internal _peggedTokenOrigin;
    uint256 internal _globalNonce;
    MetaData internal _nativeMetaData;

    constructor(ConstructorArguments memory constructorArgs) InjectorContextHolder(constructorArgs) {
        (_erc20TokenHandler) = _factoryTokenHandlers();
    }

    function _factoryTokenHandlers() internal virtual returns (IBridgeHandler erc20TokenHandler) {
        return (new ERC20TokenHandler());
    }

    function initialize(string memory nativeTokenSymbol, string memory nativeTokenName) external initializer {
        __ReentrancyGuard_init();
        __CrossChainBridge_init(nativeTokenSymbol, nativeTokenName);
    }

    function __CrossChainBridge_init(string memory nativeTokenSymbol, string memory nativeTokenName) internal {
        _nativeMetaData = MetaData(
            StringUtils.stringToBytes32(nativeTokenSymbol),
            StringUtils.stringToBytes32(nativeTokenName),
            _generateNativeTokenAddress(nativeTokenSymbol)
        );
    }

    function _generateNativeTokenAddress(string memory tokenSymbol) internal pure returns (address) {
        // generate unique address that will not collide with any contract address
        return address(bytes20(keccak256(abi.encodePacked("CrossChainBridge:", tokenSymbol))));
    }

    function getNativeMetaData() external view returns (MetaData memory) {
        return _nativeMetaData;
    }

    function getOrigin(address token) internal view returns (uint256, address) {
        if (token == _nativeMetaData.origin) {
            return (0, address(0x0));
        }
        try IPegToken(token).getOrigin() returns (uint256 chain, address origin) {
            return (chain, origin);
        } catch {}
        return (0, address(0x0));
    }

    function isPeggedToken(address toToken) external view override returns (bool) {
        return _peggedTokenOrigin[toToken] != address(0x00);
    }

    function deposit(uint256 toChain, address toAddress) external payable nonReentrant override {
        _depositNative(toChain, toAddress, msg.value);
    }

    function depositERC20(address fromToken, uint256 toChain, address toAddress, uint256 amount) external nonReentrant override {
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
        address toBridge = _RELAY_HUB_CONTRACT.getBridgeAddress(toChain);
        require(toBridge != address(0x00), "bad chain");
        // we need to calculate peg token contract address with meta data
        address toToken = _erc20TokenHandler.calcPegTokenAddress(address(toBridge), _nativeMetaData.origin);
        // emit event with all these params
        emit DepositLocked(
            block.chainid,
            toChain,
            fromAddress, // who send these funds
            toAddress, // who can claim these funds in "toChain" network
            _nativeMetaData.origin, // this is our current native token (e.g. ETH, MATIC, BNB, etc)
            toToken, // this is an address of our target pegged token
            totalAmount, // how much funds was locked in this contract
            _globalNonce,
            _nativeMetaData // meta information about
        );
        _globalNonce++;
    }

    function _depositPegged(address fromToken, uint256 toChain, address toAddress, uint256 totalAmount, uint256 fromChain, address originAddress) internal {
        // sender is our from address because he is locking funds
        address fromAddress = address(msg.sender);
        // check allowance and transfer tokens
        require(IERC20Upgradeable(fromToken).balanceOf(fromAddress) >= totalAmount, "insufficient balance");
        uint256 scaledAmount = totalAmount;
        address toToken = _peggedDestinationErc20Token(fromToken, originAddress, toChain, fromChain);
        IERC20Mintable(fromToken).burn(fromAddress, scaledAmount);
        MetaData memory metaData = MetaData(
            StringUtils.stringToBytes32(IERC20Metadata(fromToken).symbol()),
            StringUtils.stringToBytes32(IERC20Metadata(fromToken).name()),
            originAddress
        );
        // emit event with all these params
        emit DepositBurned(
            fromChain, // source chain id
            toChain, // target chain id
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
        address toBridge = _RELAY_HUB_CONTRACT.getBridgeAddress(toChain);
        require(toBridge != address(0x00), "bad chain");
        // lets pack ERC20 token meta data and scale amount to 18 decimals
        uint256 scaledAmount = _amountErc20Token(fromToken, totalAmount);
        address toToken = _erc20TokenHandler.calcPegTokenAddress(address(toBridge), fromToken);
        MetaData memory metaData = MetaData(
            StringUtils.stringToBytes32(IERC20Metadata(fromToken).symbol()),
            StringUtils.stringToBytes32(IERC20Metadata(fromToken).name()),
            fromToken
        );
        // emit event with all these params
        emit DepositLocked(
            block.chainid, // origin chain id
            toChain, // destination chain id
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
        address toBridge = _RELAY_HUB_CONTRACT.getBridgeAddress(toChain);
        require(toBridge != address(0x00), "bad chain");
        // make sure token is supported
        require(_peggedTokenOrigin[fromToken] == origin, "non-pegged contract not supported");
        if (toChain == originChain) {
            return _peggedTokenOrigin[fromToken];
        }
        return _erc20TokenHandler.calcPegTokenAddress(address(toBridge), origin);
    }

    function _amountErc20Token(address fromToken, uint256 totalAmount) internal view returns (uint256) {
        // lets pack ERC20 token meta data and scale amount to 18 decimals
        require(IERC20Metadata(fromToken).decimals() <= 18, "decimals overflow");
        totalAmount *= (10 ** (18 - IERC20Metadata(fromToken).decimals()));
        return totalAmount;
    }

    function withdraw(
        bytes[] calldata blockProofs,
        bytes calldata rawReceipt,
        bytes calldata proofPath,
        bytes calldata proofSiblings
    ) external nonReentrant override {
        // we must parse and verify that tx and receipt matches
        (ReceiptParser.State memory state, ReceiptParser.PegInType pegInType) = ReceiptParser.parseTransactionReceipt(rawReceipt);
        require(state.toChain == block.chainid, "receipt points to another chain");
        // verify provided block proof
        require(_RELAY_HUB_CONTRACT.checkReceiptProof(state.fromChain, blockProofs, rawReceipt, proofSiblings, proofPath), "bad proof");
        // make sure origin contract is allowed
        _checkContractAllowed(state);
        // withdraw funds to recipient
        _withdraw(state, pegInType, state.receiptHash);
    }

    function _checkContractAllowed(ReceiptParser.State memory state) internal view virtual {
        require(_RELAY_HUB_CONTRACT.getBridgeAddress(state.fromChain) == state.contractAddress, "event from not allowed contract");
    }

    function _withdraw(ReceiptParser.State memory state, ReceiptParser.PegInType pegInType, bytes32 proofHash) internal {
        // make sure these proofs wasn't used before
        require(!_usedProofs[proofHash], "proof already used");
        _usedProofs[proofHash] = true;
        if (state.toToken == _nativeMetaData.origin) {
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
        emit WithdrawUnlocked(
            state.receiptHash,
            state.fromAddress,
            state.toAddress,
            state.fromToken,
            state.toToken,
            state.totalAmount
        );
    }

    function _extractMetaDataFromState(ReceiptParser.State memory state) internal pure returns (MetaData memory) {
        MetaData memory metaData;
        assembly {
            metaData := add(state, 0x140)
        }
        return metaData;
    }

    function _withdrawPegged(ReceiptParser.State memory state, address /*origin*/) internal {
        // create pegged token if it doesn't exist
        MetaData memory metadata = _extractMetaDataFromState(state);
        _factoryPeggedToken(state.toToken, metadata, state.fromChain);
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

    function _factoryPeggedToken(address toToken, MetaData memory metaData, uint256 fromChain) internal returns (IERC20Mintable) {
        address fromToken = metaData.origin;
        // if pegged token exist we can just return its address
        if (_peggedTokenOrigin[toToken] != address(0x00)) {
            return IERC20Mintable(toToken);
        }
        // we must use delegate call because we need to deploy new contract from bridge contract to have valid address
        (bool success, bytes memory returnValue) = address(_erc20TokenHandler).delegatecall(
            abi.encodeWithSelector(IBridgeHandler.factoryPegToken.selector, fromToken, metaData, fromChain)
        );
        if (!success) {
            // preserving error message
            assembly {
                revert(add(returnValue, 0x20), mload(returnValue))
            }
        }
        // make sure produced peg-token address is what we're looking for
        (address pegTokenAddress) = abi.decode(returnValue, (address));
        require(pegTokenAddress == toToken, "non-deterministic peg-token address");
        // emit event with all deployed peg-tokens
        emit PegTokenDeployed(toToken, fromChain, metaData.symbol, metaData.name, metaData.origin);
        // now we can mark this token as pegged
        _peggedTokenOrigin[toToken] = fromToken;
        return IERC20Mintable(toToken);
    }
}
