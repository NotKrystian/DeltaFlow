// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test, console} from "forge-std/Test.sol";
import {SovereignALM} from "../src/SovereignALM.sol";
import {SovereignPool} from "../src/SovereignPool.sol";
import {SovereignPoolConstructorArgs, SovereignPoolSwapParams, SovereignPoolSwapContextData} from "../src/structs/SovereignPoolStructs.sol";
import {ALMLiquidityQuoteInput, ALMLiquidityQuote} from "../src/ALM/structs/SovereignALMStructs.sol";
import {PrecompileLib} from "@hyper-evm-lib/src/PrecompileLib.sol";
import {PrecompileSimulator} from "@hyper-evm-lib/test/utils/PrecompileSimulator.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice Fork tests - uses real Hyperliquid mainnet prices
contract SovereignALMForkTest is Test {
    SovereignALM public alm;
    SovereignPool public pool;

    // PURR token on Hyperliquid TESTNET
    address constant PURR = 0xa9056c15938f9aff34CD497c722Ce33dB0C2fD57;
    address constant USDC = 0x5555555555555555555555555555555555555555; // Native USDC placeholder

    function setUp() public {
        // Fork Hyperliquid testnet
        vm.createSelectFork("https://hyperliquid-testnet.g.alchemy.com/v2/uSFYHvKqoVOUFsNnbGM7sL_EWO0tf4iS");

        // Initialize precompile simulator to enable L1 reads
        PrecompileSimulator.init();

        // Deploy pool with PURR/USDC
        SovereignPoolConstructorArgs memory args = SovereignPoolConstructorArgs({
            token0: PURR,
            token1: USDC,
            protocolFactory: address(this),
            poolManager: address(this),
            sovereignVault: address(0),
            verifierModule: address(0),
            isToken0Rebase: false,
            isToken1Rebase: false,
            token0AbsErrorTolerance: 0,
            token1AbsErrorTolerance: 0,
            defaultSwapFeeBips: 30,
            hedgePerpAssetIndex: 0
        });

        pool = new SovereignPool(args);
        alm = new SovereignALM(address(pool));

        // Set ALM on pool
        pool.setALM(address(alm));
    }

    function test_getSpotPrice() public view {
        uint64 price = alm.getSpotPrice();
        console.log("PURR/USDC spot price (8 decimals):", price);

        // Price should be non-zero
        assertGt(price, 0, "Spot price should be non-zero");
    }

    function test_getToken0Info() public view {
        PrecompileLib.TokenInfo memory info = alm.getToken0Info();

        console.log("Token name:", info.name);
        console.log("Wei decimals:", info.weiDecimals);
        console.log("Sz decimals:", info.szDecimals);

        assertEq(info.evmContract, PURR, "EVM contract should match PURR");
    }

    function test_getLiquidityQuote_ZeroToOne() public {
        // Swap 1 PURR (weiDecimals=5) to USDC
        uint256 amountIn = 1e5; // 1 PURR in wei decimals

        ALMLiquidityQuoteInput memory input = ALMLiquidityQuoteInput({
            isZeroToOne: true,
            amountInMinusFee: amountIn,
            feeInBips: 0,
            sender: address(this),
            recipient: address(this),
            tokenOutSwap: USDC
        });

        vm.prank(address(pool));
        ALMLiquidityQuote memory quote = alm.getLiquidityQuote(input, "", "");

        console.log("Input: 1 PURR (1e5 wei)");
        console.log("Output USDC (6 decimals):", quote.amountOut);
        console.log("Spot price:", alm.getSpotPrice());

        // Verify output is non-zero and matches input filled
        assertGt(quote.amountOut, 0, "Amount out should be non-zero");
        assertEq(quote.amountInFilled, amountIn, "Amount in filled should match input");

        // At ~$4.71 PURR price, 1 PURR should give ~4.71e6 USDC
        assertApproxEqRel(quote.amountOut, 4.71e6, 0.05e18, "Output should be ~4.71 USDC");
    }

    function test_getLiquidityQuote_OneToZero() public {
        // Swap 10 USDC (6 decimals) to PURR
        uint256 amountIn = 10e6; // 10 USDC

        ALMLiquidityQuoteInput memory input = ALMLiquidityQuoteInput({
            isZeroToOne: false,
            amountInMinusFee: amountIn,
            feeInBips: 0,
            sender: address(this),
            recipient: address(this),
            tokenOutSwap: PURR
        });

        vm.prank(address(pool));
        ALMLiquidityQuote memory quote = alm.getLiquidityQuote(input, "", "");

        console.log("Input: 10 USDC (10e6)");
        console.log("Output PURR (5 decimals):", quote.amountOut);
        console.log("Spot price:", alm.getSpotPrice());

        // Verify output is non-zero
        assertGt(quote.amountOut, 0, "Amount out should be non-zero");

        // At ~$4.71/PURR, 10 USDC should give ~2.12 PURR (~2.12e5 in 5 decimals)
        assertApproxEqRel(quote.amountOut, 2.12e5, 0.05e18, "Output should be ~2.12 PURR");
    }

    function test_onlyPool_getLiquidityQuote() public {
        ALMLiquidityQuoteInput memory input = ALMLiquidityQuoteInput({
            isZeroToOne: true,
            amountInMinusFee: 1e18,
            feeInBips: 0,
            sender: address(this),
            recipient: address(this),
            tokenOutSwap: USDC
        });

        // Should work - getLiquidityQuote is view, no onlyPool restriction
        alm.getLiquidityQuote(input, "", "");
    }

    function test_onlyPool_onSwapCallback() public {
        // Should revert when called by non-pool
        vm.expectRevert(SovereignALM.SovereignALM__OnlyPool.selector);
        alm.onSwapCallback(true, 1e18, 1e6);

        // Should succeed when called by pool
        vm.prank(address(pool));
        alm.onSwapCallback(true, 1e18, 1e6);
    }

    function test_onlyPool_onDepositLiquidityCallback() public {
        // Should revert when called by non-pool
        vm.expectRevert(SovereignALM.SovereignALM__OnlyPool.selector);
        alm.onDepositLiquidityCallback(1e18, 1e6, "");

        // Should succeed when called by pool
        vm.prank(address(pool));
        alm.onDepositLiquidityCallback(1e18, 1e6, "");
    }
}

/// @notice Integration test for actual swaps through the pool
contract SovereignALMSwapTest is Test {
    SovereignALM public alm;
    SovereignPool public pool;

    // PURR token on Hyperliquid TESTNET
    address constant PURR = 0xa9056c15938f9aff34CD497c722Ce33dB0C2fD57;

    // We need a real USDC address on testnet - using a mock for now
    MockUSDC public usdc;

    address public swapper = makeAddr("swapper");

    function setUp() public {
        // Fork Hyperliquid testnet
        vm.createSelectFork("https://hyperliquid-testnet.g.alchemy.com/v2/uSFYHvKqoVOUFsNnbGM7sL_EWO0tf4iS");
        PrecompileSimulator.init();

        // Deploy mock USDC for testing (since we need to control token transfers)
        usdc = new MockUSDC();

        // Deploy pool with PURR/USDC - pool holds reserves (sovereignVault = address(0) means pool itself)
        // Using isRebase=true so pool uses balanceOf() instead of internal reserves (allows deal() for testing)
        SovereignPoolConstructorArgs memory args = SovereignPoolConstructorArgs({
            token0: PURR,
            token1: address(usdc),
            protocolFactory: address(this),
            poolManager: address(this),
            sovereignVault: address(0), // Pool holds its own reserves
            verifierModule: address(0),
            isToken0Rebase: true,  // Use balanceOf for reserve checks
            isToken1Rebase: true,  // Use balanceOf for reserve checks
            token0AbsErrorTolerance: 10, // Max allowed is 10
            token1AbsErrorTolerance: 10, // Max allowed is 10
            defaultSwapFeeBips: 30, // 0.3% fee
            hedgePerpAssetIndex: 0
        });

        pool = new SovereignPool(args);
        alm = new SovereignALM(address(pool));
        pool.setALM(address(alm));

        // Provide liquidity to the pool using deal()
        // Give pool 10000 PURR (1e5 decimals = 1e9 total)
        deal(PURR, address(pool), 10000e5);
        // Give pool 50000 USDC (6 decimals = 5e10 total)
        usdc.mint(address(pool), 50000e6);

        // Give swapper some tokens
        deal(PURR, swapper, 100e5); // 100 PURR
        usdc.mint(swapper, 1000e6); // 1000 USDC
    }

    /// @notice Test swapping PURR -> USDC through the pool
    function test_swap_PurrToUsdc() public {
        uint256 amountIn = 10e5; // 10 PURR

        // Check balances before
        uint256 swapperPurrBefore = IERC20(PURR).balanceOf(swapper);
        uint256 swapperUsdcBefore = usdc.balanceOf(swapper);
        uint256 poolPurrBefore = IERC20(PURR).balanceOf(address(pool));
        uint256 poolUsdcBefore = usdc.balanceOf(address(pool));

        console.log("=== Before Swap ===");
        console.log("Swapper PURR:", swapperPurrBefore);
        console.log("Swapper USDC:", swapperUsdcBefore);
        console.log("Pool PURR:", poolPurrBefore);
        console.log("Pool USDC:", poolUsdcBefore);
        console.log("Spot price:", alm.getSpotPrice());

        // Approve pool to spend PURR
        vm.startPrank(swapper);
        IERC20(PURR).approve(address(pool), amountIn);

        // Execute swap
        SovereignPoolSwapParams memory swapParams = SovereignPoolSwapParams({
            isSwapCallback: false,
            isZeroToOne: true, // PURR (token0) -> USDC (token1)
            amountIn: amountIn,
            amountOutMin: 0, // No slippage protection for test
            deadline: block.timestamp + 1000,
            recipient: swapper,
            swapTokenOut: address(usdc),
            swapContext: SovereignPoolSwapContextData({
                externalContext: "",
                verifierContext: "",
                swapCallbackContext: "",
                swapFeeModuleContext: ""
            })
        });

        (uint256 amountInUsed, uint256 amountOut) = pool.swap(swapParams);
        vm.stopPrank();

        console.log("=== After Swap ===");
        console.log("Amount In Used:", amountInUsed);
        console.log("Amount Out:", amountOut);
        console.log("Swapper PURR:", IERC20(PURR).balanceOf(swapper));
        console.log("Swapper USDC:", usdc.balanceOf(swapper));

        // Verify swap happened
        assertGt(amountOut, 0, "Should receive USDC");
        assertEq(amountInUsed, amountIn, "Should use full input amount");

        // At ~$4.71/PURR, 10 PURR should give ~47.1 USDC (minus 0.3% fee)
        // Expected: 10 * 4.718 * 0.997 ≈ 47.04 USDC
        assertApproxEqRel(amountOut, 47e6, 0.05e18, "Output should be ~47 USDC");

        // Verify balance changes
        assertEq(IERC20(PURR).balanceOf(swapper), swapperPurrBefore - amountIn, "PURR should decrease");
        assertEq(usdc.balanceOf(swapper), swapperUsdcBefore + amountOut, "USDC should increase");
    }

    /// @notice Test swapping USDC -> PURR through the pool
    function test_swap_UsdcToPurr() public {
        uint256 amountIn = 100e6; // 100 USDC

        // Check balances before
        uint256 swapperPurrBefore = IERC20(PURR).balanceOf(swapper);
        uint256 swapperUsdcBefore = usdc.balanceOf(swapper);

        console.log("=== Before Swap ===");
        console.log("Swapper PURR:", swapperPurrBefore);
        console.log("Swapper USDC:", swapperUsdcBefore);
        console.log("Spot price:", alm.getSpotPrice());

        // Approve pool to spend USDC
        vm.startPrank(swapper);
        usdc.approve(address(pool), amountIn);

        // Execute swap
        SovereignPoolSwapParams memory swapParams = SovereignPoolSwapParams({
            isSwapCallback: false,
            isZeroToOne: false, // USDC (token1) -> PURR (token0)
            amountIn: amountIn,
            amountOutMin: 0,
            deadline: block.timestamp + 1000,
            recipient: swapper,
            swapTokenOut: PURR,
            swapContext: SovereignPoolSwapContextData({
                externalContext: "",
                verifierContext: "",
                swapCallbackContext: "",
                swapFeeModuleContext: ""
            })
        });

        (uint256 amountInUsed, uint256 amountOut) = pool.swap(swapParams);
        vm.stopPrank();

        console.log("=== After Swap ===");
        console.log("Amount In Used:", amountInUsed);
        console.log("Amount Out:", amountOut);
        console.log("Swapper PURR:", IERC20(PURR).balanceOf(swapper));
        console.log("Swapper USDC:", usdc.balanceOf(swapper));

        // Verify swap happened
        assertGt(amountOut, 0, "Should receive PURR");

        // At ~$4.71/PURR, 100 USDC should give ~21.2 PURR (minus 0.3% fee)
        // Expected: 100 / 4.718 * 0.997 ≈ 21.13 PURR = 21.13e5 in 5 decimals
        assertApproxEqRel(amountOut, 21.1e5, 0.05e18, "Output should be ~21.1 PURR");

        // Verify balance changes
        assertEq(usdc.balanceOf(swapper), swapperUsdcBefore - amountIn, "USDC should decrease");
        assertEq(IERC20(PURR).balanceOf(swapper), swapperPurrBefore + amountOut, "PURR should increase");
    }
}

/// @notice Mock USDC token for testing
contract MockUSDC {
    string public name = "USD Coin";
    string public symbol = "USDC";
    uint8 public decimals = 6;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }
}

/// @notice Simple mock ERC20 for testing
contract MockERC20 {
    string public name;
    string public symbol;
    uint8 public decimals;

    constructor(string memory _name, string memory _symbol, uint8 _decimals) {
        name = _name;
        symbol = _symbol;
        decimals = _decimals;
    }
}
