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

    function fifthRootWad(uint256 t) internal pure returns (uint256 y) {
        if (t == 0) return 0;
        y = t;
        for (uint256 i = 0; i < 16; i++) {
            uint256 y4 = _pow4(y);
            if (y4 == 0) break;
            uint256 term = Math.mulDiv(t, WAD * WAD * WAD * WAD, y4);
            y = (4 * y + term) / 5;
        }
    }

    function _pow4(uint256 y) internal pure returns (uint256) {
        uint256 y2 = Math.mulDiv(y, y, WAD);
        return Math.mulDiv(y2, y2, WAD);
    }

    /// @dev `((t/WAD)^2.2) * WAD` for `t = (1−u)·WAD`.
    function pow22FromTWad(uint256 t) internal pure returns (uint256) {
        if (t == 0) return 0;
        uint256 r = fifthRootWad(t);
        uint256 t2 = Math.mulDiv(t, t, WAD);
        return Math.mulDiv(t2, r, WAD);
    }

    /// @dev Unwind average → **integer bips** (~2–8): `2.5 + (5.5/2.2)·Δ((1−u)^2.2)/Δu` (tenths rounded).
    function unwindFeeBpsIntegral(uint256 utilPreWad, uint256 utilPostWad) internal pure returns (uint256) {
        if (utilPreWad <= utilPostWad) return 3;
        uint256 du = utilPreWad - utilPostWad;
        uint256 tPre = WAD - utilPreWad;
        uint256 tPost = WAD - utilPostWad;
        uint256 a = pow22FromTWad(tPost);
        uint256 b = pow22FromTWad(tPre);
        uint256 tenths;
        if (du < 10) {
            tenths = 25 + Math.mulDiv(55, WAD - utilPostWad, WAD);
        } else if (a <= b) {
            tenths = 25;
        } else {
            uint256 delta = a - b;
            tenths = 25 + Math.mulDiv(55, Math.mulDiv(delta, WAD, du), 22);
        }
        if (tenths > 80) tenths = 80;
        return (tenths + 5) / 10; // integer bips
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

        bool reduces = absPost < absPre;
        uint256 unwindFrac = 0;
        if (reduces && absPre > 0) {
            unwindFrac = Math.mulDiv(absPre - absPost, WAD, absPre);
        }

        uint256 utilPre = hMaxSz == 0 ? WAD : Math.min(WAD, Math.mulDiv(absPre, WAD, hMaxSz));
        uint256 utilPost = hMaxSz == 0 ? WAD : Math.min(WAD, Math.mulDiv(absPost, WAD, hMaxSz));

        uint256 unwindBps = unwindFeeBpsIntegral(utilPre, utilPost);

        uint256 nr = newRiskFeeBpsHtml(
            s, p, tradeNotionalWad, volatileRegime, useMarketRiskComponent, absPost, hMaxSz, poolNavWad
        );
        uint256 nrClamped = Math.max(10, nr);

        rawBps = Math.mulDiv(unwindFrac, unwindBps, WAD) + Math.mulDiv(WAD - unwindFrac, nrClamped, WAD);
    }
}
