// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

interface IBlast {
    // Note: the full interface for IBlast can be found below
    function configureClaimableGas() external;

    function claimAllGas(
        address contractAddress,
        address recipient
    ) external returns (uint256);

    function claimGasAtMinClaimRate(
        address contractAddress,
        address recipient,
        uint256 minClaimRateBips
    ) external returns (uint256);
}
