// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.6;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

interface IPegToken {

    function getOrigin() external view returns (
        uint256 originChain,
        address originAddress
    );
}

interface IERC20PegToken is IPegToken {

    function mint(address account, uint256 amount) external;

    function burn(address account, uint256 amount) external;
}

interface IERC20Mintable is IERC20PegToken {
}