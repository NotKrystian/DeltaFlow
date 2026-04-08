// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {ISovereignVaultMinimal} from "./interfaces/ISovereignVaultMinimal.sol";
import {ISovereignPool} from "./interfaces/ISovereignPool.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {CoreWriterLib} from "@hyper-evm-lib/src/CoreWriterLib.sol";
import {HLConversions} from "@hyper-evm-lib/src/CoreWriterLib.sol";
import {HLConstants} from "@hyper-evm-lib/src/common/HLConstants.sol";
import {PrecompileLib} from "@hyper-evm-lib/src/PrecompileLib.sol";

/// @dev Minimal interface so the vault can read the spot price from the ALM
///      without importing the full ALM contract.
interface ISpotPricer {
    function getSpotPriceUSDCperPURR() external view returns (uint256);
}

contract SovereignVault is ISovereignVaultMinimal, ERC20, ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 public constant MINIMUM_LIQUIDITY = 1_000;

    address public immutable strategist;
    address public immutable usdc;
    address public immutable purr;
    uint8 public immutable usdcDec;
    uint8 public immutable purrDec;

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
    error LP__AlmNotSet();
    error LP__InsufficientShares(uint256 got, uint256 min);
    error LP__InsufficientUsdcOut(uint256 got, uint256 min);
    error LP__InsufficientPurrOut(uint256 got, uint256 min);
    error LP__InsufficientEvmUsdc(uint256 available, uint256 needed);

    event LiquidityAdded(address indexed provider, uint256 usdcAmount, uint256 purrAmount, uint256 shares);
    event LiquidityRemoved(address indexed provider, uint256 usdcOut, uint256 purrOut, uint256 shares);
    event BridgedToCore(address indexed token, uint256 amount);
    event BridgedToEvm(address indexed token, uint256 amount);
    event CoreVaultMoved(address indexed coreVault, bool isDeposit, uint256 amount);
    event CoreAllocationsSynced(uint256 oldTotal, uint256 newTotal);
    event SwapHedgeExecuted(uint32 indexed perpAsset, bool vaultPurrOut, uint256 purrAmountWei, uint64 sz);

    mapping(address => uint256) public allocatedToCoreVault;

    /// @notice HyperCore perp asset index for swap hedges (PURR perp). 0 = disabled (no CoreWriter call).
    uint32 public hedgePerpAssetIndex;

    constructor(address _usdc, address _purr) ERC20("DeltaFlow LP", "DFLP") {
        strategist = msg.sender;
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

    /// @notice Sets the perp used to hedge inventory from swaps. Set to 0 to disable on-chain hedging.
    function setHedgePerpAsset(uint32 perpAssetIndex) external onlyStrategist {
        hedgePerpAssetIndex = perpAssetIndex;
    }

    /// @inheritdoc ISovereignVaultMinimal
    function hedgeAfterSwap(bool vaultPurrOut, uint256 purrAmountWei) external onlyAuthorizedPool {
        uint32 perpIx = hedgePerpAssetIndex;
        if (perpIx == 0 || purrAmountWei == 0) return;

        uint64 tokenIdx = PrecompileLib.getTokenIndex(purr);
        uint64 weiAmt = HLConversions.evmToWei(tokenIdx, purrAmountWei);
        uint64 sz = HLConversions.weiToSz(tokenIdx, weiAmt);
        if (sz == 0) return;

        bool isBuy = vaultPurrOut;
        uint64 limitPx = isBuy ? type(uint64).max : 0;
        uint128 cloid = uint128(uint256(keccak256(abi.encodePacked(block.number, purrAmountWei, vaultPurrOut, msg.sender))));

        CoreWriterLib.placeLimitOrder(
            perpIx, isBuy, limitPx, sz, false, HLConstants.LIMIT_ORDER_TIF_IOC, cloid
        );

        emit SwapHedgeExecuted(perpIx, vaultPurrOut, purrAmountWei, sz);
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
    function getReservesForPool(address _pool, address[] calldata _tokens) external view returns (uint256[] memory) {
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

    // Sends tokens to recipient, withdrawing from lending market if needed
    function sendTokensToRecipient(address _token, address recipient, uint256 _amount) external onlyAuthorizedPool {
        if (_amount == 0) return;

        IERC20 token = IERC20(_token);
        uint256 internalBalance = token.balanceOf(address(this));
        if (internalBalance >= _amount) {
            token.safeTransfer(recipient, _amount);
            return;
        }
        require(internalBalance + totalAllocatedUSDC >= _amount, "INSUFFICIENT_BUFFER");
        if (_token == usdc) {
            uint256 amountNeeded = _amount - internalBalance;

            // transfers from vault to core and bridges to evm
            CoreWriterLib.vaultTransfer(defaultVault, false, uint64(amountNeeded));
            CoreWriterLib.bridgeToEvm(usdc, amountNeeded);
            uint256 finalBalance = token.balanceOf(address(this));
            if (finalBalance < _amount) revert InsufficientFundsAfterWithdraw();
            IERC20(usdc).safeTransfer(recipient, _amount);
        }
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

    /// @notice Deposit USDC and/or PURR to receive LP shares.
    ///
    ///         Three deposit modes:
    ///
    ///         1. First deposit (supply == 0)
    ///            Must be two-sided. Shares = geometric mean of both amounts minus
    ///            MINIMUM_LIQUIDITY, which is permanently locked to prevent share-price
    ///            manipulation on a tiny pool.
    ///
    ///         2. Subsequent two-sided deposit (both amounts > 0)
    ///            Oracle-free. Shares = min(USDC_ratio, PURR_ratio) × supply.
    ///            Any excess of the larger side stays in the vault and accrues to all LPs.
    ///
    ///         3. Single-sided deposit (exactly one amount > 0)
    ///            Requires the ALM to be set (for spot price). Shares are value-weighted:
    ///            shares = depositValue / poolValue × supply, where both values are
    ///            expressed in USDC using the current spot price. The deposited token
    ///            sits in the vault and converts to the other token gradually as traders
    ///            use the pool, with the direction-aware fee module attracting the trades
    ///            that drive the conversion.
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

        (uint256 reserveUsdc, uint256 reservePurr) = getReserves();
        uint256 supply = totalSupply();

        if (supply == 0) {
            // Option 1: first deposit
            // the first depositor sets the initial ratio, which all subsequent value calculations depend on.
            // Allowing a one-token bootstrap would tie the starting ratio entirely, so we disallow it
            if (usdcAmount == 0 || purrAmount == 0) revert LP__FirstDepositRequiresBothTokens();

            shares = Math.sqrt(usdcAmount * purrAmount) - MINIMUM_LIQUIDITY;
            _mint(address(0xdead), MINIMUM_LIQUIDITY);
        } else if (usdcAmount > 0 && purrAmount > 0) {
            // Option 2 is a two-sided deposit
            // Oracle-free. min() ensures shares are proportional to whichever
            // token is the binding constraint; excess of the other is donated. - like univ2
            shares =
                Math.min(Math.mulDiv(usdcAmount, supply, reserveUsdc), Math.mulDiv(purrAmount, supply, reservePurr));
        } else {
            // Option 3 is a single-sided deposit
            // Users can deposit one token, which gradually converts into the other
            // Requires spot price to fairly value the one-token contribution.
            if (alm == address(0)) revert LP__AlmNotSet();

            // spotPrice: USDC per 1 PURR, scaled to usdcDec decimals
            // e.g. at $5 with 6-decimal USDC → spotPrice = 5_000_000
            uint256 spotPrice = ISpotPricer(alm).getSpotPriceUSDCperPURR();
            uint256 purrScale = 10 ** uint256(purrDec);

            // Express everything in USDC units for a common denominator
            uint256 poolValue = reserveUsdc + Math.mulDiv(reservePurr, spotPrice, purrScale);
            uint256 depositValue = usdcAmount + Math.mulDiv(purrAmount, spotPrice, purrScale);

            shares = Math.mulDiv(depositValue, supply, poolValue);
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
