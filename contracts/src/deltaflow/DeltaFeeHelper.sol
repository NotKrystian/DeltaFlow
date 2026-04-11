// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {BalanceSheet} from "./DeltaFlowTypes.sol";
import {DeltaFlowFeeMath} from "./DeltaFlowFeeMath.sol";

/// @title DeltaFeeHelper
/// @notice Helper: fixed-point memo quote (unwind integral + new-risk stack + blend) for `DeltaFlowCompositeFeeModule`.
library DeltaFeeHelper {
    uint256 internal constant WAD = 1e18;

    uint256 internal constant STRATEGIC_SOFT = WAD / 2;
    uint256 internal constant STRATEGIC_WARN = (8 * WAD) / 10;
    uint256 internal constant STRATEGIC_HARD = WAD;

    /// @dev Antiderivative of `(WAD - u)` for `u ∈ [0,WAD]`: `F(u) = ∫_0^u (WAD - t) dt` (raw, not WAD-normalized).
    function _linearUnwindAntiderivRaw(uint256 uWad) internal pure returns (uint256) {
        return WAD * uWad - (uWad * uWad) / 2;
    }

    /// @dev `e^(x/WAD)` in WAD (same series as `DeltaFlowFeeMath._expWad`).
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

    /// @dev Exponential ramp on [0,WAD]: `(e^(2u/WAD)-1)/(e^2-1)` scaled to WAD (matches concentration curve shape).
    function _expCurveUtilWad(uint256 uWad) internal pure returns (uint256) {
        if (uWad == 0) return 0;
        if (uWad >= WAD) return WAD;
        uint256 k = 2 * WAD;
        uint256 x = Math.mulDiv(k, uWad, WAD);
        uint256 num = _expWad(x) - WAD;
        uint256 den = _expWad(k) - WAD;
        if (den == 0) return uWad;
        return Math.min(WAD, Math.mulDiv(num, WAD, den));
    }

    /// @dev Marginal new-risk bps at hedge utilization `u`: 10 → 60 bps following `_expCurveUtilWad`.
    function _newRiskMarginalBpsAtUtil(uint256 uWad) internal pure returns (uint256) {
        return 10 + Math.mulDiv(50, _expCurveUtilWad(uWad), WAD);
    }

    /// @dev ∫_0^U `_newRiskMarginalBpsAtUtil` du via trapezoids (16 steps); `U` in WAD.
    function _integralNewRisk0ToU(uint256 uEndWad) internal pure returns (uint256) {
        if (uEndWad == 0) return 0;
        uint256 n = 16;
        uint256 sum = 0;
        for (uint256 i = 0; i < n; i++) {
            uint256 u0 = Math.mulDiv(uEndWad, i, n);
            uint256 u1 = Math.mulDiv(uEndWad, i + 1, n);
            uint256 f0 = _newRiskMarginalBpsAtUtil(u0);
            uint256 f1 = _newRiskMarginalBpsAtUtil(u1);
            sum += Math.mulDiv(f0 + f1, uEndWad, 2 * n);
        }
        return sum;
    }

    /// @notice Average bps for a **zero-crossing** hedge path: unwind integral (0→10 bps marginal) + new-risk integral (10→60 marginal), divided by path length `uPre+uPost`.
    function hedgeCrossingPathAvgBps(uint256 utilPreWad, uint256 utilPostWad) internal pure returns (uint256) {
        uint256 denom = utilPreWad + utilPostWad;
        if (denom == 0) return 10;
        uint256 deltaFU = _linearUnwindAntiderivRaw(utilPreWad);
        uint256 iu = Math.mulDiv(10, deltaFU, WAD);
        uint256 iN = _integralNewRisk0ToU(utilPostWad);
        uint256 total = iu + iN;
        return Math.mulDiv(total, 1, denom);
    }

    /// @notice Concentration-only unwind leg: 0 bps when the pool is fully one-sided in value (c = WAD), 10 bps at 50/50 (c = 0).
    /// @dev `cWad` is the same metric as `DeltaFlowCompositeFeeModule`: |U − B| / (U + B) in WAD scale.
    function unwindFeeBpsFromConcentrationWad(uint256 cWad) internal pure returns (uint256) {
        if (cWad >= WAD) return 0;
        return Math.mulDiv(10, WAD - cWad, WAD);
    }

    /// @notice Zero-crossing quote in concentration-only mode: average unwind bps at pre- and post-trade concentration.
    function hedgeCrossingUnwindConcAvgBps(uint256 cPreWad, uint256 cPostWad) internal pure returns (uint256) {
        uint256 a = unwindFeeBpsFromConcentrationWad(cPreWad);
        uint256 b = unwindFeeBpsFromConcentrationWad(cPostWad);
        return (a + b) / 2;
    }

    /// @dev Unwind-only: **area under** marginal fee `m(u) = 10·(WAD-u)/WAD` from `utilPost`→`utilPre`, divided by `Δu` → average bps.
    function unwindFeeBpsIntegral(uint256 utilPreWad, uint256 utilPostWad) internal pure returns (uint256) {
        if (utilPreWad <= utilPostWad) return 3;
        uint256 du = utilPreWad - utilPostWad;
        if (du < 10) {
            uint256 mLo = Math.mulDiv(10, WAD - utilPostWad, WAD);
            uint256 mHi = Math.mulDiv(10, WAD - utilPreWad, WAD);
            return (mLo + mHi) / 2;
        }
        uint256 deltaF = _linearUnwindAntiderivRaw(utilPreWad) - _linearUnwindAntiderivRaw(utilPostWad);
        uint256 iSeg = Math.mulDiv(10, deltaF, WAD);
        return Math.mulDiv(iSeg, 1, du);
    }

    function sqrtWad(uint256 x) internal pure returns (uint256) {
        if (x == 0) return 0;
        return Math.sqrt(Math.mulDiv(x, WAD, 1));
    }

    function skewUtilPow25(uint256 skewUtilWad) internal pure returns (uint256) {
        uint256 s2 = Math.mulDiv(skewUtilWad, skewUtilWad, WAD);
        uint256 sr = sqrtWad(skewUtilWad);
        return Math.mulDiv(Math.mulDiv(s2, sr, WAD), WAD, WAD);
    }

    function bandMultiplierWad(uint256 navExposureWad) internal pure returns (uint256) {
        if (navExposureWad <= STRATEGIC_SOFT) return WAD;
        if (navExposureWad <= STRATEGIC_WARN) {
            uint256 num = 2 * (navExposureWad - STRATEGIC_SOFT);
            uint256 den = STRATEGIC_WARN - STRATEGIC_SOFT;
            return WAD + Math.mulDiv(num, WAD, den);
        }
        if (navExposureWad <= STRATEGIC_HARD) {
            uint256 num = navExposureWad - STRATEGIC_WARN;
            uint256 den = STRATEGIC_HARD - STRATEGIC_WARN;
            uint256 frac = den == 0 ? WAD : Math.min(WAD, Math.mulDiv(num, WAD, den));
            return 3 * WAD + Math.mulDiv(4 * WAD, frac, WAD);
        }
        return 7 * WAD;
    }

    function absInt(int256 x) internal pure returns (uint256) {
        return x >= 0 ? uint256(x) : uint256(-x);
    }

    /// @notice New-risk leg: components + InventorySkew/Exhaustion (memo-style).
    function newRiskFeeBpsHtml(
        BalanceSheet memory s,
        DeltaFlowFeeMath.FeeParams memory p,
        uint256 tradeNotionalWad,
        bool volatileRegime,
        bool useMarketRiskComponent,
        uint256 absHPostSz,
        uint256 hMaxSz,
        uint256 poolNavWad
    ) internal pure returns (uint256 feeBps) {
        uint256 exec = p.execPerpBps;
        if (s.shortfallWad > 0) exec = p.execSpotShortfallBps;

        uint256 depth = p.perpDepthWad == 0 ? WAD : p.perpDepthWad;
        uint256 impact = Math.mulDiv(p.impactCoeff, sqrtWad(Math.mulDiv(tradeNotionalWad, WAD, depth)), WAD);

        uint256 delay = p.delayStressed ? p.delayStressedBps : p.delayNormalBps;
        uint256 basis = Math.min(p.basisMaxBps, 5);
        uint256 funding = Math.min(p.fundingCapBps, 3);

        uint256 q = s.navWad == 0 ? 0 : Math.min(WAD, Math.mulDiv(s.shortfallWad, WAD, s.navWad));
        // Exhaustion coefficients are WAD-scaled; convert to bips before summing with fee components.
        uint256 exhaustWad = Math.mulDiv(p.exhaustLinearWad, q, WAD)
            + Math.mulDiv(p.exhaustQuadWad, Math.mulDiv(q, q, WAD), WAD);
        uint256 exhaust = exhaustWad / WAD;

        uint256 skewUtil = hMaxSz == 0 ? WAD : Math.min(WAD, Math.mulDiv(absHPostSz, WAD, hMaxSz));
        uint256 navDenom = poolNavWad == 0 ? (s.navWad == 0 ? WAD : s.navWad) : poolNavWad;
        uint256 hedgeNotionalWad = s.markPxNormalized == 0 ? 0 : Math.mulDiv(absHPostSz, s.markPxNormalized, WAD);
        uint256 navExposureWad = navDenom == 0 ? WAD : Math.min(WAD, Math.mulDiv(hedgeNotionalWad, WAD, navDenom));

        uint256 bm = bandMultiplierWad(navExposureWad);
        uint256 sp = skewUtilPow25(skewUtil);
        uint256 invSkew = Math.min(
            210,
            Math.mulDiv(35, Math.mulDiv(Math.mulDiv(sp, 30, WAD), bm, WAD), 10 * WAD)
        );

        uint256 exhaustionKnee = 0;
        if (skewUtil > WAD / 2) {
            uint256 z = Math.mulDiv(skewUtil - WAD / 2, WAD, WAD / 2);
            exhaustionKnee =
                8 * Math.mulDiv(Math.mulDiv(z, z, WAD), WAD, WAD) + 25 * Math.mulDiv(Math.mulDiv(z, z, WAD), Math.mulDiv(z, z, WAD), WAD);
        }

        uint256 safety = p.safetyBaseBps;
        if (useMarketRiskComponent) {
            if (volatileRegime) safety += 3;
            if (s.spreadBps > 30) safety += 5;
            if (s.spreadBps > 50) safety += 10;
        }

        feeBps = exec + impact + delay + basis + funding + exhaust + invSkew + exhaustionKnee + safety;
    }

    /// @notice Blended fee: `unwindFrac * unwindBps + (1−unwindFrac) * clamp(newRisk,10,60)`, then `min(60,…)`.
    /// @dev If the hedge **crosses zero** (long→short or short→long) in one quote, fee is the **path integral**
    ///      average (unwind 0→10 bps marginal + new-risk 10→60 marginal), not the `unwindFrac` blend.
    function blendedQuoteBpsHtml(
        BalanceSheet memory s,
        DeltaFlowFeeMath.FeeParams memory p,
        uint256 tradeNotionalWad,
        bool volatileRegime,
        bool useMarketRiskComponent,
        int256 perpPre,
        int256 deltaSz,
        uint256 hMaxSz,
        uint256 poolNavWad
    ) internal pure returns (uint256 rawBps) {
        uint256 absPre = absInt(perpPre);
        int256 hPost = perpPre + deltaSz;
        uint256 absPost = absInt(hPost);

        uint256 utilPre = hMaxSz == 0 ? WAD : Math.min(WAD, Math.mulDiv(absPre, WAD, hMaxSz));
        uint256 utilPost = hMaxSz == 0 ? WAD : Math.min(WAD, Math.mulDiv(absPost, WAD, hMaxSz));

        bool crossesZero = (perpPre > 0 && hPost < 0) || (perpPre < 0 && hPost > 0);
        if (crossesZero) {
            return hedgeCrossingPathAvgBps(utilPre, utilPost);
        }

        bool reduces = absPost < absPre;
        uint256 unwindFrac = 0;
        if (reduces && absPre > 0) {
            unwindFrac = Math.mulDiv(absPre - absPost, WAD, absPre);
        }

        uint256 unwindBps = unwindFeeBpsIntegral(utilPre, utilPost);

        uint256 nr = newRiskFeeBpsHtml(
            s, p, tradeNotionalWad, volatileRegime, useMarketRiskComponent, absPost, hMaxSz, poolNavWad
        );
        uint256 nrClamped = Math.max(10, nr);

        rawBps = Math.mulDiv(unwindFrac, unwindBps, WAD) + Math.mulDiv(WAD - unwindFrac, nrClamped, WAD);
    }
}
