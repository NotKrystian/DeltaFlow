// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {CoreWriterLib} from "@hyper-evm-lib/src/CoreWriterLib.sol";
import {PrecompileLib} from "@hyper-evm-lib/src/PrecompileLib.sol";
import {HLConversions} from "@hyper-evm-lib/src/common/HLConversions.sol";

/// @title HedgeEscrow
/// @notice Escrows USDC on EVM, bridges to HyperCore spot, places a **limit order via CoreWriter**
///         (system contract `0x3333…3333`). Users claim PURR back to EVM after fills; fill detection
///         uses `PrecompileLib.spotBalance` (same as off-chain polling).
contract HedgeEscrow is ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC20 public immutable usdc;
    IERC20 public immutable purr;
    /// @dev Hyperliquid spot universe asset id for the PURR/USDC book (see HL metadata / `ReadSpotIndex`).
    uint32 public immutable spotAssetIndex;
    /// @dev Token index for PURR in Core (for spot balance reads / wei conversion).
    uint64 public immutable purrTokenIndex;

    uint256 public nextTradeId;

    struct Trade {
        address user;
        bool isBuy;
        uint64 limitPx;
        uint64 sz;
        uint128 cloid;
        uint64 purrSpotBefore;
        uint64 usdcSpotBefore;
        bool claimed;
    }

    mapping(uint256 => Trade) public trades;

    event HedgeOpened(
        uint256 indexed id,
        address indexed user,
        bool isBuy,
        uint64 limitPx,
        uint64 sz,
        uint128 cloid,
        uint64 purrSpotBefore,
        uint64 usdcSpotBefore
    );
    event HedgeClaimed(uint256 indexed id, address indexed user, uint256 purrEvmOut);

    error HedgeEscrow__BadArgs();
    error HedgeEscrow__NotFilled();
    error HedgeEscrow__NotUser();
    error HedgeEscrow__AlreadyClaimed();
    error HedgeEscrow__InvalidTif();

    constructor(address _usdc, address _purr, uint32 _spotAssetIndex, uint64 _purrTokenIndex) {
        require(_usdc != address(0) && _purr != address(0), "ZERO");
        usdc = IERC20(_usdc);
        purr = IERC20(_purr);
        spotAssetIndex = _spotAssetIndex;
        purrTokenIndex = _purrTokenIndex;
    }

    /// @notice Open a **buy PURR with USDC** spot limit order. `sz` and `limitPx` use HL scaling (1e8 * human).
    /// @param usdcEvmIn USDC pulled from `msg.sender` and bridged to Core spot.
    /// @param tif 1=Alo, 2=Gtc, 3=Ioc (see HL docs).
    /// @param cloid Client order id; use 0 for none, else unique uint128 per order.
    function openBuyPurrWithUsdc(uint256 usdcEvmIn, uint64 limitPx1e8, uint64 sz1e8, uint8 tif, uint128 cloid)
        external
        nonReentrant
        returns (uint256 id)
    {
        if (usdcEvmIn == 0 || sz1e8 == 0) revert HedgeEscrow__BadArgs();
        if (tif < 1 || tif > 3) revert HedgeEscrow__InvalidTif();

        usdc.safeTransferFrom(msg.sender, address(this), usdcEvmIn);
        CoreWriterLib.bridgeToCore(address(usdc), usdcEvmIn);

        uint64 pb = PrecompileLib.spotBalance(address(this), purrTokenIndex).total;
        uint64 ub = PrecompileLib.spotBalance(address(this), uint64(0)).total;

        CoreWriterLib.placeLimitOrder(spotAssetIndex, true, limitPx1e8, sz1e8, false, tif, cloid);

        id = ++nextTradeId;
        trades[id] = Trade({
            user: msg.sender,
            isBuy: true,
            limitPx: limitPx1e8,
            sz: sz1e8,
            cloid: cloid,
            purrSpotBefore: pb,
            usdcSpotBefore: ub,
            claimed: false
        });

        emit HedgeOpened(id, msg.sender, true, limitPx1e8, sz1e8, cloid, pb, ub);
    }

    /// @notice True if PURR spot balance increased enough vs snapshot (≥95% of `sz` in wei terms).
    function canClaimBuy(uint256 id) external view returns (bool) {
        Trade storage t = trades[id];
        if (t.user == address(0) || t.claimed || !t.isBuy) return false;
        uint64 purrNow = PrecompileLib.spotBalance(address(this), purrTokenIndex).total;
        uint64 minWei = HLConversions.szToWei(purrTokenIndex, t.sz);
        uint256 thr = uint256(t.purrSpotBefore) + (uint256(minWei) * 95 / 100);
        return uint256(purrNow) >= thr;
    }

    /// @notice Bridge filled PURR from Core to EVM and send to the user.
    function claimPurrBuy(uint256 id) external nonReentrant {
        Trade storage t = trades[id];
        if (t.claimed) revert HedgeEscrow__AlreadyClaimed();
        if (t.user != msg.sender) revert HedgeEscrow__NotUser();
        if (!t.isBuy) revert HedgeEscrow__BadArgs();

        uint64 purrNow = PrecompileLib.spotBalance(address(this), purrTokenIndex).total;
        uint64 minWei = HLConversions.szToWei(purrTokenIndex, t.sz);
        if (uint256(purrNow) < uint256(t.purrSpotBefore) + (uint256(minWei) * 95 / 100)) {
            revert HedgeEscrow__NotFilled();
        }

        t.claimed = true;

        uint64 deltaWei = purrNow - t.purrSpotBefore;
        // Move filled PURR from Core spot to this contract's EVM balance (`amount` is Core wei).
        CoreWriterLib.bridgeToEvm(purrTokenIndex, deltaWei, false);

        uint256 bal = IERC20(purr).balanceOf(address(this));
        IERC20(purr).safeTransfer(t.user, bal);

        emit HedgeClaimed(id, t.user, bal);
    }
}
