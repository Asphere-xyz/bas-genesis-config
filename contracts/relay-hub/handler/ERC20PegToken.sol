// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.6;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import "../interfaces/IERC20.sol";

contract ERC20PegToken is ERC20, IERC20PegToken {

    // we store symbol and name as bytes32
    bytes32 internal _symbol;
    bytes32 internal _name;

    // cross chain bridge (owner)
    address internal _crossChainBridge;

    // origin address and chain id
    address internal _originAddress;
    uint256 internal _originChain;

    constructor() ERC20("", "") {
    }

    function initialize(bytes32 symbol_, bytes32 name_, uint256 originChain, address originAddress) public emptyCrossChainBridge {
        // remember owner of the smart contract (only cross chain bridge)
        _crossChainBridge = msg.sender;
        // remember new symbol and name
        _symbol = symbol_;
        _name = name_;
        // store origin address and chain id (where the original token exists)
        _originChain = originChain;
        _originAddress = originAddress;
    }

    modifier emptyCrossChainBridge() {
        require(_crossChainBridge == address(0x00));
        _;
    }

    modifier onlyCrossChainBridge() virtual {
        require(msg.sender == _crossChainBridge, "only owner");
        _;
    }

    function getOrigin() public view override returns (
        uint256 originChain,
        address originAddress
    ) {
        return (_originChain, _originAddress);
    }

    function mint(address account, uint256 amount) external override onlyCrossChainBridge {
        _mint(account, amount);
    }

    function burn(address account, uint256 amount) external override onlyCrossChainBridge {
        _burn(account, amount);
    }

    function bytes32ToString(bytes32 _bytes32) internal pure returns (string memory) {
        if (_bytes32 == 0) {
            return new string(0);
        }
        uint8 countNonZero = 0;
        for (uint8 i = 16; i > 0; i >>= 1) {
            if (_bytes32[countNonZero + i] != 0) countNonZero += i;
        }
        string memory result = new string(countNonZero + 1);
        assembly {
            mstore(add(result, 0x20), _bytes32)
        }
        return result;
    }

    function name() public view override returns (string memory) {
        return bytes32ToString(_name);
    }

    function symbol() public view override returns (string memory) {
        return bytes32ToString(_symbol);
    }
}