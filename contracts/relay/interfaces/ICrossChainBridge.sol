// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.6;

import "../interfaces/IERC20.sol";

interface ICrossChainBridge {

    event PegTokenDeployed(address pegTokenAddress, uint256 fromChain, bytes32 symbol, bytes32 name, address origin);

    struct MetaData {
        bytes32 symbol; // token symbol from origin chain
        bytes32 name; // token name from origin chain (only first 32 bytes)
        address origin; // address of the origin token
    }

    event DepositLocked(
        uint256 fromChain, // source chain id
        uint256 toChain, // target chain id
        address indexed fromAddress, // sender address
        address indexed toAddress, // recipient address
        address fromToken, // locked token address
        address toToken, // tokens to be minted in the target chain
        uint256 totalAmount, // total locked amount
        uint256 nonce, // just global nonce
        MetaData metaData // origin token metadata (symbol, name)
    );
    event DepositBurned(
        uint256 fromChain,
        uint256 toChain,
        address indexed fromAddress,
        address indexed toAddress,
        address fromToken,
        address toToken,
        uint256 totalAmount,
        uint256 nonce,
        MetaData metaData
    );

    event WithdrawMinted(
        bytes32 receiptHash,
        address indexed fromAddress,
        address indexed toAddress,
        address fromToken,
        address toToken,
        uint256 totalAmount
    );
    event WithdrawUnlocked(
        bytes32 receiptHash,
        address indexed fromAddress,
        address indexed toAddress,
        address fromToken,
        address toToken,
        uint256 totalAmount
    );

    function isPeggedToken(address toToken) external returns (bool);

    function deposit(uint256 toChain, address toAddress) payable external;

    function depositERC20(address fromToken, uint256 toChain, address toAddress, uint256 amount) external;

    function withdraw(
        bytes[] calldata blockProofs,
        bytes calldata rawReceipt,
        bytes memory proofPath,
        bytes calldata proofSiblings
    ) external;
}
