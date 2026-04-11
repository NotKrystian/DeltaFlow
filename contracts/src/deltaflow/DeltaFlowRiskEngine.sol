// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {BalanceSheet, DeltaFlowRiskPolicy} from "./DeltaFlowTypes.sol";
import {FeeSurplus} from "./FeeSurplus.sol";

/// @title DeltaFlowRiskEngine
/// @notice Policy gate: **reverts** mean “reject swap” (per product spec).
/// @dev “Fill probability &lt; 85%” is approximated via `maxSpreadBps` on BBO until a dedicated feed exists.
contract DeltaFlowRiskEngine {
    DeltaFlowRiskPolicy public policy;
    FeeSurplus public immutable surplus;
    bool public immutable requireSurplusForNewRisk;

    address public owner;

    error RiskEngine__RawFeeTooHigh(uint256 raw, uint256 max);
    error RiskEngine__SpreadTooWide(uint256 spreadBps, uint256 max);
    error RiskEngine__NavHardCap(uint256 nav, uint256 cap);
    error RiskEngine__Shortfall(uint256 shortfallWad, uint256 maxWad);
    error RiskEngine__SurplusTooLow(uint256 have, uint256 need);
    error RiskEngine__NewRiskNotAllowed();
    error RiskEngine__OnlyOwner();

    constructor(DeltaFlowRiskPolicy memory p, FeeSurplus _surplus, bool _requireSurplusForNewRisk, address _owner) {
        policy = p;
        surplus = _surplus;
        requireSurplusForNewRisk = _requireSurplusForNewRisk;
        owner = _owner;
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert RiskEngine__OnlyOwner();
        _;
    }

    /// @notice Update caps / thresholds as markets evolve (per-pair tuning).
    function setPolicy(DeltaFlowRiskPolicy memory p) external onlyOwner {
        policy = p;
    }

    function setOwner(address o) external onlyOwner {
        owner = o;
    }

    function validate(
        BalanceSheet memory sheet,
        uint256 rawFeeBps,
        bool isUnwind,
        bool isNewRisk
    ) external view {
        // `rawFeeRejectBps == 0` disables this guard (useful for testnet tuning).
        if (policy.rawFeeRejectBps > 0 && rawFeeBps > policy.rawFeeRejectBps) {
            revert RiskEngine__RawFeeTooHigh(rawFeeBps, policy.rawFeeRejectBps);
        }

        if (policy.maxSpreadBps > 0 && sheet.spreadBps > policy.maxSpreadBps) {
            revert RiskEngine__SpreadTooWide(sheet.spreadBps, policy.maxSpreadBps);
        }

        if (policy.navHardWad > 0 && sheet.navWad > policy.navHardWad) {
            revert RiskEngine__NavHardCap(sheet.navWad, policy.navHardWad);
        }

        if (policy.maxShortfallWad > 0 && sheet.shortfallWad > policy.maxShortfallWad) {
            revert RiskEngine__Shortfall(sheet.shortfallWad, policy.maxShortfallWad);
        }

        if (isNewRisk && policy.minSurplusUsdcNewRisk > 0) {
            if (address(surplus) != address(0) && surplus.surplusUsdc() < policy.minSurplusUsdcNewRisk) {
                revert RiskEngine__SurplusTooLow(surplus.surplusUsdc(), policy.minSurplusUsdcNewRisk);
            }
        }

        if (requireSurplusForNewRisk && isNewRisk && !isUnwind) {
            if (address(surplus) == address(0)) revert RiskEngine__NewRiskNotAllowed();
        }
    }

    function capDisplayedFee(uint256 rawFeeBps) external view returns (uint256) {
        if (rawFeeBps <= policy.displayedFeeCapBps) return rawFeeBps;
        return policy.displayedFeeCapBps;
    }
}
