// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface ISovereignVaultMinimal {
    function getTokensForPool(address _pool) external view returns (address[] memory);

    /// @notice Base token held by this vault (e.g. PURR) for swap→hedge sizing.
    function purr() external view returns (address);

    /// @notice Must match the pool's configured perp index for this pair when the vault backs a pool.
    function hedgePerpAssetIndex() external view returns (uint32);

    // ✅ used by SovereignPool to compute usdcDelta safely
    function usdc() external view returns (address);

    function getTotalAllocatedUSDC() external view returns (uint256);

    // ✅ must exist; make it dynamic in the vault contract
    function getUSDCBalance() external view returns (uint256);

    function getReservesForPool(address _pool, address[] calldata _tokens) external view returns (uint256[] memory);

    function claimPoolManagerFees(uint256 _feePoolManager0, uint256 _feePoolManager1) external;

    function sendTokensToRecipient(address _token, address _recipient, uint256 _amount) external;

    /// @notice After each swap, the pool requests a perp hedge sized to the PURR leg (disabled when perp index is 0).
    /// @param vaultPurrOut If true, the vault paid PURR to the user (hedge: buy perp). If false, the vault received PURR (hedge: sell perp).
    /// @param purrAmountWei PURR amount in EVM wei for the swap leg (output or input filled).
    function hedgeAfterSwap(bool vaultPurrOut, uint256 purrAmountWei) external;
}