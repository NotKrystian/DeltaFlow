// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {HLConversions} from "@hyper-evm-lib/src/common/HLConversions.sol";
import {PrecompileLib} from "@hyper-evm-lib/src/PrecompileLib.sol";

import {ISwapFeeModule, SwapFeeModuleData} from "../swap-fee-modules/interfaces/ISwapFeeModule.sol";

import {BalanceSheet} from "./DeltaFlowTypes.sol";
import {BalanceSheetLib} from "./BalanceSheetLib.sol";
import {DeltaFlowFeeMath} from "./DeltaFlowFeeMath.sol";
import {DeltaFeeHelper} from "./DeltaFeeHelper.sol";
import {DeltaFlowRiskEngine} from "./DeltaFlowRiskEngine.sol";
import {FeeSurplus} from "./FeeSurplus.sol";

interface ISovereignPoolLite {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function sovereignVault() external view returns (address);
}

interface IVaultHedgePending {
    function pendingHedgeBuySz() external view returns (uint256);
    function pendingHedgeSellSz() external view returns (uint256);
}

/// @title DeltaFlowCompositeFeeModule
/// @notice Risk engine + memo-style fee components; balance sheet = EVM + HyperCore spot + optional perp.
/// @dev Unwind vs new-risk blend uses `DeltaFeeHelper.blendedQuoteBpsHtml` when market-risk components are enabled.
///      In concentration-only mode, this module still applies unwind blending so reduce-only flow can get lower fees.
///      `SovereignVault.lastHedgeLeg` mirrors IOC legs (open / reduce-only / both) for ops; fee quote uses the balance sheet, not `lastHedgeLeg` directly.
contract DeltaFlowCompositeFeeModule is ISwapFeeModule {
    uint256 internal constant WAD = 1e18;
    uint256 internal constant BIPS = 10_000;

    address public immutable sovereignPool;
    address public immutable usdc;
    address public immutable base;

    uint64 public immutable spotIndex;
    uint256 public immutable rawPxScale;
    bool public immutable rawIsPurrPerUsdc;

    uint32 public immutable perpIndex;
    uint32 public immutable spotAssetForBBO;
    uint256 public immutable capacityWad;

    DeltaFlowRiskEngine public immutable riskEngine;
    FeeSurplus public immutable surplus;
    uint256 public immutable surplusFractionBps;

    DeltaFlowFeeMath.FeeParams public feeParams;
    bool public immutable volatileRegimeFlag;
    bool public immutable useMarketRiskComponent;
    bool public immutable usePerpPriceForFee;

    error Composite__PairMismatch();

    constructor(
        address _pool,
        address _usdc,
        address _base,
        uint64 _spotIndex,
        uint256 _rawPxScale,
        bool _rawIsPurrPerUsdc,
        uint32 _perpIndex,
        uint32 _spotAssetForBBO,
        uint256 _capacityWad,
        DeltaFlowRiskEngine _risk,
        FeeSurplus _surplus,
        uint256 _surplusFractionBps,
        DeltaFlowFeeMath.FeeParams memory _feeParams,
        bool _volatileRegimeFlag,
        bool _useMarketRiskComponent,
        bool _usePerpPriceForFee
    ) {
        sovereignPool = _pool;
        usdc = _usdc;
        base = _base;
        spotIndex = _spotIndex;
        rawPxScale = _rawPxScale;
        rawIsPurrPerUsdc = _rawIsPurrPerUsdc;
        perpIndex = _perpIndex;
        spotAssetForBBO = _spotAssetForBBO;
        capacityWad = _capacityWad;
        riskEngine = _risk;
        surplus = _surplus;
        surplusFractionBps = _surplusFractionBps;
        feeParams = _feeParams;
        volatileRegimeFlag = _volatileRegimeFlag;
        useMarketRiskComponent = _useMarketRiskComponent;
        usePerpPriceForFee = _usePerpPriceForFee;
    }

    function getSwapFeeInBips(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        address,
        bytes memory
    ) external view override returns (SwapFeeModuleData memory data) {
        data.internalContext = "";

        if (amountIn == 0) {
            data.feeInBips = 10;
            return data;
        }

        ISovereignPoolLite pool = ISovereignPoolLite(sovereignPool);
        address vault = pool.sovereignVault();
        address t0 = pool.token0();
        address t1 = pool.token1();

        bool pathOk = (tokenIn == t0 || tokenIn == t1) && (tokenOut == t0 || tokenOut == t1) && tokenIn != tokenOut;
        if (!pathOk) {
            data.feeInBips = 10;
            return data;
        }

        if (!((t0 == usdc && t1 == base) || (t0 == base && t1 == usdc))) revert Composite__PairMismatch();

        BalanceSheet memory sheet = BalanceSheetLib.snapshot(
            vault,
            usdc,
            base,
            perpIndex,
            spotIndex,
            capacityWad,
            spotAssetForBBO,
            rawPxScale,
            rawIsPurrPerUsdc,
            IVaultHedgePending(vault).pendingHedgeBuySz(),
            IVaultHedgePending(vault).pendingHedgeSellSz()
        );

        uint8 usdcDec = IERC20Metadata(usdc).decimals();
        uint8 baseDec = IERC20Metadata(base).decimals();
        uint256 px = _pxUsdcPerBase(usdcDec);

        uint256 tradeNotionalWad = tokenIn == usdc
            ? Math.mulDiv(amountIn, WAD, 10 ** uint256(usdcDec))
            : BalanceSheetLib.usdcValueWadOfBase(amountIn, baseDec, px, usdcDec);

        // Net trade size for hedge `sz` delta (10 bps conservative seed → amountInNet).
        uint256 amountInNet = Math.mulDiv(amountIn, BIPS, BIPS + 10);
        int256 deltaSz = _estimatePerpDeltaSz(tokenIn, tokenOut, amountInNet, px, baseDec);
        uint256 absPre = DeltaFeeHelper.absInt(sheet.perpSzi);
        int256 hPost = sheet.perpSzi + deltaSz;
        uint256 absPost = DeltaFeeHelper.absInt(hPost);

        DeltaFlowFeeMath.FeeParams memory p = feeParams;

        uint256 rawBps;
        if (useMarketRiskComponent) {
            rawBps = DeltaFeeHelper.blendedQuoteBpsHtml(
                sheet,
                p,
                tradeNotionalWad,
                volatileRegimeFlag,
                useMarketRiskComponent,
                sheet.perpSzi,
                deltaSz,
                p.hMaxSz,
                p.poolNavWad
            );
        } else {
            uint256 concBps = _concentrationFeeBps(sheet, tokenIn, tokenOut, amountInNet, px, baseDec);
            rawBps = _blendConcentrationWithUnwind(p.hMaxSz, absPre, absPost, concBps);
        }

        bool unwind = absPost < absPre;
        bool newRisk = !unwind;

        riskEngine.validate(sheet, rawBps, unwind, newRisk);

        data.feeInBips = riskEngine.capDisplayedFee(rawBps);
        data.internalContext = abi.encode(rawBps);
    }

    function callbackOnSwapEnd(uint256, int24, uint256, uint256, SwapFeeModuleData memory) external pure override {}

    function callbackOnSwapEnd(
        uint256 effectiveFee,
        uint256,
        uint256,
        SwapFeeModuleData memory feeData
    ) external override {
        if (address(surplus) == address(0) || surplusFractionBps == 0) return;
        if (keccak256(feeData.internalContext) == keccak256(new bytes(0))) return;
        if (msg.sender != sovereignPool) return;

        uint256 slice = (effectiveFee * surplusFractionBps) / 10_000;
        if (slice > 0) {
            surplus.accrueFromPool(slice);
        }
    }

    /// @dev Apply memo-style unwind fraction blend in concentration-only mode.
    function _blendConcentrationWithUnwind(
        uint256 hMaxSz,
        uint256 absPre,
        uint256 absPost,
        uint256 concBps
    ) internal pure returns (uint256) {
        if (absPre == 0 || absPost >= absPre) return concBps;
        uint256 unwindFrac = Math.mulDiv(absPre - absPost, WAD, absPre);
        uint256 utilPre = hMaxSz == 0 ? WAD : Math.min(WAD, Math.mulDiv(absPre, WAD, hMaxSz));
        uint256 utilPost = hMaxSz == 0 ? WAD : Math.min(WAD, Math.mulDiv(absPost, WAD, hMaxSz));
        uint256 unwindBps = DeltaFeeHelper.unwindFeeBpsIntegral(utilPre, utilPost);
        uint256 unwindWeight = _inverseExpUnwindWeightWad(unwindFrac);
        return Math.mulDiv(unwindWeight, unwindBps, WAD) + Math.mulDiv(WAD - unwindWeight, concBps, WAD);
    }

    /// @dev Inverse-exponential unwind weighting over [0,1]:
    ///      w(u) = 1 - (1-u)^3, where u = unwind fraction.
    ///      This strongly favors unwind pricing as u approaches 1 (near full unhedge).
    function _inverseExpUnwindWeightWad(uint256 unwindFracWad) internal pure returns (uint256) {
        if (unwindFracWad == 0) return 0;
        if (unwindFracWad >= WAD) return WAD;
        uint256 oneMinus = WAD - unwindFracWad;
        uint256 oneMinus2 = Math.mulDiv(oneMinus, oneMinus, WAD);
        uint256 oneMinus3 = Math.mulDiv(oneMinus2, oneMinus, WAD);
        return WAD - oneMinus3;
    }

    /// @dev Estimated HL `sz` delta from this swap (buy base → add long hedge sz; sell base → reduce).
    function _estimatePerpDeltaSz(
        address tokenIn,
        address tokenOut,
        uint256 amountInNet,
        uint256 px,
        uint8 baseDec
    ) internal view returns (int256) {
        if (tokenIn == usdc && tokenOut == base) {
            uint256 outWei = Math.mulDiv(amountInNet, 10 ** uint256(baseDec), px);
            if (outWei == 0) return 0;
            uint64 sz = _baseWeiToPerpSz(outWei);
            return int256(uint256(sz));
        }
        if (tokenIn == base && tokenOut == usdc) {
            uint64 sz = _baseWeiToPerpSz(amountInNet);
            return -int256(uint256(sz));
        }
        return 0;
    }

    /// @dev Convert base amount in EVM wei to perp sz using perp asset `szDecimals`.
    function _baseWeiToPerpSz(uint256 baseAmountWei) internal view returns (uint64) {
        if (baseAmountWei == 0) return 0;
        uint64 tokenIx = PrecompileLib.getTokenIndex(base);
        uint8 weiDec = PrecompileLib.tokenInfo(uint32(tokenIx)).weiDecimals;
        uint8 perpSzDec = PrecompileLib.perpAssetInfo(perpIndex).szDecimals;
        uint64 coreWei = HLConversions.evmToWei(tokenIx, baseAmountWei);
        if (weiDec >= perpSzDec) {
            return coreWei / uint64(10 ** uint256(weiDec - perpSzDec));
        }
        uint256 up = uint256(coreWei) * (10 ** uint256(perpSzDec - weiDec));
        if (up > type(uint64).max) return type(uint64).max;
        return uint64(up);
    }

    /// @dev Canonical USDC-per-base px, using perp mark when configured.
    function _pxUsdcPerBase(uint8 usdcDec) internal view returns (uint256) {
        if (usePerpPriceForFee) {
            uint256 rawMark = PrecompileLib.normalizedMarkPx(perpIndex);
            if (rawMark == 0) return 0;
            return Math.mulDiv(rawMark, 10 ** uint256(usdcDec), 1_000_000);
        }
        return BalanceSheetLib.pxUsdcPerBase(usdcDec, spotIndex, rawPxScale, rawIsPurrPerUsdc);
    }

    /// @dev Testnet-friendly dynamic curve: fee expands exponentially with post-trade concentration and
    ///      reaches 60 bps at 100/0 concentration, with 10 bps floor at 50/50.
    function _concentrationFeeBps(
        BalanceSheet memory sheet,
        address tokenIn,
        address tokenOut,
        uint256 amountInNet,
        uint256 px,
        uint8 baseDec
    ) internal view returns (uint256) {
        uint256 usdcPost = sheet.evmUsdc + sheet.coreUsdc;
        uint256 basePost = sheet.evmBase + sheet.coreBase;

        if (px == 0) return 10;

        if (tokenIn == usdc && tokenOut == base) {
            usdcPost += amountInNet;
            uint256 baseOut = Math.mulDiv(amountInNet, 10 ** uint256(baseDec), px);
            basePost = baseOut >= basePost ? 0 : (basePost - baseOut);
        } else if (tokenIn == base && tokenOut == usdc) {
            basePost += amountInNet;
            uint256 usdcOut = Math.mulDiv(amountInNet, px, 10 ** uint256(baseDec));
            usdcPost = usdcOut >= usdcPost ? 0 : (usdcPost - usdcOut);
        }

        uint256 baseValUsdcRaw = Math.mulDiv(basePost, px, 10 ** uint256(baseDec));
        uint256 totalValUsdcRaw = usdcPost + baseValUsdcRaw;
        if (totalValUsdcRaw == 0) return 10;

        // c = |U - B| / (U + B) in [0,1] WAD; 0 at 50/50 and 1 at 100/0.
        uint256 diff = usdcPost > baseValUsdcRaw ? (usdcPost - baseValUsdcRaw) : (baseValUsdcRaw - usdcPost);
        uint256 cWad = Math.mulDiv(diff, WAD, totalValUsdcRaw);
        uint256 cExpWad = _expConcentrationCurveWad(cWad); // exponential expansion in [0, WAD]

        uint256 minBps = 10;
        uint256 maxBps = 60;
        return minBps + Math.mulDiv(maxBps - minBps, cExpWad, WAD);
    }

    /// @dev Exponential concentration curve on [0,1]: (e^(k*c)-1)/(e^k-1), k=2.
    function _expConcentrationCurveWad(uint256 cWad) internal pure returns (uint256) {
        if (cWad == 0) return 0;
        if (cWad >= WAD) return WAD;

        uint256 k = 2 * WAD;
        uint256 x = Math.mulDiv(k, cWad, WAD);
        uint256 num = _expWad(x) - WAD;
        uint256 den = _expWad(k) - WAD;
        if (den == 0) return cWad;
        return Math.min(WAD, Math.mulDiv(num, WAD, den));
    }

    /// @dev Small bounded exp approximation for x in WAD scale.
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
