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

    /// @notice Mint LP shares to foundation against swap fees already received into the vault.
    /// @dev Called by authorized pool after charging swap fee.
    function creditSwapFeeToFoundation(address feeToken, uint256 feeAmount) external;

    /// @notice Hedge sizing + optional payout escrow when `minPerpHedgeSz > 0`. Pool calls before sending `tokenOut`.
    /// @param vaultPurrOut If true, the vault would pay PURR (hedge: buy perp). If false, vault receives PURR (hedge: sell perp).
    /// @param purrAmountWei PURR leg in EVM wei for hedge sizing.
    /// @param swapTokenOut Output token for this swap.
    /// @param recipient Swap output recipient.
    /// @param amountOut Output amount quoted by the ALM.
    /// @return poolShouldSendTokenOut If true, the pool must call `sendTokensToRecipient` for this swap. If false, the vault escrowed the payout or already paid in a batch flush.
    function processSwapHedge(
        bool vaultPurrOut,
        uint256 purrAmountWei,
        uint256 usdcFeeProtected,
        address swapTokenOut,
        address recipient,
        uint256 amountOut
    ) external returns (bool poolShouldSendTokenOut);
}