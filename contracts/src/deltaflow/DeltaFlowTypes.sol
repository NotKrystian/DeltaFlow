// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/// @notice Unified snapshot for EVM vault balances + HyperCore spot + optional perp leg.
struct BalanceSheet {
    uint256 evmUsdc;
    uint256 evmBase;
    /// @dev Core spot totals converted to EVM token decimals (wei).
    uint256 coreUsdc;
    uint256 coreBase;
    /// @dev Perp size in raw contract units (sign from `szi`), plus queued hedge `sz` not yet sent as IOC (`pendingBuy − pendingSell`).
    int256 perpSzi;
    uint256 markPxNormalized;
    uint256 spotPxNormalized;
    /// @dev USDC value of inventory + hedge in 1e18 WAD (see BalanceSheetLib).
    uint256 navWad;
    /// @dev Base token “shortfall” vs capacity in WAD (0 if none).
    uint256 shortfallWad;
    /// @dev Mid-price spread proxy in bps (0 if disabled / invalid BBO).
    uint256 spreadBps;
}

/// @notice Tunable policy (store immutables in RiskEngine / FeeModule).
struct DeltaFlowRiskPolicy {
    /// @dev Capacity reference for exhaustion / NAV (base token, WAD).
    uint256 capacityWad;
    uint256 navSoftWad;
    uint256 navWarnWad;
    uint256 navHardWad;
    /// @dev Max Core+EVM base shortfall before revert (WAD).
    uint256 maxShortfallWad;
    /// @dev Reject if BBO spread wider than this (bps); 0 = skip check.
    uint256 maxSpreadBps;
    /// @dev Minimum fee surplus (USDC, 6 decimals) required for “new risk” swaps; 0 = off.
    uint256 minSurplusUsdcNewRisk;
    uint256 rawFeeRejectBps;
    uint256 displayedFeeCapBps;
    bool requirePositiveSurplusTrend;
}
