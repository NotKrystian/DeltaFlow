// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {BalanceSheet} from "./DeltaFlowTypes.sol";

/// @title DeltaFlowFeeMath
/// @notice Implements the memo’s component fee model (fixed-point). Parameters are tunable per deployment.
/// @dev Unwind power curve uses a linear taper (see comment) — replace with rational pow if you add PRBMath.
library DeltaFlowFeeMath {
    uint256 internal constant WAD = 1e18;

    struct FeeParams {
        uint256 execPerpBps;
        uint256 execSpotShortfallBps;
        uint256 delayNormalBps;
        uint256 delayStressedBps;
        uint256 basisMaxBps;
        uint256 fundingCapBps;
        uint256 invKappaWad; // 2.4 * 1e18
        uint256 exhaustLinearWad;
        uint256 exhaustQuadWad;
        uint256 safetyBaseBps;
        bool delayStressed;
        /// @dev HTML quote engine: `sqrt` impact denominator (WAD USDC-notional); 0 → 1 WAD.
        uint256 perpDepthWad;
        /// @dev Coefficient on `sqrt(notional/depth)` (HTML default 12).
        uint256 impactCoeff;
        /// @dev Max hedge `sz` for utilization = |H|/H_MAX (0 → treat as full util = WAD).
        uint256 hMaxSz;
        /// @dev POOL_NAV denominator for strategic bands (WAD); 0 → use `sheet.navWad`.
        uint256 poolNavWad;
    }

    /// @notice Returns raw fee in **bips** (1 = 0.01%, same as `SovereignPool` feeInBips scale) before cap/reject.
    function computeNewRiskFeeBps(
        BalanceSheet memory s,
        FeeParams memory p,
        uint256 tradeNotionalUsdcWad,
        bool volatileRegime
    ) internal pure returns (uint256 feeBps) {
        uint256 exec = p.execPerpBps;

        if (s.shortfallWad > 0) {
            exec = p.execSpotShortfallBps;
        }

        uint256 delay = p.delayStressed ? p.delayStressedBps : p.delayNormalBps;

        uint256 basis = Math.min(p.basisMaxBps, 5); // stub: use max until rolling std dev is wired

        uint256 funding = Math.min(p.fundingCapBps, 3);

        uint256 q = 0;
        if (s.navWad > 0) {
            q = Math.min(WAD, Math.mulDiv(s.shortfallWad, WAD, s.navWad));
        }
        // Exhaustion coefficients are WAD-scaled; convert to bips before summing with fee components.
        uint256 exhaustWad =
            Math.mulDiv(p.exhaustLinearWad, q, WAD) + Math.mulDiv(p.exhaustQuadWad, Math.mulDiv(q, q, WAD), WAD);
        uint256 exhaust = exhaustWad / WAD;

        uint256 x = s.navWad > 0 ? Math.mulDiv(s.shortfallWad + tradeNotionalUsdcWad / 4, WAD, s.navWad) : WAD;
        x = Math.min(x, 3 * WAD);
        uint256 invSkew = _inventorySkewBps(p.invKappaWad, x);

        uint256 safety = p.safetyBaseBps;
        if (volatileRegime) safety += 3;
        if (s.spreadBps > 30) safety += 5;
        if (s.spreadBps > 50) safety += 10;

        feeBps = exec + delay + basis + funding + exhaust + invSkew + safety;
    }

    /// @notice Marginal unwind curve (memo §): blended single-step midpoint — taper is **linear** in (1−u).
    function unwindFeeBps(uint256 uPreWad, uint256 uPostWad) internal pure returns (uint256) {
        uint256 uAvg = (uPreWad + uPostWad) / 2;
        uint256 oneMinus = uAvg >= WAD ? 0 : WAD - uAvg;
        // Target: ~2.5–5 bps: 2.5 + 5.5 * (1-u)  [linear substitute for (1-u)^1.2]
        uint256 term = Math.mulDiv(55, oneMinus, WAD);
        return 25 + term / 10;
    }

    function _inventorySkewBps(uint256 kappaWad, uint256 xWad) internal pure returns (uint256) {
        uint256 z = Math.mulDiv(kappaWad, xWad, WAD);
        uint256 eZ = _expWad(z);
        uint256 diff = eZ > WAD ? eZ - WAD : 0;
        return Math.mulDiv(7, diff, WAD);
    }

    function _expWad(uint256 xWad) internal pure returns (uint256) {
        uint256 term = WAD;
        uint256 sum = WAD;
        for (uint256 i = 1; i < 24; i++) {
            term = Math.mulDiv(term, xWad, WAD * i);
            sum += term;
            if (term < 1e12) break;
        }
        return sum;
    }
}
