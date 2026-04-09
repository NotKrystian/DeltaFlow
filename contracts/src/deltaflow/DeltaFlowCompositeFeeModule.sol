// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {ISwapFeeModule, SwapFeeModuleData} from "../swap-fee-modules/interfaces/ISwapFeeModule.sol";

import {BalanceSheet} from "./DeltaFlowTypes.sol";
import {BalanceSheetLib} from "./BalanceSheetLib.sol";
import {DeltaFlowFeeMath} from "./DeltaFlowFeeMath.sol";
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
contract DeltaFlowCompositeFeeModule is ISwapFeeModule {
    uint256 internal constant WAD = 1e18;

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
        bool _volatileRegimeFlag
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
        uint256 px = BalanceSheetLib.pxUsdcPerBase(usdcDec, spotIndex, rawPxScale, rawIsPurrPerUsdc);

        uint256 tradeNotionalWad = tokenIn == usdc
            ? Math.mulDiv(amountIn, WAD, 10 ** uint256(usdcDec))
            : BalanceSheetLib.usdcValueWadOfBase(amountIn, baseDec, px, usdcDec);

        bool unwind = _isUnwind(tokenIn, sheet.perpSzi);
        bool newRisk = !unwind;

        uint256 uPre = capacityWad > 0 ? Math.min(WAD, Math.mulDiv(sheet.shortfallWad, WAD, capacityWad)) : 0;
        uint256 uPost = capacityWad > 0
            ? Math.min(WAD, Math.mulDiv(sheet.shortfallWad + tradeNotionalWad / 10, WAD, capacityWad))
            : 0;

        uint256 rawBps = unwind
            ? DeltaFlowFeeMath.unwindFeeBps(uPre, uPost)
            : DeltaFlowFeeMath.computeNewRiskFeeBps(sheet, feeParams, tradeNotionalWad, volatileRegimeFlag);

        if (rawBps < 10 && !unwind) {
            rawBps = 10;
        }

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

    /// @dev Heuristic: user sells base into pool while perp long → unwind; user buys base while perp short → unwind.
    function _isUnwind(address tokenIn, int256 szi) internal view returns (bool) {
        if (tokenIn == base && szi > 0) return true;
        if (tokenIn == usdc && szi < 0) return true;
        return false;
    }
}
