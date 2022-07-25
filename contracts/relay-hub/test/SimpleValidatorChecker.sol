// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import "../interfaces/IValidatorChecker.sol";

contract SimpleValidatorChecker is IValidatorChecker {

    constructor(address[] memory _existingValidatorSet) {
        existingValidatorSet = _existingValidatorSet;
    }

    address[] public existingValidatorSet;

    function checkValidatorsAndQuorumReached(uint256, address[] memory validatorSet, uint64) external view returns (bool) {
        for (uint256 i = 0; i < validatorSet.length; i++) {
            bool signerFound = false;
            for (uint256 j = 0; j < existingValidatorSet.length; j++) {
                if (existingValidatorSet[j] != validatorSet[i]) continue;
                signerFound = true;
                break;
            }
            require(signerFound, "bad validator");
        }
        return true;
    }
}