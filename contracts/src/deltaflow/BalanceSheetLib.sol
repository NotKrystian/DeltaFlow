// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {PrecompileLib} from "@hyper-evm-lib/src/PrecompileLib.sol";
import {HLConversions} from "@hyper-evm-lib/src/common/HLConversions.sol";

import {BalanceSheet} from "./DeltaFlowTypes.sol";

/// @title BalanceSheetLib
/// @notice Aggregates EVM ERC-20 balances on `account` with HyperCore spot + optional perp.
library BalanceSheetLib {
    uint256 internal constant WAD = 1e18;

    /// @param perpIndex Hyperliquid perp index; `type(uint32).max` skips perp reads.
    /// @param spotAssetForBBO Pass `uint32(uint256(10000) + spotIndex)` for spot; 0 skips spread.
    /// @param pendingHedgeBuySz / pendingHedgeSellSz HL `sz` queued in `SovereignVault` before IOC (0 if N/A).
    function snapshot(
        address account,
        address usdc,
        address base,
        uint32 perpIndex,
        uint64 spotIndex,
        uint256 capacityWad,
        uint32 spotAssetForBBO,
        uint256 rawPxScale,
        bool rawIsPurrPerUsdc,
        uint256 pendingHedgeBuySz,
        uint256 pendingHedgeSellSz
    ) internal view returns (BalanceSheet memory s) {
        uint8 usdcDec = IERC20Metadata(usdc).decimals();
        uint8 baseDec = IERC20Metadata(base).decimals();

        s.evmUsdc = IERC20Metadata(usdc).balanceOf(account);
        s.evmBase = IERC20Metadata(base).balanceOf(account);

        uint64 usdcIx = PrecompileLib.getTokenIndex(usdc);
        uint64 baseIx = PrecompileLib.getTokenIndex(base);

        PrecompileLib.SpotBalance memory csu = PrecompileLib.spotBalance(account, usdcIx);
        PrecompileLib.SpotBalance memory csb = PrecompileLib.spotBalance(account, baseIx);
        s.coreUsdc = HLConversions.weiToEvm(usdc, csu.total);
        s.coreBase = HLConversions.weiToEvm(base, csb.total);

        if (perpIndex != type(uint32).max) {
            PrecompileLib.Position memory p = PrecompileLib.position(account, uint16(perpIndex));
            s.perpSzi = int256(int64(p.szi)) + int256(pendingHedgeBuySz) - int256(pendingHedgeSellSz);
            s.markPxNormalized = PrecompileLib.normalizedMarkPx(perpIndex);
        }

        s.spotPxNormalized = PrecompileLib.normalizedSpotPx(spotIndex);

        uint256 totalUsdc = s.evmUsdc + s.coreUsdc;
        uint256 totalBase = s.evmBase + s.coreBase;

        uint256 px = pxUsdcPerBase(usdcDec, spotIndex, rawPxScale, rawIsPurrPerUsdc);
        uint256 baseUsdcVal = px == 0 ? 0 : Math.mulDiv(totalBase, px, 10 ** uint256(baseDec));
        s.navWad = Math.mulDiv(totalUsdc + baseUsdcVal, WAD, 10 ** uint256(usdcDec));

        if (capacityWad > 0 && totalBase > 0) {
            uint256 baseWad = Math.mulDiv(totalBase, WAD, 10 ** uint256(baseDec));
            if (baseWad > capacityWad) {
                s.shortfallWad = baseWad - capacityWad;
            }
        }

        if (spotAssetForBBO != 0) {
            PrecompileLib.Bbo memory b = PrecompileLib.bbo(uint64(spotAssetForBBO));
            if (b.bid > 0 && b.ask > 0) {
                uint256 mid = uint256(b.bid + b.ask) / 2;
                if (mid > 0) {
                    s.spreadBps = (uint256(b.ask) - uint256(b.bid)) * 10_000 / mid;
                }
            }
        }
    }

    function pxUsdcPerBase(uint8 usdcDec, uint64 spotIndex, uint256 rawPxScale, bool rawIsPurrPerUsdc)
        internal
        view
        returns (uint256)
    {
        uint256 raw = PrecompileLib.normalizedSpotPx(spotIndex);
        if (raw == 0) return 0;
        uint256 USDC_SCALE = 10 ** uint256(usdcDec);
        if (!rawIsPurrPerUsdc) {
            return Math.mulDiv(raw, USDC_SCALE, rawPxScale);
        }
        return Math.mulDiv(USDC_SCALE, rawPxScale, raw);
    }

    function usdcValueWadOfBase(uint256 baseAmount, uint8 baseDec, uint256 pxUsdcPerBase_, uint8 usdcDec)
        internal
        pure
        returns (uint256)
    {
        uint256 usdcVal = Math.mulDiv(baseAmount, pxUsdcPerBase_, 10 ** uint256(baseDec));
        return Math.mulDiv(usdcVal, WAD, 10 ** uint256(usdcDec));
    }
}
