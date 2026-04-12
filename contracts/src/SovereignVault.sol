// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ISovereignVaultMinimal} from "./interfaces/ISovereignVaultMinimal.sol";
import {ISovereignPool} from "./interfaces/ISovereignPool.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {CoreWriterLib} from "@hyper-evm-lib/src/CoreWriterLib.sol";
import {HLConversions} from "@hyper-evm-lib/src/common/HLConversions.sol";
import {HLConstants} from "@hyper-evm-lib/src/common/HLConstants.sol";
import {PrecompileLib} from "@hyper-evm-lib/src/PrecompileLib.sol";

/// @dev Minimal interface so the vault can read the spot price from the ALM
///      without importing the full ALM contract.
interface ISpotPricer {
    function getSpotPriceUsdcPerBase() external view returns (uint256);
}

contract SovereignVault is ISovereignVaultMinimal, ERC20, ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 public constant MINIMUM_LIQUIDITY = 1_000;
    /// @dev Maximum allowed imbalance between the USDC and PURR sides of the first deposit,
    ///      expressed in basis points. Enforces a delta-neutral starting state.
    uint256 public constant FIRST_DEPOSIT_MAX_IMBALANCE_BPS = 100; // 1%

    address public immutable strategist;
    address public immutable usdc;
    address public immutable purr;
    uint8 public immutable usdcDec;
    uint8 public immutable purrDec;
    address public foundation;

    address public defaultVault;
    uint256 totalAllocatedUSDC;

    /// @notice Address of the deployed ALM. Used only for spot price reads on
    ///         single-sided deposits. Set by the strategist after ALM deployment.
    address public alm;

    mapping(address => bool) public authorizedPools;

    // Ordered list of core vaults that have ever received an allocation.
    // Used to enumerate vaults for automatic equity sync on LP deposit/withdraw.
    address[] public coreVaultsList;
    mapping(address => bool) private _coreVaultTracked;

    error OnlyAuthorizedPool();
    error OnlyStrategist();
    error InsufficientBuffer();
    error InsufficientFundsAfterWithdraw();
    error LP__ZeroAmount();
    error LP__FirstDepositRequiresBothTokens();
    error LP__FirstDepositImbalanced(uint256 usdcValue, uint256 purrValue);
    error LP__AlmNotSet();
    error LP__InsufficientShares(uint256 got, uint256 min);
    error LP__InsufficientUsdcOut(uint256 got, uint256 min);
    error LP__InsufficientPurrOut(uint256 got, uint256 min);
    error LP__InsufficientEvmUsdc(uint256 available, uint256 needed);
    error HedgeBatchTooLarge();
    /// @dev Vault EVM USDC lower than USDC notionally required to fund perp margin for this hedge `sz`.
    error InsufficientUSDCForHedge(uint256 required, uint256 available);
    /// @dev `normalizedMarkPx(perpIx) == 0` — cannot size USDC margin for the IOC.
    error HedgeMarkPxZero();
    /// @dev Bridged USDC rounds to zero `transferUsdClass` units — increase trade size or USDC amount.
    error HedgePerpNtlDust();
    error PerpIndexTooLarge();
    error BootstrapAmountTooSmall(uint256 minAmount, uint256 got);
    error ZeroAmount();
    error FoundationZeroAddress();

    event LiquidityAdded(address indexed provider, uint256 usdcAmount, uint256 purrAmount, uint256 shares);
    event LiquidityRemoved(address indexed provider, uint256 usdcOut, uint256 purrOut, uint256 shares);
    event BridgedToCore(address indexed token, uint256 amount);
    event BridgedToEvm(address indexed token, uint256 amount);
    event CoreVaultMoved(address indexed coreVault, bool isDeposit, uint256 amount);
    event CoreAllocationsSynced(uint256 oldTotal, uint256 newTotal);
    event SwapHedgeExecuted(uint32 indexed perpAsset, bool vaultPurrOut, uint256 purrAmountWei, uint64 sz);
    /// @notice Emitted when a slice is merged into the perp hedge queue (HL `sz` units).
    event HedgeSliceQueued(bool indexed buyPerp, uint64 sz, uint256 pendingBuySz, uint256 pendingSellSz);
    /// @notice Emitted when a batch IOC is sent (one or many swaps combined).
    event HedgeBatchExecuted(uint32 indexed perpAsset, bool indexed buyPerp, uint256 totalSz);
    event HypeBridgedToCore(uint256 weiAmount);
    event FoundationSet(address indexed foundation);
    event FoundationFeeLpMinted(address indexed feeToken, uint256 feeAmount, uint256 mintedShares);

    /// @notice Last perp hedge leg from `_netHedgePosition` (mirrors memo unwind vs open; fee module uses balance-sheet `unwind` blend separately).
    ///         0=None, 1=OpenOnly, 2=UnwindOnly (reduce-only), 3=UnwindThenOpen.
    uint8 public lastHedgeLeg;

    /// @dev Minimum USDC (6-decimal wei) for `bootstrapHyperCoreAccount` — HyperCore account creation / first spot funding.
    uint256 public constant MIN_CORE_BOOTSTRAP_USDC = 1_000_000;

    mapping(address => uint256) public allocatedToCoreVault;

    /// @notice HyperCore perp asset index for swap hedges (PURR perp). 0 = disabled (no CoreWriter call).
    uint32 public hedgePerpAssetIndex;

    /// @notice When true, batching threshold uses HL ~\$10 min notional from `normalizedMarkPx` + `szDecimals` (with `minPerpHedgeSz` as floor). When false, `minPerpHedgeSz` is the fixed threshold.
    bool public useMarkBasedMinHedgeSz;

    /// @notice Minimum HL perp order size (`sz` units) before sending an IOC when not using mark-based mode; when using mark-based mode, acts as a floor on the computed threshold. Batching is off iff `!useMarkBasedMinHedgeSz && minPerpHedgeSz == 0`.
    uint64 public minPerpHedgeSz;

    /// @dev HL perp min notional ≈ \$10 in the same 1e6 units as `PrecompileLib.normalizedMarkPx`.
    uint256 internal constant MIN_PERP_NOTIONAL_USD_1E6 = 10 * 1_000_000;

    /// @notice Pending hedge size (HL `sz`) for long-perp hedges (vault paid PURR on swaps).
    uint256 public pendingHedgeBuySz;

    /// @notice Pending hedge size (HL `sz`) for short-perp hedges (vault received PURR on swaps).
    uint256 public pendingHedgeSellSz;

    /// @notice Sub-`sz` base-wei remainder carried forward so tiny swaps accumulate into future hedge `sz`.
    uint256 public pendingHedgeBuyWeiDust;
    uint256 public pendingHedgeSellWeiDust;

    /// @dev Swap outputs waiting for a hedge batch when batching is on and the hedge bucket is still below threshold.
    struct HedgePayout {
        address recipient;
        address token;
        uint256 amount;
        uint64 sz;
    }

    HedgePayout[] private _pendingPayoutsBuy;
    HedgePayout[] private _pendingPayoutsSell;

    event HedgePayoutEscrowed(address indexed recipient, address indexed token, uint256 amount, bool buyPerpSide);

    constructor(address _usdc, address _purr) ERC20("DeltaFlow LP", "DFLP") {
        strategist = msg.sender;
        foundation = msg.sender;
        defaultVault = 0xa15099a30BBf2e68942d6F4c43d70D04FAEab0A0; // HLP
        usdc = _usdc;
        purr = _purr;
        usdcDec = IERC20Metadata(_usdc).decimals();
        purrDec = IERC20Metadata(_purr).decimals();
    }

    modifier onlyAuthorizedPool() {
        if (!authorizedPools[msg.sender]) revert OnlyAuthorizedPool();
        _;
    }

    modifier onlyStrategist() {
        if (msg.sender != strategist) revert OnlyStrategist();
        _;
    }

    function setAuthorizedPool(address _pool, bool _authorized) external onlyStrategist {
        authorizedPools[_pool] = _authorized;
    }

    /// @notice Set the ALM address so the vault can read spot price for single-sided deposits.
    ///         Called once by the strategist after the ALM is deployed and wired to the pool.
    function setALM(address _alm) external onlyStrategist {
        alm = _alm;
    }

    /// @notice Update fee recipient for swap-fee LP share mints.
    function setFoundation(address _foundation) external onlyStrategist {
        if (_foundation == address(0)) revert FoundationZeroAddress();
        foundation = _foundation;
        emit FoundationSet(_foundation);
    }

    /// @notice Sets the perp used to hedge inventory from swaps. Set to 0 to disable on-chain hedging.
    function setHedgePerpAsset(uint32 perpAssetIndex) external onlyStrategist {
        hedgePerpAssetIndex = perpAssetIndex;
    }

    /// @notice Toggle mark-based \$10 notional threshold (see `MIN_PERP_NOTIONAL_USD_1E6`). If false, `minPerpHedgeSz` alone defines batching and threshold.
    function setUseMarkBasedMinHedgeSz(bool enabled) external onlyStrategist {
        useMarkBasedMinHedgeSz = enabled;
    }

    /// @notice Fixed threshold (`!useMarkBasedMinHedgeSz`) or floor on mark-based threshold. With both off (`!useMarkBasedMinHedgeSz && minSz==0`), each swap sends an IOC (no queue).
    function setMinPerpHedgeSz(uint64 minSz) external onlyStrategist {
        minPerpHedgeSz = minSz;
    }

    function _hedgeBatching() internal view returns (bool) {
        return useMarkBasedMinHedgeSz || minPerpHedgeSz > 0;
    }

    /// @notice Minimum HL `sz` to meet ~\$10 perp notional at current mark, optionally floored by `minPerpHedgeSz`.
    function hedgeSzThreshold() external view returns (uint256) {
        return _hedgeSzThreshold(hedgePerpAssetIndex);
    }

    function _hedgeSzThreshold(uint32 perpIx) internal view returns (uint256) {
        if (!useMarkBasedMinHedgeSz) {
            return uint256(minPerpHedgeSz);
        }
        if (perpIx == 0) return uint256(minPerpHedgeSz);

        uint256 px = PrecompileLib.normalizedMarkPx(perpIx);
        uint8 sd = PrecompileLib.perpAssetInfo(perpIx).szDecimals;
        uint256 factor = 10 ** uint256(sd);
        uint256 dyn;
        if (px == 0) {
            dyn = uint256(minPerpHedgeSz);
            return dyn == 0 ? 1 : dyn;
        }
        dyn = Math.ceilDiv(MIN_PERP_NOTIONAL_USD_1E6 * factor, px);
        if (dyn == 0) dyn = 1;
        uint256 floor = uint256(minPerpHedgeSz);
        return dyn > floor ? dyn : floor;
    }

    /// @notice USDC notionally (~1e6 USD units) required to margin an IOC of size `sz`, matching `_hedgeSzThreshold` math.
    function _notionalUsdcEvmForSz(uint32 perpIx, uint64 sz) internal view returns (uint256) {
        if (sz == 0) return 0;
        uint256 px = PrecompileLib.normalizedMarkPx(perpIx);
        if (px == 0) revert HedgeMarkPxZero();
        uint8 sd = PrecompileLib.perpAssetInfo(perpIx).szDecimals;
        uint256 factor = 10 ** uint256(sd);
        return Math.mulDiv(uint256(sz), px, factor, Math.Rounding.Ceil);
    }

    /// @dev Convert base token amount in Core `wei` to perp `sz` using perp `szDecimals` (not spot token sz decimals).
    function _baseWeiToPerpSz(uint32 perpIx, uint64 baseTokenIx, uint64 amountWei) internal view returns (uint64) {
        if (amountWei == 0) return 0;
        uint8 weiDec = PrecompileLib.tokenInfo(uint32(baseTokenIx)).weiDecimals;
        uint8 perpSzDec = PrecompileLib.perpAssetInfo(perpIx).szDecimals;
        if (weiDec >= perpSzDec) {
            return amountWei / uint64(10 ** uint256(weiDec - perpSzDec));
        }
        uint256 up = uint256(amountWei) * (10 ** uint256(perpSzDec - weiDec));
        if (up > type(uint64).max) return type(uint64).max;
        return uint64(up);
    }

    /// @dev Convert perp `sz` back to base token Core `wei` at the same decimal bridge used in `_baseWeiToPerpSz`.
    function _perpSzToBaseWei(uint32 perpIx, uint64 baseTokenIx, uint64 sz) internal view returns (uint64) {
        if (sz == 0) return 0;
        uint8 weiDec = PrecompileLib.tokenInfo(uint32(baseTokenIx)).weiDecimals;
        uint8 perpSzDec = PrecompileLib.perpAssetInfo(perpIx).szDecimals;
        if (weiDec >= perpSzDec) {
            uint256 up = uint256(sz) * (10 ** uint256(weiDec - perpSzDec));
            if (up > type(uint64).max) return type(uint64).max;
            return uint64(up);
        }
        return sz / uint64(10 ** uint256(perpSzDec - weiDec));
    }

    /// @dev Ensure required USDC notional is available in perp class.
    ///      Uses existing Core spot USDC first, bridges only the shortfall from EVM, then `transferUsdClass`.
    function _bridgeUsdcSpotToPerpForHedge(uint256 usdcEvmAmount, uint256 usdcFeeProtected) internal {
        if (usdcEvmAmount == 0) return;
        uint64 reqCoreWei = HLConversions.evmToWei(usdc, usdcEvmAmount);
        uint64 reqPerpNtl = HLConversions.weiToPerp(reqCoreWei);
        if (reqPerpNtl == 0) revert HedgePerpNtlDust();

        // Available Core spot USDC for this vault address.
        uint64 spotWei = PrecompileLib.spotBalance(address(this), 0).total;
        uint64 spotPerpNtl = HLConversions.weiToPerp(spotWei);

        if (spotPerpNtl < reqPerpNtl) {
            uint64 shortPerpNtl = reqPerpNtl - spotPerpNtl;
            uint64 shortCoreWei = HLConversions.perpToWei(shortPerpNtl);
            uint256 shortEvm = HLConversions.weiToEvm(usdc, shortCoreWei);

            uint256 bal = IERC20(usdc).balanceOf(address(this));
            uint256 spendable = bal > usdcFeeProtected ? bal - usdcFeeProtected : 0;
            if (spendable < shortEvm) revert InsufficientUSDCForHedge(shortEvm, spendable);
            CoreWriterLib.bridgeToCore(usdc, shortEvm);
        }

        CoreWriterLib.transferUsdClass(reqPerpNtl, true);
    }

    /// @param reduceOnly When true, closing against an existing perp position — skip fresh USDC bridge; margin comes from Core.
    function _placePerpIoc(uint32 perpIx, bool isBuy, uint64 sz, bool reduceOnly, uint256 usdcFeeProtected) internal {
        if (sz == 0) return;

        if (!reduceOnly) {
            uint256 usdcNeed = _notionalUsdcEvmForSz(perpIx, sz);
            _bridgeUsdcSpotToPerpForHedge(usdcNeed, usdcFeeProtected);
        }

        uint64 limitPx = isBuy ? type(uint64).max : 0;
        uint128 cloid = uint128(
            uint256(keccak256(abi.encodePacked(block.number, perpIx, isBuy, sz, reduceOnly, address(this), gasleft())))
        );
        CoreWriterLib.placeLimitOrder(perpIx, isBuy, limitPx, sz, reduceOnly, HLConstants.LIMIT_ORDER_TIF_IOC, cloid);
    }

    /// @notice Applies incremental hedge `sz` against live Core perp position: closes the opposing leg with reduce-only IOCs first, then opens the remainder.
    function _netHedgePosition(uint32 perpIx, bool isBuy, uint64 sz, uint256 usdcFeeProtected) internal {
        if (sz == 0) return;
        if (perpIx > type(uint16).max) revert PerpIndexTooLarge();
        int64 pos = PrecompileLib.position(address(this), uint16(perpIx)).szi;

        uint8 leg;

        if (isBuy) {
            if (pos >= 0) {
                _placePerpIoc(perpIx, true, sz, false, usdcFeeProtected);
                leg = 1;
            } else {
                uint64 shortAbs = uint64(uint256(-int256(pos)));
                uint64 closePart = sz < shortAbs ? sz : shortAbs;
                if (closePart > 0) {
                    _placePerpIoc(perpIx, true, closePart, true, 0);
                }
                if (sz > closePart) {
                    _placePerpIoc(perpIx, true, sz - closePart, false, usdcFeeProtected);
                    leg = 3;
                } else {
                    leg = 2;
                }
            }
        } else {
            if (pos <= 0) {
                _placePerpIoc(perpIx, false, sz, false, usdcFeeProtected);
                leg = 1;
            } else {
                uint64 longAbs = uint64(uint256(int256(pos)));
                uint64 closePart = sz < longAbs ? sz : longAbs;
                if (closePart > 0) {
                    _placePerpIoc(perpIx, false, closePart, true, 0);
                }
                if (sz > closePart) {
                    _placePerpIoc(perpIx, false, sz - closePart, false, usdcFeeProtected);
                    leg = 3;
                } else {
                    leg = 2;
                }
            }
        }
        lastHedgeLeg = leg;
    }

    /// @dev Move USDC from perp → spot → EVM up to `maxEvmAmount` (6-decimal USDC) to refill the vault for swap payouts / LP.
    function _pullPerpUsdcToEvmUpTo(uint256 maxEvmAmount) internal {
        if (maxEvmAmount == 0) return;
        uint64 coreWei = HLConversions.evmToWei(usdc, maxEvmAmount);
        uint64 perpNtl = HLConversions.weiToPerp(coreWei);
        if (perpNtl == 0) return;
        CoreWriterLib.transferUsdClass(perpNtl, false);
        CoreWriterLib.bridgeToEvm(usdc, maxEvmAmount);
    }

    function _topUpVaultUsdcFromPerpForAmount(uint256 minEvmBalance) internal {
        uint256 bal = IERC20(usdc).balanceOf(address(this));
        if (bal >= minEvmBalance) return;
        _pullPerpUsdcToEvmUpTo(minEvmBalance - bal);
    }

    /// @dev HyperCore spot → HyperEVM for a linked ERC20 (`bridgeToEvm` / `spotSend` in CoreWriterLib). Requires Core spot balance + HYPE on Core for transfer gas per HL docs.
    function _pullCoreSpotTokenToEvmUpTo(address token, uint256 maxEvmAmount) internal {
        if (maxEvmAmount == 0) return;
        CoreWriterLib.bridgeToEvm(token, maxEvmAmount);
    }

    function _topUpVaultTokenFromCoreSpot(address token, uint256 minEvmBalance) internal {
        uint256 bal = IERC20(token).balanceOf(address(this));
        if (bal >= minEvmBalance) return;
        _pullCoreSpotTokenToEvmUpTo(token, minEvmBalance - bal);
    }

    function _flushBuyAndPayouts(uint32 perpIx) internal {
        uint256 batch = pendingHedgeBuySz;
        pendingHedgeBuySz = 0;
        if (batch > type(uint64).max) revert HedgeBatchTooLarge();
        uint256 n = _pendingPayoutsBuy.length;
        (uint256 usdcSum, uint256 baseSum) = _sumPayoutTokens(_pendingPayoutsBuy, n);
        _netHedgePosition(perpIx, true, uint64(batch), 0);
        emit HedgeBatchExecuted(perpIx, true, batch);
        _topUpEvmAfterHedgeBatch(usdcSum, baseSum);
        for (uint256 i = 0; i < n; i++) {
            HedgePayout memory p = _pendingPayoutsBuy[i];
            _sendTokensToRecipient(p.token, p.recipient, p.amount);
        }
        delete _pendingPayoutsBuy;
    }

    function _flushSellAndPayouts(uint32 perpIx) internal {
        uint256 batch = pendingHedgeSellSz;
        pendingHedgeSellSz = 0;
        if (batch > type(uint64).max) revert HedgeBatchTooLarge();
        uint256 n = _pendingPayoutsSell.length;
        (uint256 usdcSum, uint256 baseSum) = _sumPayoutTokens(_pendingPayoutsSell, n);
        _netHedgePosition(perpIx, false, uint64(batch), 0);
        emit HedgeBatchExecuted(perpIx, false, batch);
        _topUpEvmAfterHedgeBatch(usdcSum, baseSum);
        for (uint256 i = 0; i < n; i++) {
            HedgePayout memory p = _pendingPayoutsSell[i];
            _sendTokensToRecipient(p.token, p.recipient, p.amount);
        }
        delete _pendingPayoutsSell;
    }

    /// @dev Sum USDC / base (`purr`) notionals in a payout buffer (before delete).
    function _sumPayoutTokens(HedgePayout[] storage payouts, uint256 n)
        internal
        view
        returns (uint256 usdcSum, uint256 baseSum)
    {
        for (uint256 i = 0; i < n; i++) {
            address t = payouts[i].token;
            uint256 a = payouts[i].amount;
            if (t == usdc) usdcSum += a;
            else if (t == purr) baseSum += a;
        }
    }

    /// @dev Match `processSwapHedge` non-batching path: after IOC, pull USDC from perp margin (and base from Core spot) to EVM
    ///      so `_sendTokensToRecipient` can pay swap recipients. Batched flushes previously skipped this, so reduce-only closes
    ///      could leave released margin in perp while paying USDC out from a thin EVM balance.
    function _topUpEvmAfterHedgeBatch(uint256 usdcSum, uint256 baseSum) internal {
        if (usdcSum > 0) {
            _topUpVaultUsdcFromPerpForAmount(usdcSum);
        }
        if (baseSum > 0) {
            _topUpVaultTokenFromCoreSpot(purr, baseSum);
        }
    }

    /// @dev Before paying an escrowed hedge payout, pull from perp / Core spot like the immediate-hedge path (see `_release*Sz` netting).
    function _topUpEvmBeforeEscrowPayout(address token, uint256 payAmt) internal {
        if (payAmt == 0) return;
        if (token == usdc) {
            _topUpVaultUsdcFromPerpForAmount(payAmt);
        } else if (token == purr) {
            _topUpVaultTokenFromCoreSpot(purr, payAmt);
        }
    }

    /// @dev FIFO release `matchSz` of sell-side hedge notion from escrow (opposite-direction netting).
    function _releaseSellSz(uint256 matchSz) internal {
        uint256 remaining = matchSz;
        while (remaining > 0 && _pendingPayoutsSell.length > 0) {
            HedgePayout storage h = _pendingPayoutsSell[0];
            uint256 take = remaining < uint256(h.sz) ? remaining : uint256(h.sz);
            uint256 payAmt = Math.mulDiv(h.amount, take, uint256(h.sz));
            address token = h.token;
            address recv = h.recipient;

            if (take == uint256(h.sz)) {
                uint256 last = _pendingPayoutsSell.length - 1;
                if (last != 0) {
                    _pendingPayoutsSell[0] = _pendingPayoutsSell[last];
                }
                _pendingPayoutsSell.pop();
            } else {
                h.sz -= uint64(take);
                h.amount -= payAmt;
            }
            remaining -= take;
            _topUpEvmBeforeEscrowPayout(token, payAmt);
            _sendTokensToRecipient(token, recv, payAmt);
        }
    }

    /// @dev FIFO release `matchSz` of buy-side hedge notion from escrow (opposite-direction netting).
    function _releaseBuySz(uint256 matchSz) internal {
        uint256 remaining = matchSz;
        while (remaining > 0 && _pendingPayoutsBuy.length > 0) {
            HedgePayout storage h = _pendingPayoutsBuy[0];
            uint256 take = remaining < uint256(h.sz) ? remaining : uint256(h.sz);
            uint256 payAmt = Math.mulDiv(h.amount, take, uint256(h.sz));
            address token = h.token;
            address recv = h.recipient;

            if (take == uint256(h.sz)) {
                uint256 last = _pendingPayoutsBuy.length - 1;
                if (last != 0) {
                    _pendingPayoutsBuy[0] = _pendingPayoutsBuy[last];
                }
                _pendingPayoutsBuy.pop();
            } else {
                h.sz -= uint64(take);
                h.amount -= payAmt;
            }
            remaining -= take;
            _topUpEvmBeforeEscrowPayout(token, payAmt);
            _sendTokensToRecipient(token, recv, payAmt);
        }
    }

    /// @inheritdoc ISovereignVaultMinimal
    function processSwapHedge(
        bool vaultPurrOut,
        uint256 purrAmountWei,
        uint256 usdcFeeProtected,
        address swapTokenOut,
        address recipient,
        uint256 amountOut
    ) external onlyAuthorizedPool returns (bool poolShouldSendTokenOut) {
        uint32 perpIx = hedgePerpAssetIndex;
        if (perpIx == 0 || purrAmountWei == 0) return true;

        uint64 tokenIdx = PrecompileLib.getTokenIndex(purr);
        uint64 weiAmt = HLConversions.evmToWei(tokenIdx, purrAmountWei);
        bool isBuy = vaultPurrOut;
        uint256 priorDust = isBuy ? pendingHedgeBuyWeiDust : pendingHedgeSellWeiDust;
        uint256 totalWei = uint256(weiAmt) + priorDust;
        uint64 sz =
            _baseWeiToPerpSz(perpIx, tokenIdx, totalWei > type(uint64).max ? type(uint64).max : uint64(totalWei));
        uint64 consumedWei = _perpSzToBaseWei(perpIx, tokenIdx, sz);
        uint256 nextDust = totalWei > uint256(consumedWei) ? (totalWei - uint256(consumedWei)) : 0;
        if (isBuy) {
            pendingHedgeBuyWeiDust = nextDust;
        } else {
            pendingHedgeSellWeiDust = nextDust;
        }
        if (sz == 0) return true;

        // If dynamic threshold dropped (e.g. mark moved), flush older queued hedges before this swap’s slice.
        if (_hedgeBatching()) {
            uint256 batchThresh = _hedgeSzThreshold(perpIx);
            if (pendingHedgeBuySz >= batchThresh) {
                _flushBuyAndPayouts(perpIx);
            }
            if (pendingHedgeSellSz >= batchThresh) {
                _flushSellAndPayouts(perpIx);
            }
        }

        if (!_hedgeBatching()) {
            _netHedgePosition(perpIx, isBuy, sz, usdcFeeProtected);
            if (swapTokenOut == usdc) {
                _topUpVaultUsdcFromPerpForAmount(amountOut);
            } else {
                _topUpVaultTokenFromCoreSpot(swapTokenOut, amountOut);
            }
            emit SwapHedgeExecuted(perpIx, vaultPurrOut, purrAmountWei, sz);
            return true;
        }

        uint256 thresh = _hedgeSzThreshold(perpIx);

        if (isBuy) {
            if (pendingHedgeSellSz > 0) {
                uint256 matchSz = uint256(sz) < pendingHedgeSellSz ? uint256(sz) : pendingHedgeSellSz;
                pendingHedgeSellSz -= matchSz;
                _releaseSellSz(matchSz);
                sz = uint64(uint256(sz) - matchSz);
            }
            if (sz == 0) {
                return true;
            }

            pendingHedgeBuySz += uint256(sz);
            _pendingPayoutsBuy.push(HedgePayout({recipient: recipient, token: swapTokenOut, amount: amountOut, sz: sz}));
            emit HedgePayoutEscrowed(recipient, swapTokenOut, amountOut, true);
            emit HedgeSliceQueued(true, sz, pendingHedgeBuySz, pendingHedgeSellSz);

            if (pendingHedgeBuySz < thresh) {
                return false;
            }
            _flushBuyAndPayouts(perpIx);
            return false;
        } else {
            if (pendingHedgeBuySz > 0) {
                uint256 matchSz = uint256(sz) < pendingHedgeBuySz ? uint256(sz) : pendingHedgeBuySz;
                pendingHedgeBuySz -= matchSz;
                _releaseBuySz(matchSz);
                sz = uint64(uint256(sz) - matchSz);
            }
            if (sz == 0) {
                return true;
            }

            pendingHedgeSellSz += uint256(sz);
            _pendingPayoutsSell.push(
                HedgePayout({recipient: recipient, token: swapTokenOut, amount: amountOut, sz: sz})
            );
            emit HedgePayoutEscrowed(recipient, swapTokenOut, amountOut, false);
            emit HedgeSliceQueued(false, sz, pendingHedgeBuySz, pendingHedgeSellSz);

            if (pendingHedgeSellSz < thresh) {
                return false;
            }
            _flushSellAndPayouts(perpIx);
            return false;
        }
    }

    function pendingPayoutsBuyLength() external view returns (uint256) {
        return _pendingPayoutsBuy.length;
    }

    function pendingPayoutsSellLength() external view returns (uint256) {
        return _pendingPayoutsSell.length;
    }

    function _feeTokenValueInUsdc(address feeToken, uint256 feeAmount, uint256 spotPrice)
        internal
        view
        returns (uint256)
    {
        if (feeToken == usdc) return feeAmount;
        if (feeToken == purr) return Math.mulDiv(feeAmount, spotPrice, 10 ** uint256(purrDec));
        return 0;
    }

    /// @inheritdoc ISovereignVaultMinimal
    function creditSwapFeeToFoundation(address feeToken, uint256 feeAmount) external onlyAuthorizedPool {
        if (feeAmount == 0) return;
        address foundationAddr = foundation;
        if (foundationAddr == address(0)) return;

        uint256 supply = totalSupply();
        if (supply == 0) return;

        if (alm == address(0)) return;
        uint256 spotPrice = ISpotPricer(alm).getSpotPriceUsdcPerBase();

        (uint256 reserveUsdc, uint256 reservePurr) = getReserves();
        uint256 poolValueUsdc = reserveUsdc + Math.mulDiv(reservePurr, spotPrice, 10 ** uint256(purrDec));
        uint256 feeValueUsdc = _feeTokenValueInUsdc(feeToken, feeAmount, spotPrice);
        if (feeValueUsdc == 0 || poolValueUsdc <= feeValueUsdc) return;

        // Fee tokens are already present in reserves; mint shares against pre-fee value.
        uint256 shares = Math.mulDiv(feeValueUsdc, supply, poolValueUsdc - feeValueUsdc);
        if (shares == 0) return;

        _mint(foundationAddr, shares);
        emit FoundationFeeLpMinted(feeToken, feeAmount, shares);
    }

    /// @notice Runs batched hedge IOCs and pays escrowed `tokenOut`s even when below the normal min-`sz` threshold (same as a full batch flush).
    function forceFlushHedgeBatch() external nonReentrant {
        uint32 perpIx = hedgePerpAssetIndex;
        if (perpIx == 0) return;
        if (pendingHedgeBuySz > 0) {
            _flushBuyAndPayouts(perpIx);
        }
        if (pendingHedgeSellSz > 0) {
            _flushSellAndPayouts(perpIx);
        }
    }

    /// @notice Pulls USDC from HyperCore perp → spot → this contract on EVM, up to `maxEvmAmount` (6‑decimals).
    function pullPerpUsdcToEvm(uint256 maxEvmAmount) external nonReentrant {
        _pullPerpUsdcToEvmUpTo(maxEvmAmount);
    }

    /// @notice Pulls a linked spot asset from HyperCore spot to this contract on HyperEVM (see HL Core ↔ EVM linking).
    function pullCoreSpotTokenToEvm(address token, uint256 maxEvmAmount) external nonReentrant {
        _pullCoreSpotTokenToEvmUpTo(token, maxEvmAmount);
    }

    function _toU64(uint256 x) internal pure returns (uint64) {
        require(x <= type(uint64).max, "AMOUNT_TOO_LARGE");
        return uint64(x);
    }

    function getTokensForPool(address _pool) external view returns (address[] memory) {
        ISovereignPool pool = ISovereignPool(_pool);
        address[] memory tokens = new address[](2);
        tokens[0] = pool.token0();
        tokens[1] = pool.token1();
        return tokens;
    }

    // Interface required function - returns total reserves (internal + external)
    function getReservesForPool(address, address[] calldata _tokens) external view returns (uint256[] memory) {
        PrecompileLib.SpotBalance memory externalUSDCReserves = PrecompileLib.spotBalance(address(this), 0);
        uint256 usdcSpotTotal = externalUSDCReserves.total;
        uint256 spotToEvm = HLConversions.perpToWei(uint64(usdcSpotTotal));
        uint256 token0Reserves = _tokens[0] == usdc
            ? IERC20(usdc).balanceOf(address(this)) + spotToEvm
            : IERC20(_tokens[0]).balanceOf(address(this));
        uint256 token1Reserves = _tokens[1] == usdc
            ? IERC20(usdc).balanceOf(address(this)) + spotToEvm
            : IERC20(_tokens[1]).balanceOf(address(this));

        uint256[] memory tokenReserves = new uint256[](_tokens.length);
        tokenReserves[0] = token0Reserves;
        tokenReserves[1] = token1Reserves;
        return tokenReserves;
    }

    /// @dev Shared by `sendTokensToRecipient` and batched hedge payout flushes.
    function _sendTokensToRecipient(address _token, address recipient, uint256 _amount) internal {
        if (_amount == 0) return;

        IERC20 token = IERC20(_token);
        uint256 internalBalance = token.balanceOf(address(this));
        if (internalBalance >= _amount) {
            token.safeTransfer(recipient, _amount);
            return;
        }

        uint256 amountNeeded = _amount - internalBalance;

        if (_token == usdc) {
            require(internalBalance + totalAllocatedUSDC >= _amount, "INSUFFICIENT_BUFFER");
            CoreWriterLib.vaultTransfer(defaultVault, false, _toU64(amountNeeded));
            CoreWriterLib.bridgeToEvm(usdc, amountNeeded);
        } else {
            // Linked HyperCore spot asset (e.g. PURR): pull Core spot → EVM via system `spotSend` (CoreWriterLib.bridgeToEvm).
            CoreWriterLib.bridgeToEvm(_token, amountNeeded);
        }

        uint256 finalBalance = token.balanceOf(address(this));
        if (finalBalance < _amount) revert InsufficientFundsAfterWithdraw();
        token.safeTransfer(recipient, _amount);
    }

    // Sends tokens to recipient, withdrawing from lending market if needed
    function sendTokensToRecipient(address _token, address recipient, uint256 _amount) external onlyAuthorizedPool {
        _sendTokensToRecipient(_token, recipient, _amount);
    }

    function changeDefaultVault(address newVault) external onlyStrategist {
        defaultVault = newVault;
    }

    function getUSDCBalance() external view returns (uint256) {
        return IERC20(usdc).balanceOf(address(this));
    }

    // ============ VAULT ALLOCATION ============

    /// @notice Bridge USDC from this EVM vault to Core (no vault transfer)
    function bridgeToCoreOnly(uint256 usdcAmount) external onlyStrategist {
        CoreWriterLib.bridgeToCore(usdc, usdcAmount);
        emit BridgedToCore(usdc, usdcAmount);
    }

    /// @notice First USDC bridge to HyperCore spot for this address — establishes the Core account / spot balance in a **dedicated tx** before CoreWriter-heavy flows.
    /// @dev USDC is assumed 6 decimals on HyperEVM (same as `MIN_CORE_BOOTSTRAP_USDC`).
    function bootstrapHyperCoreAccount(uint256 usdcAmount) external onlyStrategist nonReentrant {
        if (usdcAmount < MIN_CORE_BOOTSTRAP_USDC) {
            revert BootstrapAmountTooSmall(MIN_CORE_BOOTSTRAP_USDC, usdcAmount);
        }
        CoreWriterLib.bridgeToCore(usdc, usdcAmount);
        emit BridgedToCore(usdc, usdcAmount);
    }

    /// @notice Bridge any linked HyperEVM ERC20 (e.g. pool base asset) from this vault to HyperCore spot — use when USDC is tight but base inventory should sit on Core for hedging / spot.
    function bridgeInventoryTokenToCore(address token, uint256 amount) external onlyStrategist nonReentrant {
        if (amount == 0) revert ZeroAmount();
        CoreWriterLib.bridgeToCore(token, amount);
        emit BridgedToCore(token, amount);
    }

    /// @notice Bridge native HYPE on HyperEVM to HyperCore spot (gas / fee token on Core).
    function fundCoreWithHype() external payable onlyStrategist nonReentrant {
        if (msg.value == 0) revert ZeroAmount();
        CoreWriterLib.bridgeToCore(HLConstants.hypeTokenIndex(), msg.value);
        emit HypeBridgedToCore(msg.value);
    }

    /// @notice Bridge USDC to Core and deposit into a specific Core vault (yield/trading)
    function allocate(address coreVault, uint256 usdcAmount) external onlyStrategist {
        // Register the vault for enumeration so the auto-sync can reach it later
        if (!_coreVaultTracked[coreVault]) {
            _coreVaultTracked[coreVault] = true;
            coreVaultsList.push(coreVault);
        }

        CoreWriterLib.bridgeToCore(usdc, usdcAmount);
        CoreWriterLib.vaultTransfer(coreVault, true, _toU64(usdcAmount));

        allocatedToCoreVault[coreVault] += usdcAmount;
        totalAllocatedUSDC += usdcAmount;

        emit BridgedToCore(usdc, usdcAmount);
        emit CoreVaultMoved(coreVault, true, usdcAmount);
    }

    /// @notice Withdraw USDC from a specific Core vault back to this EVM vault
    function deallocate(address coreVault, uint256 usdcAmount) external onlyStrategist {
        CoreWriterLib.vaultTransfer(coreVault, false, _toU64(usdcAmount));
        CoreWriterLib.bridgeToEvm(usdc, usdcAmount);

        allocatedToCoreVault[coreVault] -= usdcAmount;
        totalAllocatedUSDC -= usdcAmount;

        emit CoreVaultMoved(coreVault, false, usdcAmount);
        emit BridgedToEvm(usdc, usdcAmount);
    }

    /// @notice Bridge USDC back from Core to EVM (no vault transfer)
    ///         Assumes strategist has already moved funds out of Core vault(s) into the Core balance.
    function bridgeToEvmOnly(uint256 usdcAmount) external onlyStrategist {
        CoreWriterLib.bridgeToEvm(usdc, usdcAmount);
        emit BridgedToEvm(usdc, usdcAmount);
    }

    function approveAgent(address agent, string calldata name) external onlyStrategist {
        CoreWriterLib.addApiWallet(agent, name);
    }

    function getTotalAllocatedUSDC() external view returns (uint256) {
        return totalAllocatedUSDC;
    }

    function syncCoreAllocations() external onlyStrategist {
        _syncAllCoreAllocations();
    }

    function _syncAllCoreAllocations() internal {
        if (coreVaultsList.length == 0) return;

        uint256 oldTotal = totalAllocatedUSDC;
        uint256 newTotal = 0;

        for (uint256 i = 0; i < coreVaultsList.length; i++) {
            address cv = coreVaultsList[i];
            PrecompileLib.UserVaultEquity memory eq = PrecompileLib.userVaultEquity(address(this), cv);
            uint256 liveEquity = uint256(eq.equity);
            allocatedToCoreVault[cv] = liveEquity;
            newTotal += liveEquity;
        }

        totalAllocatedUSDC = newTotal;

        if (newTotal != oldTotal) {
            emit CoreAllocationsSynced(oldTotal, newTotal);
        }
    }

    function claimPoolManagerFees(uint256 _feePoolManager0, uint256 _feePoolManager1) external onlyAuthorizedPool {
        // Pool manager fees are tracked in the pool, this is called to claim them
        // In this implementation, fees stay in the vault as part of reserves
    }

    // ============ LP ============

    /// @notice Returns total vault reserves: EVM balance + Core-allocated USDC, and EVM PURR
    function getReserves() public view returns (uint256 reserveUsdc, uint256 reservePurr) {
        reserveUsdc = IERC20(usdc).balanceOf(address(this)) + totalAllocatedUSDC;
        reservePurr = IERC20(purr).balanceOf(address(this));
    }

    // ============ Share price view functions ============

    /// @notice Total vault NAV in USDC units (6-decimal).
    ///
    ///         Components:
    ///           EVM USDC balance
    ///         + Core-allocated USDC (yield vaults, last-synced via `_syncAllCoreAllocations`)
    ///         + EVM PURR valued at spot price
    ///         + Perp account value (USDC margin bridged to Core + unrealized P&L), signed —
    ///           positive when the hedge earns, negative when it loses beyond margin.
    ///
    ///         The perp component is the key addition: without it, PURR inventory is
    ///         valued at spot while the offsetting short perp loss is invisible, causing
    ///         NAV to be overstated when PURR has risen and understated when it has fallen.
    ///
    ///         If the ALM is not set, PURR is valued at zero.
    ///         `totalAllocatedUSDC` may lag; call `syncCoreAllocations()` first for a
    ///         time-sensitive read.
    function totalAssets() public view returns (uint256) {
        uint256 usdcPart = IERC20(usdc).balanceOf(address(this)) + totalAllocatedUSDC;

        // Perp account value: USDC margin sitting on Core + all unrealized P&L.
        // Only read when hedging is active; the signed value is in 6-decimal USDC
        // units (same as HyperCore's internal accounting).
        if (hedgePerpAssetIndex != 0) {
            PrecompileLib.AccountMarginSummary memory m =
                PrecompileLib.accountMarginSummary(HLConstants.DEFAULT_PERP_DEX, address(this));
            if (m.accountValue >= 0) {
                usdcPart += uint256(int256(m.accountValue));
            } else {
                uint256 loss = uint256(-int256(m.accountValue));
                usdcPart = usdcPart > loss ? usdcPart - loss : 0;
            }
        }

        if (alm == address(0)) return usdcPart;
        uint256 spotPrice = ISpotPricer(alm).getSpotPriceUsdcPerBase();
        if (spotPrice == 0) return usdcPart;
        return usdcPart + Math.mulDiv(IERC20(purr).balanceOf(address(this)), spotPrice, 10 ** uint256(purrDec));
    }

    /// @notice Convert a USDC-denominated value to LP shares at the current share price.
    ///         Uses the same +1 virtual-share formula as the deposit path.
    function convertToShares(uint256 assetsUsdc) public view returns (uint256) {
        return Math.mulDiv(assetsUsdc, totalSupply() + 1, totalAssets() + 1);
    }

    /// @notice Convert LP shares to their USDC-denominated NAV.
    function convertToAssets(uint256 shares) public view returns (uint256) {
        return Math.mulDiv(shares, totalAssets() + 1, totalSupply() + 1);
    }

    /// @notice Preview shares received for a deposit of `usdcAmount` + `purrAmount`.
    function previewDeposit(uint256 usdcAmount, uint256 purrAmount) public view returns (uint256) {
        if (alm == address(0)) revert LP__AlmNotSet();
        uint256 spotPrice = ISpotPricer(alm).getSpotPriceUsdcPerBase();
        uint256 depositValue = usdcAmount + Math.mulDiv(purrAmount, spotPrice, 10 ** uint256(purrDec));
        return convertToShares(depositValue);
    }

    /// @notice Preview USDC and PURR returned for redeeming `shares`.
    function previewRedeem(uint256 shares) public view returns (uint256 usdcOut, uint256 purrOut) {
        uint256 supply = totalSupply();
        if (supply == 0) return (0, 0);
        (uint256 reserveUsdc, uint256 reservePurr) = getReserves();
        usdcOut = Math.mulDiv(shares, reserveUsdc, supply);
        purrOut = Math.mulDiv(shares, reservePurr, supply);
    }

    /// @notice Deposit USDC and/or PURR to receive LP shares.
    ///
    ///         Two deposit modes:
    ///
    ///         1. First deposit (supply == 0)
    ///            Must be two-sided. Shares = geometric mean of both amounts minus
    ///            MINIMUM_LIQUIDITY, which is permanently locked to prevent share-price
    ///            manipulation on a tiny pool.
    ///
    ///         2. Subsequent deposit (supply > 0, one or both amounts > 0)
    ///            Value-based via ERC4626-style math. Both tokens are converted to a
    ///            USDC NAV using the ALM spot price, then shares are minted proportional
    ///            to the deposit's share of the pool's total NAV:
    ///              shares = depositValueUsdc / totalAssets() × supply
    ///            This is consistent with `convertToShares()` / `totalAssets()`.
    ///            For single-sided deposits the deposited token sits in the vault and
    ///            converts gradually as traders use the pool.
    ///
    /// @param usdcAmount  Amount of USDC to deposit (may be 0 for PURR-only deposit)
    /// @param purrAmount  Amount of PURR to deposit (may be 0 for USDC-only deposit)
    /// @param minShares   Minimum shares to receive (slippage protection)
    function depositLP(uint256 usdcAmount, uint256 purrAmount, uint256 minShares)
        external
        nonReentrant
        returns (uint256 shares)
    {
        if (usdcAmount == 0 && purrAmount == 0) revert LP__ZeroAmount();

        // Sync Core equity before computing share price so any accumulated P&L is
        // reflected and new depositors pay a fair price.
        _syncAllCoreAllocations();

        uint256 supply = totalSupply();

        if (supply == 0) {
            // First deposit: must be two-sided and value-balanced to start the pool
            // in a delta-neutral state — equal dollar value on each side means no
            // immediate corrective hedge is needed.
            if (usdcAmount == 0 || purrAmount == 0) revert LP__FirstDepositRequiresBothTokens();
            if (alm == address(0)) revert LP__AlmNotSet();

            uint256 spotPrice0 = ISpotPricer(alm).getSpotPriceUsdcPerBase();
            uint256 purrValue = Math.mulDiv(purrAmount, spotPrice0, 10 ** uint256(purrDec));

            // Enforce that the two sides are within FIRST_DEPOSIT_MAX_IMBALANCE_BPS of
            // each other. Uses the larger side as the reference so the tolerance is
            // symmetric: neither side may exceed the other by more than 1%.
            uint256 larger  = usdcAmount > purrValue ? usdcAmount : purrValue;
            uint256 smaller = usdcAmount > purrValue ? purrValue  : usdcAmount;
            if ((larger - smaller) * 10_000 > larger * FIRST_DEPOSIT_MAX_IMBALANCE_BPS) {
                revert LP__FirstDepositImbalanced(usdcAmount, purrValue);
            }

            shares = Math.sqrt(usdcAmount * purrAmount) - MINIMUM_LIQUIDITY;
            _mint(address(0xdead), MINIMUM_LIQUIDITY);
        } else {
            // Subsequent deposit (two-sided or single-sided).
            // Value both tokens in USDC at spot price, then delegate to convertToShares
            // so the formula is defined in exactly one place.
            if (alm == address(0)) revert LP__AlmNotSet();

            uint256 spotPrice = ISpotPricer(alm).getSpotPriceUsdcPerBase();
            uint256 depositValue = usdcAmount + Math.mulDiv(purrAmount, spotPrice, 10 ** uint256(purrDec));

            shares = convertToShares(depositValue);
        }

        if (shares == 0 || shares < minShares) revert LP__InsufficientShares(shares, minShares);

        if (usdcAmount > 0) IERC20(usdc).safeTransferFrom(msg.sender, address(this), usdcAmount);
        if (purrAmount > 0) IERC20(purr).safeTransferFrom(msg.sender, address(this), purrAmount);

        _mint(msg.sender, shares);
        emit LiquidityAdded(msg.sender, usdcAmount, purrAmount, shares);
    }

    /// @notice Burn LP shares and receive pro-rata USDC and PURR.
    ///         Reverts if USDC allocated to Core exceeds the EVM balance available.
    ///         In that case, the strategist must call deallocate() first.
    /// @param shares Amount of LP shares to burn
    /// @param minUsdc Minimum USDC to receive (slippage protection)
    /// @param minPurr Minimum PURR to receive (slippage protection)
    function withdrawLP(uint256 shares, uint256 minUsdc, uint256 minPurr)
        external
        nonReentrant
        returns (uint256 usdcOut, uint256 purrOut)
    {
        if (shares == 0) revert LP__ZeroAmount();

        // Sync Core equity before computing the redemption value so withdrawing LPs
        // receive an accurate pro-rata share of all vault assets including any P&L.
        _syncAllCoreAllocations();

        (uint256 reserveUsdc, uint256 reservePurr) = getReserves();
        uint256 supply = totalSupply();

        usdcOut = Math.mulDiv(shares, reserveUsdc, supply);
        purrOut = Math.mulDiv(shares, reservePurr, supply);

        if (usdcOut < minUsdc) revert LP__InsufficientUsdcOut(usdcOut, minUsdc);
        if (purrOut < minPurr) revert LP__InsufficientPurrOut(purrOut, minPurr);

        // USDC may be partially allocated to Core — revert if EVM balance is insufficient.
        // The strategist must call deallocate() to bring funds back before this withdrawal.
        uint256 evmUsdc = IERC20(usdc).balanceOf(address(this));
        if (evmUsdc < usdcOut) revert LP__InsufficientEvmUsdc(evmUsdc, usdcOut);

        _burn(msg.sender, shares);

        IERC20(usdc).safeTransfer(msg.sender, usdcOut);
        IERC20(purr).safeTransfer(msg.sender, purrOut);

        emit LiquidityRemoved(msg.sender, usdcOut, purrOut, shares);
    }
}
