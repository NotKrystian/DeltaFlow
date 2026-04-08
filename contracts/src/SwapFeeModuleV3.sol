// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {ISwapFeeModule, SwapFeeModuleData} from "./swap-fee-modules/interfaces/ISwapFeeModule.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {PrecompileLib} from "@hyper-evm-lib/src/PrecompileLib.sol";

/*//////////////////////////////////////////////////////////////
                        Minimal Pool Interface
//////////////////////////////////////////////////////////////*/
interface ISovereignPoolLite {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function sovereignVault() external view returns (address);
}

/**
 * BalanceSeekingSwapFeeModuleV3 (decimals-correct, vault-based)
 *
 * Uses the same spot price convention as SovereignALM: `pxUSDCperBase` in USDC raw units per 1 whole base token.
 * The immutable `purr` is the non-USDC side (PURR, WETH, etc.).
 * Imbalance fee: raw USDC vault balance vs base holdings valued at spot (aligned with ALM).
 */
contract BalanceSeekingSwapFeeModuleV3 is ISwapFeeModule {
    address public immutable sovereignPool;
    address public immutable usdc;
    /// @notice Non-USDC / base token (historically named `purr`).
    address public immutable purr;

    uint8 public immutable usdcDec;
    uint8 public immutable baseDec;

    uint256 public immutable baseFeeBips;
    uint256 public immutable minFeeBips;
    uint256 public immutable maxFeeBips;

    uint256 public immutable liquidityBufferBps;

    uint64 public immutable spotIndexPURR;
    uint256 public immutable rawPxScale;
    bool public immutable rawIsPurrPerUsdc;

    uint256 private constant BIPS = 10_000;

    error PoolPairMismatch(address token0, address token1);
    error ZeroVaultBalance(address vault, address token);
    error InsufficientVaultLiquidity(address vault, address tokenOut, uint256 balOut, uint256 neededOut);
    error PriceZero();

    constructor(
        address _sovereignPool,
        address _usdc,
        address _purr,
        uint64 _spotIndexPURR,
        uint256 _rawPxScale,
        bool _rawIsPurrPerUsdc,
        uint256 _baseFeeBips,
        uint256 _minFeeBips,
        uint256 _maxFeeBips,
        uint256 _liquidityBufferBps
    ) {
        require(_sovereignPool != address(0), "POOL_ZERO");
        require(_usdc != address(0) && _purr != address(0), "TOKEN_ZERO");
        require(_usdc != _purr, "SAME_TOKEN");
        require(_rawPxScale > 0, "SCALE_0");

        require(_minFeeBips <= _baseFeeBips, "MIN_GT_BASE");
        require(_baseFeeBips <= _maxFeeBips, "BASE_GT_MAX");
        require(_maxFeeBips <= BIPS, "MAX_TOO_HIGH");
        require(_liquidityBufferBps <= 5_000, "BUF_TOO_HIGH");

        sovereignPool = _sovereignPool;
        usdc = _usdc;
        purr = _purr;

        usdcDec = IERC20Metadata(_usdc).decimals();
        baseDec = IERC20Metadata(_purr).decimals();

        spotIndexPURR = _spotIndexPURR;
        rawPxScale = _rawPxScale;
        rawIsPurrPerUsdc = _rawIsPurrPerUsdc;

        baseFeeBips = _baseFeeBips;
        minFeeBips = _minFeeBips;
        maxFeeBips = _maxFeeBips;

        liquidityBufferBps = _liquidityBufferBps;
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
            data.feeInBips = _clampFee(baseFeeBips);
            return data;
        }

        ISovereignPoolLite pool = ISovereignPoolLite(sovereignPool);
        address vault = pool.sovereignVault();

        address t0 = pool.token0();
        address t1 = pool.token1();

        bool pairOk = (t0 == usdc && t1 == purr) || (t0 == purr && t1 == usdc);
        if (!pairOk) revert PoolPairMismatch(t0, t1);

        bool isValidSwap =
            (tokenIn == t0 || tokenIn == t1) &&
            (tokenOut == t0 || tokenOut == t1) &&
            (tokenIn != tokenOut);

        if (!isValidSwap) {
            data.feeInBips = _clampFee(baseFeeBips);
            return data;
        }

        uint256 U = IERC20Metadata(usdc).balanceOf(vault);
        uint256 P = IERC20Metadata(purr).balanceOf(vault);
        if (U == 0) revert ZeroVaultBalance(vault, usdc);
        if (P == 0) revert ZeroVaultBalance(vault, purr);

        uint256 px = _pxUSDCperBase();

        uint256 estOutRaw = _estimateOutAtSpotRaw(tokenIn, tokenOut, amountIn, px);
        if (estOutRaw > 0) {
            uint256 needed = Math.mulDiv(estOutRaw, (BIPS + liquidityBufferBps), BIPS);
            uint256 balOut = IERC20Metadata(tokenOut).balanceOf(vault);
            if (balOut < needed) revert InsufficientVaultLiquidity(vault, tokenOut, balOut, needed);
        }

        uint256 left = U;
        uint256 right = Math.mulDiv(P, px, _pow10(baseDec));

        if (right == 0) {
            data.feeInBips = _clampFee(baseFeeBips);
            return data;
        }

        uint256 diff = left > right ? (left - right) : (right - left);
        uint256 devBps = Math.mulDiv(diff, BIPS, right);

        uint256 feeAddBps = (devBps / 10);
        uint256 fee = baseFeeBips + feeAddBps;

        data.feeInBips = _clampFee(fee);
        return data;
    }

    function callbackOnSwapEnd(uint256, int24, uint256, uint256, SwapFeeModuleData memory) external pure override {}
    function callbackOnSwapEnd(uint256, uint256, uint256, SwapFeeModuleData memory) external pure override {}

    function _clampFee(uint256 fee) internal view returns (uint256) {
        if (fee < minFeeBips) return minFeeBips;
        if (fee > maxFeeBips) return maxFeeBips;
        return fee;
    }

    function _pow10(uint8 n) internal pure returns (uint256) {
        return 10 ** uint256(n);
    }

    /// @dev Same convention as SovereignALM.getSpotPriceUSDCperPURR.
    function _pxUSDCperBase() internal view returns (uint256 pxUSDCperBase) {
        uint256 raw = PrecompileLib.normalizedSpotPx(spotIndexPURR);
        if (raw == 0) revert PriceZero();

        uint256 USDC_SCALE = _pow10(usdcDec);

        if (!rawIsPurrPerUsdc) {
            pxUSDCperBase = Math.mulDiv(raw, USDC_SCALE, rawPxScale);
        } else {
            pxUSDCperBase = Math.mulDiv(USDC_SCALE, rawPxScale, raw);
        }

        if (pxUSDCperBase == 0) revert PriceZero();
    }

    function _estimateOutAtSpotRaw(
        address tokenIn,
        address tokenOut,
        uint256 amountInRaw,
        uint256 pxUSDCperBase
    ) internal view returns (uint256) {
        uint256 BASE_SCALE = _pow10(baseDec);

        if (tokenIn == usdc && tokenOut == purr) {
            return Math.mulDiv(amountInRaw, BASE_SCALE, pxUSDCperBase);
        }

        if (tokenIn == purr && tokenOut == usdc) {
            return Math.mulDiv(amountInRaw, pxUSDCperBase, BASE_SCALE);
        }

        return 0;
    }
}
