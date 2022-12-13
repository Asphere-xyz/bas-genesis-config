// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import "../verifiers/ParliaBlockVerifier.sol";

contract GasMeasurerVerifier is ParliaBlockVerifier {

    function measureVerifyGas(bytes calldata blockProof, uint256 chainId) external view returns (uint64 gasUsed) {
        gasUsed = uint64(gasleft());
        _parseAndVerifyPoSaBlockHeader(chainId, blockProof, 200);
        return gasUsed - uint64(gasleft());
    }
}