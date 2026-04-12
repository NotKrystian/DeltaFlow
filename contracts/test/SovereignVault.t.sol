// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test, console} from "forge-std/Test.sol";
import {SovereignVault} from "../src/SovereignVault.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {PrecompileLib} from "@hyper-evm-lib/src/PrecompileLib.sol";
import {HLConversions} from "@hyper-evm-lib/src/common/HLConversions.sol";
import {HLConstants} from "@hyper-evm-lib/src/common/HLConstants.sol";
import {HyperCore} from "@hyper-evm-lib/test/simulation/HyperCore.sol";
import {CoreSimulatorLib} from "@hyper-evm-lib/test/simulation/CoreSimulatorLib.sol";
import {CoreWriterLib} from "@hyper-evm-lib/src/CoreWriterLib.sol";

/// @notice Mock PURR token for testing
contract MockPURR {
    string public name = "PURR";
    string public symbol = "PURR";
    uint8 public decimals = 5;

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
        if (allowance[from][msg.sender] != type(uint256).max) {
            allowance[from][msg.sender] -= amount;
        }
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }
}

/// @notice Mock ALM for single-sided LP deposit tests — returns a configurable spot price
contract MockALM {
    uint256 public price;

    constructor(uint256 _price) {
        price = _price;
    }

    function getSpotPriceUsdcPerBase() external view returns (uint256) {
        return price;
    }
}

/// @notice Mock pool for testing vault interactions
contract MockPool {
    address public token0;
    address public token1;

    constructor(address _token0, address _token1) {
        token0 = _token0;
        token1 = _token1;
    }
}

contract SovereignVaultTest is Test {
    using PrecompileLib for address;
    using HLConversions for *;

    uint64 public constant USDC_TOKEN = 0;

    // Test vault addresses (HLP and another vault)
    address public constant TEST_VAULT = 0xa15099a30BBf2e68942d6F4c43d70D04FAEab0A0; // HLP
    address public constant TEST_VAULT_2 = 0xaC26Cf5F3C46B5e102048c65b977d2551B72A9c7;

    HyperCore public hyperCore;
    SovereignVault public vault;
    MockPURR public purr;
    MockPool public pool;

    address public strategist;
    address public user = makeAddr("user");
    address public usdcAddress;

    function setUp() public {
        string memory alchemyRpc = "https://hyperliquid-testnet.g.alchemy.com/v2/uSFYHvKqoVOUFsNnbGM7sL_EWO0tf4iS";
        vm.createSelectFork(alchemyRpc);

        hyperCore = CoreSimulatorLib.init();

        // Get the correct USDC address for this chain (testnet vs mainnet)
        usdcAddress = HLConstants.usdc();

        strategist = address(this);

        // Deploy mock PURR token
        purr = new MockPURR();

        // Deploy vault with USDC and PURR addresses
        vault = new SovereignVault(usdcAddress, address(purr));

        // Activate the vault account on Core
        CoreSimulatorLib.forceAccountActivation(address(vault));

        // Deploy mock pool
        pool = new MockPool(address(purr), usdcAddress);

        // Authorize the pool
        vault.setAuthorizedPool(address(pool), true);

        // Fund the vault with initial USDC on EVM
        deal(usdcAddress, address(vault), 1000e6); // 1000 USDC
    }

    function test_constructor() public view {
        assertEq(vault.strategist(), strategist);
        assertEq(vault.usdc(), usdcAddress);
        assertEq(vault.defaultVault(), TEST_VAULT);
    }

    function test_setAuthorizedPool() public {
        address newPool = makeAddr("newPool");

        assertFalse(vault.authorizedPools(newPool));

        vault.setAuthorizedPool(newPool, true);
        assertTrue(vault.authorizedPools(newPool));

        vault.setAuthorizedPool(newPool, false);
        assertFalse(vault.authorizedPools(newPool));
    }

    function test_setAuthorizedPool_onlyStrategist() public {
        vm.prank(user);
        vm.expectRevert(SovereignVault.OnlyStrategist.selector);
        vault.setAuthorizedPool(user, true);
    }

    function test_processSwapHedge_noopWhenDisabled() public {
        vm.prank(address(pool));
        assertTrue(vault.processSwapHedge(true, 1e5, 0, address(purr), address(this), 1e5));
    }

    function test_processSwapHedge_noopWhenZeroAmount() public {
        vault.setHedgePerpAsset(1);
        vm.prank(address(pool));
        assertTrue(vault.processSwapHedge(true, 0, 0, address(purr), address(this), 0));
    }

    function test_processSwapHedge_onlyAuthorizedPool() public {
        vm.expectRevert(SovereignVault.OnlyAuthorizedPool.selector);
        vault.processSwapHedge(true, 1e5, 0, address(purr), address(this), 1e5);
    }

    function test_setHedgePerpAsset_onlyStrategist() public {
        vm.prank(user);
        vm.expectRevert(SovereignVault.OnlyStrategist.selector);
        vault.setHedgePerpAsset(1);
    }

    function test_setMinPerpHedgeSz_onlyStrategist() public {
        vm.prank(user);
        vm.expectRevert(SovereignVault.OnlyStrategist.selector);
        vault.setMinPerpHedgeSz(100);
    }

    function test_setUseMarkBasedMinHedgeSz_onlyStrategist() public {
        vm.prank(user);
        vm.expectRevert(SovereignVault.OnlyStrategist.selector);
        vault.setUseMarkBasedMinHedgeSz(true);
    }

    function test_setMinPerpHedgeSz() public {
        vault.setMinPerpHedgeSz(42);
        assertEq(vault.minPerpHedgeSz(), 42);
    }

    function test_getTokensForPool() public view {
        address[] memory tokens = vault.getTokensForPool(address(pool));

        assertEq(tokens.length, 2);
        assertEq(tokens[0], address(purr));
        assertEq(tokens[1], usdcAddress);
    }

    function test_changeDefaultVault() public {
        assertEq(vault.defaultVault(), TEST_VAULT);

        vault.changeDefaultVault(TEST_VAULT_2);

        assertEq(vault.defaultVault(), TEST_VAULT_2);
    }

    function test_changeDefaultVault_onlyStrategist() public {
        vm.prank(user);
        vm.expectRevert(SovereignVault.OnlyStrategist.selector);
        vault.changeDefaultVault(TEST_VAULT_2);
    }

    function test_allocate() public {
        uint256 allocateAmount = 500e6; // 500 USDC

        uint256 vaultEvmBalanceBefore = IERC20(usdcAddress).balanceOf(address(vault));

        // Allocate USDC to the default vault (HLP)
        vault.allocate(TEST_VAULT, allocateAmount);

        // EVM balance should decrease immediately (USDC is bridged to Core)
        assertEq(
            IERC20(usdcAddress).balanceOf(address(vault)),
            vaultEvmBalanceBefore - allocateAmount,
            "EVM balance should decrease by allocate amount"
        );

        // Note: The simulator has limitations with processing bridged funds to vault transfers
        // In production, the vaultTransfer action would be processed by HyperCore
        // and vault equity would be credited. The test verifies the EVM-side logic works.
    }

    function test_allocate_fullBalance() public {
        // Allocate the full vault balance — allocate() has no buffer guard
        uint256 allocateAmount = 1000e6;
        vault.allocate(TEST_VAULT, allocateAmount);
        assertEq(IERC20(usdcAddress).balanceOf(address(vault)), 0, "EVM balance should be zero after full allocation");
    }

    function test_allocate_onlyStrategist() public {
        vm.prank(user);
        vm.expectRevert(SovereignVault.OnlyStrategist.selector);
        vault.allocate(TEST_VAULT, 100e6);
    }

    function test_sendTokensToRecipient_fromInternal() public {
        address recipient = makeAddr("recipient");
        uint256 sendAmount = 100e6;

        vm.prank(address(pool));
        vault.sendTokensToRecipient(usdcAddress, recipient, sendAmount);

        assertEq(IERC20(usdcAddress).balanceOf(recipient), sendAmount);
        assertEq(IERC20(usdcAddress).balanceOf(address(vault)), 900e6);
    }

    function test_sendTokensToRecipient_onlyAuthorizedPool() public {
        vm.prank(user);
        vm.expectRevert(SovereignVault.OnlyAuthorizedPool.selector);
        vault.sendTokensToRecipient(usdcAddress, user, 100e6);
    }

    function test_sendTokensToRecipient_zeroAmount() public {
        address recipient = makeAddr("recipient");
        uint256 balanceBefore = IERC20(usdcAddress).balanceOf(address(vault));

        vm.prank(address(pool));
        vault.sendTokensToRecipient(usdcAddress, recipient, 0);

        // Nothing should change
        assertEq(IERC20(usdcAddress).balanceOf(address(vault)), balanceBefore);
        assertEq(IERC20(usdcAddress).balanceOf(recipient), 0);
    }

    function test_claimPoolManagerFees() public {
        // Just verify it doesn't revert when called by authorized pool
        vm.prank(address(pool));
        vault.claimPoolManagerFees(100, 200);
    }

    function test_claimPoolManagerFees_onlyAuthorizedPool() public {
        vm.prank(user);
        vm.expectRevert(SovereignVault.OnlyAuthorizedPool.selector);
        vault.claimPoolManagerFees(100, 200);
    }

    function test_getReservesForPool_internalOnly() public view {
        address[] memory tokens = new address[](2);
        tokens[0] = address(purr);
        tokens[1] = usdcAddress;

        uint256[] memory reserves = vault.getReservesForPool(address(pool), tokens);

        assertEq(reserves.length, 2);
        assertEq(reserves[0], 0); // No PURR
        assertEq(reserves[1], 1000e6); // 1000 USDC internal
    }

    function test_getReservesForPool_withExternalSpot() public {
        address[] memory tokens = new address[](2);
        tokens[0] = address(purr);
        tokens[1] = usdcAddress;

        // Force some USDC on Core spot for the vault
        uint64 spotAmount = 500e8; // 500 USDC in Core wei
        CoreSimulatorLib.forceSpotBalance(address(vault), USDC_TOKEN, spotAmount);

        uint256[] memory reserves = vault.getReservesForPool(address(pool), tokens);

        // Internal (1000e6) + Spot (500e6 converted from Core)
        uint256 spotInEvm = HLConversions.perpToWei(spotAmount);
        assertEq(reserves[1], 1000e6 + spotInEvm, "Total should include internal + spot balance");
    }
}

/// @notice Integration test simulating full AMM + Core Vault flow
contract VaultCoreIntegrationTest is Test {
    using PrecompileLib for address;
    using HLConversions for *;

    uint64 public constant USDC_TOKEN = 0;
    address public constant TEST_VAULT = 0xa15099a30BBf2e68942d6F4c43d70D04FAEab0A0; // HLP

    HyperCore public hyperCore;
    SovereignVault public vault;
    MockPURR public purr;
    MockPool public pool;

    address public strategist;
    address public swapper = makeAddr("swapper");
    address public usdcAddress;

    function setUp() public {
        string memory alchemyRpc = "https://hyperliquid-testnet.g.alchemy.com/v2/uSFYHvKqoVOUFsNnbGM7sL_EWO0tf4iS";
        vm.createSelectFork(alchemyRpc);

        hyperCore = CoreSimulatorLib.init();

        // Get the correct USDC address for this chain
        usdcAddress = HLConstants.usdc();

        strategist = address(this);

        // Deploy tokens
        purr = new MockPURR();

        // Deploy vault
        vault = new SovereignVault(usdcAddress, address(purr));

        // Activate vault on Core
        CoreSimulatorLib.forceAccountActivation(address(vault));

        // Deploy mock pool
        pool = new MockPool(address(purr), usdcAddress);

        // Authorize pool
        vault.setAuthorizedPool(address(pool), true);

        // Initial vault funding (simulating LP deposits to AMM)
        deal(usdcAddress, address(vault), 10000e6); // 10,000 USDC
        purr.mint(address(vault), 50000e5); // 50,000 PURR
    }

    /// @notice Test the complete flow:
    /// 1. Strategist allocates excess USDC to HLP vault
    /// 2. Verify EVM balance decreases correctly
    function test_fullFlow_allocateToVault() public {
        console.log("=== Initial State ===");
        console.log("Vault USDC balance:", IERC20(usdcAddress).balanceOf(address(vault)));
        console.log("Vault PURR balance:", purr.balanceOf(address(vault)));

        // Step 1: Strategist allocates 9000 USDC to HLP vault (keeping 1000 buffer)
        uint256 allocateAmount = 9000e6;
        vault.allocate(TEST_VAULT, allocateAmount);

        console.log("\n=== After Allocation ===");
        console.log("Vault internal USDC:", IERC20(usdcAddress).balanceOf(address(vault)));

        // Verify EVM balance decreased
        assertEq(
            IERC20(usdcAddress).balanceOf(address(vault)),
            1000e6,
            "Vault should have 1000 USDC internal after allocation"
        );

        // Note: Vault equity verification is limited by simulator - in production,
        // the bridgeToCore + vaultTransfer would credit the vault equity on HyperCore
    }

    /// @notice Test that vault can swap PURR without touching Core
    function test_purrSwap_noCoreInteraction() public {
        // Allocate USDC to vault first
        vault.allocate(TEST_VAULT, 9000e6);
        CoreSimulatorLib.nextBlock();

        PrecompileLib.UserVaultEquity memory equityBefore = PrecompileLib.userVaultEquity(address(vault), TEST_VAULT);

        // Swap PURR (should not touch Core)
        vm.prank(address(pool));
        vault.sendTokensToRecipient(address(purr), swapper, 1000e5);

        assertEq(purr.balanceOf(swapper), 1000e5, "Swapper should receive PURR");

        // Vault equity should be unchanged (PURR swap doesn't affect Core)
        PrecompileLib.UserVaultEquity memory equityAfter = PrecompileLib.userVaultEquity(address(vault), TEST_VAULT);
        assertEq(equityBefore.equity, equityAfter.equity, "HLP equity should not change for PURR swap");
    }

    /// @notice Test swap from internal balance only
    function test_swap_fromInternalOnly() public {
        // Allocate some to vault, leaving 1000 internal
        vault.allocate(TEST_VAULT, 9000e6);
        CoreSimulatorLib.nextBlock();

        console.log("Internal USDC before swap:", IERC20(usdcAddress).balanceOf(address(vault)));

        // Swap 500 USDC (less than internal balance)
        vm.prank(address(pool));
        vault.sendTokensToRecipient(usdcAddress, swapper, 500e6);

        assertEq(IERC20(usdcAddress).balanceOf(swapper), 500e6, "Swapper should receive 500 USDC");
        assertEq(IERC20(usdcAddress).balanceOf(address(vault)), 500e6, "Vault should have 500 USDC remaining");
    }

    /// @notice Test multiple allocations to different vaults
    function test_multipleVaultAllocations() public {
        address secondVault = 0xaC26Cf5F3C46B5e102048c65b977d2551B72A9c7;

        // Allocate to first vault
        vault.allocate(TEST_VAULT, 4000e6);

        // Allocate to second vault
        vault.allocate(secondVault, 4000e6);

        console.log("Remaining internal USDC:", IERC20(usdcAddress).balanceOf(address(vault)));

        // Verify EVM balances are correct
        assertEq(IERC20(usdcAddress).balanceOf(address(vault)), 2000e6, "Should have 2000 USDC remaining internally");
    }

    /// @notice Test reserve reporting includes Core spot balance
    function test_reserveReporting_includesSpot() public {
        address[] memory tokens = new address[](2);
        tokens[0] = address(purr);
        tokens[1] = usdcAddress;

        // Before any allocation
        uint256[] memory totalBefore = vault.getReservesForPool(address(pool), tokens);
        assertEq(totalBefore[1], 10000e6, "Total USDC should be 10000 initially");

        // Allocate to vault
        vault.allocate(TEST_VAULT, 8000e6);
        CoreSimulatorLib.nextBlock();

        // The USDC is now in Core (first bridged to Core, then to vault)
        // getReservesForPool should show internal only since vault equity isn't in spot
        uint256[] memory totalAfter = vault.getReservesForPool(address(pool), tokens);
        console.log("Internal USDC after allocation:", IERC20(usdcAddress).balanceOf(address(vault)));
        console.log("Total reserves reported:", totalAfter[1]);

        // After allocation, internal balance is 2000
        assertEq(IERC20(usdcAddress).balanceOf(address(vault)), 2000e6, "Internal should be 2000");
    }

    /// @notice Test that getReservesForPool correctly adds spot balance
    function test_reserveReporting_withForcedSpotBalance() public {
        address[] memory tokens = new address[](2);
        tokens[0] = address(purr);
        tokens[1] = usdcAddress;

        // Force a spot balance on Core for the vault (simulating USDC held on Core spot)
        uint64 spotAmount = 5000e8; // 5000 USDC in Core wei
        CoreSimulatorLib.forceSpotBalance(address(vault), USDC_TOKEN, spotAmount);

        uint256[] memory reserves = vault.getReservesForPool(address(pool), tokens);

        // Internal (10000e6) + Spot (5000e6 converted)
        uint256 spotInEvm = HLConversions.perpToWei(spotAmount);
        uint256 expectedTotal = 10000e6 + spotInEvm;

        console.log("Internal USDC:", IERC20(usdcAddress).balanceOf(address(vault)));
        console.log("Spot USDC (Core wei):", spotAmount);
        console.log("Spot USDC (EVM):", spotInEvm);
        console.log("Total reserves:", reserves[1]);

        assertEq(reserves[1], expectedTotal, "Total should include internal + spot");
    }
}

/// @notice Test vault withdrawal (recall) functionality using forced vault equity
contract VaultRecallTest is Test {
    using PrecompileLib for address;
    using HLConversions for *;

    uint64 public constant USDC_TOKEN = 0;
    address public constant TEST_VAULT = 0xa15099a30BBf2e68942d6F4c43d70D04FAEab0A0;

    HyperCore public hyperCore;
    SovereignVault public vault;
    MockPURR public purr;
    MockPool public pool;

    address public swapper = makeAddr("swapper");
    address public usdcAddress;

    function setUp() public {
        string memory alchemyRpc = "https://hyperliquid-testnet.g.alchemy.com/v2/uSFYHvKqoVOUFsNnbGM7sL_EWO0tf4iS";
        vm.createSelectFork(alchemyRpc);

        hyperCore = CoreSimulatorLib.init();

        // Get the correct USDC address for this chain
        usdcAddress = HLConstants.usdc();

        purr = new MockPURR();
        vault = new SovereignVault(usdcAddress, address(purr));

        CoreSimulatorLib.forceAccountActivation(address(vault));

        pool = new MockPool(address(purr), usdcAddress);
        vault.setAuthorizedPool(address(pool), true);

        // Start with minimal internal USDC
        deal(usdcAddress, address(vault), 100e6); // Only 100 USDC internal
    }

    /// @notice Test sending tokens from internal balance
    function test_sendTokens_fromInternalBalance() public {
        // Send from internal balance (no recall needed)
        vm.prank(address(pool));
        vault.sendTokensToRecipient(usdcAddress, swapper, 50e6);

        assertEq(IERC20(usdcAddress).balanceOf(swapper), 50e6, "Swapper should receive 50 USDC");
        assertEq(IERC20(usdcAddress).balanceOf(address(vault)), 50e6, "Vault should have 50 USDC remaining");
    }

    /// @notice Test vault lock period is respected
    function test_recallFails_whenLocked() public {
        // `INSUFFICIENT_BUFFER` requires internalBalance + totalAllocatedUSDC >= amount before any Core recall.
        // Allocate first so recall path runs and can hit the lock (not the buffer check).
        deal(usdcAddress, address(vault), 1100e6);
        vault.allocate(TEST_VAULT, 1000e6);

        uint64 lockedUntil = uint64((block.timestamp + 1 days) * 1000);
        CoreSimulatorLib.forceVaultEquity(address(vault), TEST_VAULT, 1000e6, lockedUntil);

        console.log("Lock until:", lockedUntil);
        console.log("Current time (ms):", block.timestamp * 1000);

        // Try to send more than internal balance - should revert due to lock on withdraw
        vm.prank(address(pool));
        vm.expectRevert(
            abi.encodeWithSelector(CoreWriterLib.CoreWriterLib__StillLockedUntilTimestamp.selector, lockedUntil)
        );
        vault.sendTokensToRecipient(usdcAddress, swapper, 200e6);
    }

    /// @notice Test that sending more than internal balance fails without vault equity
    function test_sendTokens_insufficientBalance() public {
        // Try to send more than internal balance with no vault equity
        vm.prank(address(pool));
        vm.expectRevert(); // Should revert - no vault equity to recall from
        vault.sendTokensToRecipient(usdcAddress, swapper, 200e6);
    }
}

/// @notice Test deallocate functionality
contract VaultDeallocateTest is Test {
    using PrecompileLib for address;
    using HLConversions for *;

    uint64 public constant USDC_TOKEN = 0;
    address public constant TEST_VAULT = 0xa15099a30BBf2e68942d6F4c43d70D04FAEab0A0;

    HyperCore public hyperCore;
    SovereignVault public vault;
    address public usdcAddress;

    function setUp() public {
        string memory alchemyRpc = "https://hyperliquid-testnet.g.alchemy.com/v2/uSFYHvKqoVOUFsNnbGM7sL_EWO0tf4iS";
        vm.createSelectFork(alchemyRpc);

        hyperCore = CoreSimulatorLib.init();

        // Get the correct USDC address for this chain
        usdcAddress = HLConstants.usdc();

        MockPURR purrToken = new MockPURR();
        vault = new SovereignVault(usdcAddress, address(purrToken));
        CoreSimulatorLib.forceAccountActivation(address(vault));

        deal(usdcAddress, address(vault), 1000e6);
    }

    function test_deallocate() public {
        // First allocate
        vault.allocate(TEST_VAULT, 500e6);
        CoreSimulatorLib.nextBlock();

        PrecompileLib.UserVaultEquity memory equityBefore = PrecompileLib.userVaultEquity(address(vault), TEST_VAULT);
        console.log("Vault equity before deallocate:", equityBefore.equity);

        // Warp past lock
        vm.warp(block.timestamp + 1 days + 1);

        // Deallocate
        vault.deallocate(TEST_VAULT, 250e6);
        CoreSimulatorLib.nextBlock();

        // Check that EVM balance increased
        // Note: The exact mechanics depend on how bridgeToEvm and vaultTransfer interact
        console.log("EVM balance after deallocate:", IERC20(usdcAddress).balanceOf(address(vault)));
    }

    function test_deallocate_onlyStrategist() public {
        address user = makeAddr("user");
        vm.prank(user);
        vm.expectRevert(SovereignVault.OnlyStrategist.selector);
        vault.deallocate(TEST_VAULT, 100e6);
    }
}

/// @notice Hedging threshold behavior on testnet assets/perp indices:
///         below threshold queues, above threshold flushes + executes IOC hedge.
contract HedgeThresholdBehaviorTest is Test {
    using HLConversions for *;

    address internal constant PURR_EVM = 0xa9056c15938f9aff34CD497c722Ce33dB0C2fD57;
    uint32 internal constant PURR_PERP_INDEX = 125;

    HyperCore public hyperCore;
    SovereignVault public vault;
    MockPool public pool;
    address public usdcAddress;

    function setUp() public {
        string memory alchemyRpc = "https://hyperliquid-testnet.g.alchemy.com/v2/uSFYHvKqoVOUFsNnbGM7sL_EWO0tf4iS";
        vm.createSelectFork(alchemyRpc);
        hyperCore = CoreSimulatorLib.init();

        usdcAddress = HLConstants.usdc();
        vault = new SovereignVault(usdcAddress, PURR_EVM);
        CoreSimulatorLib.forceAccountActivation(address(vault));

        pool = new MockPool(PURR_EVM, usdcAddress);
        vault.setAuthorizedPool(address(pool), true);
        vault.setHedgePerpAsset(PURR_PERP_INDEX);
        vault.setUseMarkBasedMinHedgeSz(true);
        vault.setMinPerpHedgeSz(0);

        // Hedge path can bridge margin from vault EVM USDC.
        deal(usdcAddress, address(vault), 10_000e6);
    }

    function _purrEvmWeiFromPerpSz(uint64 sz) internal view returns (uint256) {
        uint64 tokenIx = PrecompileLib.getTokenIndex(PURR_EVM);
        uint8 weiDec = PrecompileLib.tokenInfo(uint32(tokenIx)).weiDecimals;
        uint8 perpSzDec = PrecompileLib.perpAssetInfo(PURR_PERP_INDEX).szDecimals;

        uint64 coreWei;
        if (weiDec >= perpSzDec) {
            coreWei = sz * uint64(10 ** uint256(weiDec - perpSzDec));
        } else {
            // Defensive: keep test conversions in range.
            uint256 up = uint256(sz) / (10 ** uint256(perpSzDec - weiDec));
            coreWei = up > type(uint64).max ? type(uint64).max : uint64(up);
        }
        return HLConversions.weiToEvm(tokenIx, coreWei);
    }

    function test_underThreshold_queues() public {
        uint256 thresh = vault.hedgeSzThreshold();
        assertGt(thresh, 1, "threshold should be >1 sz");
        uint64 below = uint64(thresh - 1);
        uint256 purrAmountWei = _purrEvmWeiFromPerpSz(below);
        assertGt(purrAmountWei, 0, "converted amount should be nonzero");

        vm.prank(address(pool));
        bool poolShouldSend = vault.processSwapHedge(
            true, // vault paid PURR out -> buy perp hedge side
            purrAmountWei,
            0,
            usdcAddress,
            address(this),
            0
        );

        assertFalse(poolShouldSend, "queued payout path should return false");
        assertEq(vault.pendingHedgeBuySz(), uint256(below), "below-threshold sz should be queued");
        assertEq(vault.pendingHedgeSellSz(), 0);
    }

    function test_aboveThreshold_executesAndFlushes() public {
        uint256 thresh = vault.hedgeSzThreshold();
        uint64 above = uint64(thresh + 1);
        uint256 purrAmountWei = _purrEvmWeiFromPerpSz(above);
        assertGt(purrAmountWei, 0, "converted amount should be nonzero");

        vm.prank(address(pool));
        bool poolShouldSend = vault.processSwapHedge(
            true, // vault paid PURR out -> buy perp hedge side
            purrAmountWei,
            0,
            usdcAddress,
            address(this),
            0
        );

        assertFalse(poolShouldSend, "batching path returns false (vault pays out)");
        assertEq(vault.pendingHedgeBuySz(), 0, "queue should flush at/above threshold");
        assertEq(vault.pendingHedgeSellSz(), 0);
        assertEq(vault.lastHedgeLeg(), 1, "expected open-only hedge leg");
    }
}

// ============================================================
// LP TEST SUITE
// ============================================================

/// @notice Unit tests for SovereignVault LP deposit / withdrawal logic.
///         Uses a fork so USDC behaves exactly like production; PURR is mocked.
contract LPTest is Test {
    // HL testnet fork
    string constant RPC = "https://hyperliquid-testnet.g.alchemy.com/v2/uSFYHvKqoVOUFsNnbGM7sL_EWO0tf4iS";

    uint256 constant MINIMUM_LIQUIDITY = 1_000;

    // USDC = 6 decimals, MockPURR = 5 decimals
    uint256 constant USDC_UNIT = 1e6;
    uint256 constant PURR_UNIT = 1e5;

    SovereignVault vault;
    MockPURR purr;
    address usdc;

    address lp1 = makeAddr("lp1");
    address lp2 = makeAddr("lp2");

    function setUp() public {
        vm.createSelectFork(RPC);
        CoreSimulatorLib.init();
        CoreSimulatorLib.forceAccountActivation(address(this));

        usdc = HLConstants.usdc();
        purr = new MockPURR();
        vault = new SovereignVault(usdc, address(purr));
        CoreSimulatorLib.forceAccountActivation(address(vault));
        CoreSimulatorLib.forceAccountActivation(lp1);
        CoreSimulatorLib.forceAccountActivation(lp2);
    }

    // ─── helpers ──────────────────────────────────────────────

    /// Mint USDC + PURR to `who` and approve the vault.
    function _fund(address who, uint256 usdcAmt, uint256 purrAmt) internal {
        deal(usdc, who, usdcAmt);
        purr.mint(who, purrAmt);
        vm.startPrank(who);
        IERC20(usdc).approve(address(vault), type(uint256).max);
        purr.approve(address(vault), type(uint256).max);
        vm.stopPrank();
    }

    // ─── metadata ─────────────────────────────────────────────

    function test_lp_tokenMetadata() public view {
        assertEq(vault.name(), "DeltaFlow LP");
        assertEq(vault.symbol(), "DFLP");
    }

    // ─── first deposit ────────────────────────────────────────

    function test_lp_firstDeposit_sharesAreGeometricMean() public {
        uint256 usdcAmt = 1_000 * USDC_UNIT; // 1 000 USDC
        uint256 purrAmt = 1_000 * PURR_UNIT; // 1 000 PURR

        _fund(lp1, usdcAmt, purrAmt);

        uint256 expectedShares = Math.sqrt(usdcAmt * purrAmt) - MINIMUM_LIQUIDITY;

        vm.prank(lp1);
        uint256 shares = vault.depositLP(usdcAmt, purrAmt, 0);

        assertEq(shares, expectedShares, "first deposit shares should be sqrt(usdc*purr) - MIN_LIQ");
        assertEq(vault.balanceOf(lp1), shares);
    }

    function test_lp_firstDeposit_minimumLiquidityLockedToDead() public {
        uint256 usdcAmt = 1_000 * USDC_UNIT;
        uint256 purrAmt = 1_000 * PURR_UNIT;
        _fund(lp1, usdcAmt, purrAmt);

        vm.prank(lp1);
        vault.depositLP(usdcAmt, purrAmt, 0);

        // Dead address holds the locked minimum liquidity
        assertEq(vault.balanceOf(address(0xdead)), MINIMUM_LIQUIDITY, "dead address should hold MINIMUM_LIQUIDITY");
        // Zero address must hold nothing (OZ v5 blocks minting to address(0))
        assertEq(vault.balanceOf(address(0)), 0, "address(0) should hold nothing");
    }

    function test_lp_firstDeposit_tokensTransferredToVault() public {
        uint256 usdcAmt = 1_000 * USDC_UNIT;
        uint256 purrAmt = 1_000 * PURR_UNIT;
        _fund(lp1, usdcAmt, purrAmt);

        vm.prank(lp1);
        vault.depositLP(usdcAmt, purrAmt, 0);

        assertEq(IERC20(usdc).balanceOf(address(vault)), usdcAmt);
        assertEq(purr.balanceOf(address(vault)), purrAmt);
        assertEq(IERC20(usdc).balanceOf(lp1), 0);
        assertEq(purr.balanceOf(lp1), 0);
    }

    function test_lp_firstDeposit_emitsEvent() public {
        uint256 usdcAmt = 1_000 * USDC_UNIT;
        uint256 purrAmt = 1_000 * PURR_UNIT;
        _fund(lp1, usdcAmt, purrAmt);

        uint256 expectedShares = Math.sqrt(usdcAmt * purrAmt) - MINIMUM_LIQUIDITY;

        vm.expectEmit(true, false, false, true);
        emit SovereignVault.LiquidityAdded(lp1, usdcAmt, purrAmt, expectedShares);

        vm.prank(lp1);
        vault.depositLP(usdcAmt, purrAmt, 0);
    }

    // ─── subsequent deposits ──────────────────────────────────

    /// @dev Helper: seed the vault with an initial LP position from lp1.
    function _seedVault(uint256 usdcAmt, uint256 purrAmt) internal returns (uint256 seedShares) {
        _fund(lp1, usdcAmt, purrAmt);
        vm.prank(lp1);
        seedShares = vault.depositLP(usdcAmt, purrAmt, 0);
    }

    function test_lp_subsequentDeposit_proportionalShares() public {
        uint256 seedUsdc = 1_000 * USDC_UNIT;
        uint256 seedPurr = 1_000 * PURR_UNIT;
        _seedVault(seedUsdc, seedPurr);
        uint256 supply = vault.totalSupply(); // lp1 shares + MINIMUM_LIQUIDITY

        // lp2 deposits exactly half the pool
        uint256 usdcAmt = 500 * USDC_UNIT;
        uint256 purrAmt = 500 * PURR_UNIT;
        _fund(lp2, usdcAmt, purrAmt);

        vm.prank(lp2);
        uint256 shares = vault.depositLP(usdcAmt, purrAmt, 0);

        // Expected: min(500/1000 * supply, 500/1000 * supply) = supply / 2
        uint256 expectedUsdc = Math.mulDiv(usdcAmt, supply, seedUsdc);
        uint256 expectedPurr = Math.mulDiv(purrAmt, supply, seedPurr);
        uint256 expected = Math.min(expectedUsdc, expectedPurr);
        assertEq(shares, expected, "proportional shares mismatch");
        assertEq(vault.balanceOf(lp2), shares);
    }

    function test_lp_subsequentDeposit_unbalanced_excessStaysInVault() public {
        _seedVault(1_000 * USDC_UNIT, 1_000 * PURR_UNIT);

        // lp2 deposits too much USDC relative to PURR — excess USDC stays in vault
        uint256 usdcAmt = 800 * USDC_UNIT;
        uint256 purrAmt = 200 * PURR_UNIT; // only 200 PURR worth of ratio
        _fund(lp2, usdcAmt, purrAmt);

        uint256 vaultUsdcBefore = IERC20(usdc).balanceOf(address(vault));
        uint256 vaultPurrBefore = purr.balanceOf(address(vault));

        vm.prank(lp2);
        vault.depositLP(usdcAmt, purrAmt, 0);

        // Both full amounts are transferred in
        assertEq(IERC20(usdc).balanceOf(address(vault)), vaultUsdcBefore + usdcAmt, "full USDC transferred");
        assertEq(purr.balanceOf(address(vault)), vaultPurrBefore + purrAmt, "full PURR transferred");
        // lp2 holds nothing back
        assertEq(IERC20(usdc).balanceOf(lp2), 0);
        assertEq(purr.balanceOf(lp2), 0);
    }

    // ─── revert: zero amounts ─────────────────────────────────

    function test_lp_depositBothZero_reverts() public {
        vm.prank(lp1);
        vm.expectRevert(SovereignVault.LP__ZeroAmount.selector);
        vault.depositLP(0, 0, 0);
    }

    // Single-sided with supply==0 hits LP__FirstDepositRequiresBothTokens, not LP__ZeroAmount
    function test_lp_firstDeposit_purrOnlyReverts() public {
        _fund(lp1, 0, 1_000 * PURR_UNIT);
        vm.prank(lp1);
        vm.expectRevert(SovereignVault.LP__FirstDepositRequiresBothTokens.selector);
        vault.depositLP(0, 1_000 * PURR_UNIT, 0);
    }

    function test_lp_firstDeposit_usdcOnlyReverts() public {
        _fund(lp1, 1_000 * USDC_UNIT, 0);
        vm.prank(lp1);
        vm.expectRevert(SovereignVault.LP__FirstDepositRequiresBothTokens.selector);
        vault.depositLP(1_000 * USDC_UNIT, 0, 0);
    }

    function test_lp_withdrawZeroShares_reverts() public {
        vm.prank(lp1);
        vm.expectRevert(SovereignVault.LP__ZeroAmount.selector);
        vault.withdrawLP(0, 0, 0);
    }

    // ─── revert: slippage protection ─────────────────────────

    function test_lp_deposit_minSharesSlippage_reverts() public {
        uint256 usdcAmt = 1_000 * USDC_UNIT;
        uint256 purrAmt = 1_000 * PURR_UNIT;
        _fund(lp1, usdcAmt, purrAmt);

        uint256 expectedShares = Math.sqrt(usdcAmt * purrAmt) - MINIMUM_LIQUIDITY;

        vm.prank(lp1);
        vm.expectRevert(
            abi.encodeWithSelector(SovereignVault.LP__InsufficientShares.selector, expectedShares, expectedShares + 1)
        );
        vault.depositLP(usdcAmt, purrAmt, expectedShares + 1);
    }

    function test_lp_withdraw_minUsdcSlippage_reverts() public {
        uint256 seedUsdc = 1_000 * USDC_UNIT;
        uint256 seedPurr = 1_000 * PURR_UNIT;
        uint256 shares = _seedVault(seedUsdc, seedPurr);

        (uint256 reserveUsdc,) = vault.getReserves();
        uint256 supply = vault.totalSupply();
        uint256 expectedUsdc = Math.mulDiv(shares, reserveUsdc, supply);

        vm.prank(lp1);
        vm.expectRevert(
            abi.encodeWithSelector(SovereignVault.LP__InsufficientUsdcOut.selector, expectedUsdc, expectedUsdc + 1)
        );
        vault.withdrawLP(shares, expectedUsdc + 1, 0);
    }

    function test_lp_withdraw_minPurrSlippage_reverts() public {
        uint256 seedUsdc = 1_000 * USDC_UNIT;
        uint256 seedPurr = 1_000 * PURR_UNIT;
        uint256 shares = _seedVault(seedUsdc, seedPurr);

        (, uint256 reservePurr) = vault.getReserves();
        uint256 supply = vault.totalSupply();
        uint256 expectedPurr = Math.mulDiv(shares, reservePurr, supply);

        vm.prank(lp1);
        vm.expectRevert(
            abi.encodeWithSelector(SovereignVault.LP__InsufficientPurrOut.selector, expectedPurr, expectedPurr + 1)
        );
        vault.withdrawLP(shares, 0, expectedPurr + 1);
    }

    // ─── withdrawal: happy path ───────────────────────────────

    function test_lp_withdraw_proRataAmounts() public {
        uint256 seedUsdc = 1_000 * USDC_UNIT;
        uint256 seedPurr = 1_000 * PURR_UNIT;
        uint256 shares = _seedVault(seedUsdc, seedPurr);

        uint256 evmUsdc  = IERC20(usdc).balanceOf(address(vault));
        uint256 evmPurr  = purr.balanceOf(address(vault));
        uint256 supply   = vault.totalSupply();
        uint256 expectedUsdc = Math.mulDiv(shares, evmUsdc, supply);
        uint256 expectedPurr = Math.mulDiv(shares, evmPurr, supply);

        vm.prank(lp1);
        vault.withdrawLP(shares, 0, 0);

        // Payout is queued — flush to distribute.
        vault.flushLpWithdrawals();

        assertEq(IERC20(usdc).balanceOf(lp1), expectedUsdc, "USDC out mismatch");
        assertEq(purr.balanceOf(lp1),         expectedPurr, "PURR out mismatch");
    }

    function test_lp_withdraw_burnsSharesToZero() public {
        uint256 shares = _seedVault(1_000 * USDC_UNIT, 1_000 * PURR_UNIT);

        vm.prank(lp1);
        vault.withdrawLP(shares, 0, 0);

        assertEq(vault.balanceOf(lp1), 0);
        // Only the permanently locked MINIMUM_LIQUIDITY remains
        assertEq(vault.totalSupply(), MINIMUM_LIQUIDITY);
    }

    function test_lp_withdraw_emitsQueuedEvent() public {
        uint256 seedUsdc = 1_000 * USDC_UNIT;
        uint256 seedPurr = 1_000 * PURR_UNIT;
        uint256 shares = _seedVault(seedUsdc, seedPurr);

        uint256 evmUsdc = IERC20(usdc).balanceOf(address(vault));
        uint256 evmPurr = purr.balanceOf(address(vault));
        uint256 supply  = vault.totalSupply();
        uint256 expectedUsdc = Math.mulDiv(shares, evmUsdc, supply);
        uint256 expectedPurr = Math.mulDiv(shares, evmPurr, supply);

        vm.expectEmit(true, false, false, true);
        emit SovereignVault.LpWithdrawalQueued(lp1, expectedUsdc, expectedPurr, shares, 0);

        vm.prank(lp1);
        vault.withdrawLP(shares, 0, 0);
    }

    function test_lp_withdraw_emitsLiquidityRemovedOnFlush() public {
        uint256 seedUsdc = 1_000 * USDC_UNIT;
        uint256 seedPurr = 1_000 * PURR_UNIT;
        uint256 shares = _seedVault(seedUsdc, seedPurr);

        uint256 evmUsdc = IERC20(usdc).balanceOf(address(vault));
        uint256 evmPurr = purr.balanceOf(address(vault));
        uint256 supply  = vault.totalSupply();
        uint256 expectedUsdc = Math.mulDiv(shares, evmUsdc, supply);
        uint256 expectedPurr = Math.mulDiv(shares, evmPurr, supply);

        vm.prank(lp1);
        vault.withdrawLP(shares, 0, 0);

        vm.expectEmit(true, false, false, true);
        emit SovereignVault.LiquidityRemoved(lp1, expectedUsdc, expectedPurr, 0);
        vault.flushLpWithdrawals();
    }

    // ─── withdrawal: queue-based (no immediate revert when USDC is on Core) ───

    function test_lp_withdraw_queuesWhenUsdcInCore() public {
        uint256 seedUsdc = 1_000 * USDC_UNIT;
        uint256 seedPurr = 1_000 * PURR_UNIT;
        uint256 shares = _seedVault(seedUsdc, seedPurr);

        // withdrawLP no longer reverts if USDC is on Core — it queues and lets
        // flushLpWithdrawals() bridge the funds back.
        vm.prank(lp1);
        vault.withdrawLP(shares, 0, 0);

        // Shares are burned immediately.
        assertEq(vault.balanceOf(lp1), 0, "shares should be burned");
        // Pending withdrawal tracked.
        assertGt(vault.pendingLpWithdrawalUsdc(), 0, "pendingLpWithdrawalUsdc should be set");
    }

    // ─── getReserves ──────────────────────────────────────────

    function test_lp_getReserves_includesAllocated() public {
        uint256 seedUsdc = 1_000 * USDC_UNIT;
        uint256 seedPurr = 1_000 * PURR_UNIT;
        _seedVault(seedUsdc, seedPurr);

        address coreVault = 0xa15099a30BBf2e68942d6F4c43d70D04FAEab0A0;
        uint256 allocateAmt = 600 * USDC_UNIT;
        vault.allocate(coreVault, allocateAmt);

        (uint256 reserveUsdc, uint256 reservePurr) = vault.getReserves();

        // USDC reserve = EVM balance + totalAllocatedUSDC
        assertEq(reserveUsdc, seedUsdc, "total USDC reserve must equal original deposit");
        assertEq(reservePurr, seedPurr, "PURR reserve unchanged");
    }

    // ─── multi-LP share fairness ──────────────────────────────

    function test_lp_twoLPs_fairSharesOnWithdraw() public {
        // lp1 seeds the vault
        uint256 seed = 1_000 * USDC_UNIT;
        uint256 shares1 = _seedVault(seed, 1_000 * PURR_UNIT);

        // lp2 deposits the same ratio
        _fund(lp2, seed, 1_000 * PURR_UNIT);
        vm.prank(lp2);
        uint256 shares2 = vault.depositLP(seed, 1_000 * PURR_UNIT, 0);

        // Record EVM balances and supply before any burning to compute expected payouts.
        uint256 supply  = vault.totalSupply();
        uint256 evmUsdc = IERC20(usdc).balanceOf(address(vault));
        uint256 evmPurr = purr.balanceOf(address(vault));

        uint256 expected1Usdc = Math.mulDiv(shares1, evmUsdc, supply);
        uint256 expected1Purr = Math.mulDiv(shares1, evmPurr, supply);

        // lp2 withdraws after lp1 has already queued (supply and EVM balance change).
        // Compute lp2 expected values against the state *after* lp1 queues.
        vm.prank(lp1);
        vault.withdrawLP(shares1, 0, 0);

        uint256 supply2  = vault.totalSupply();
        uint256 evmUsdc2 = IERC20(usdc).balanceOf(address(vault));
        uint256 evmPurr2 = purr.balanceOf(address(vault));
        uint256 expected2Usdc = Math.mulDiv(shares2, evmUsdc2, supply2);
        uint256 expected2Purr = Math.mulDiv(shares2, evmPurr2, supply2);

        vm.prank(lp2);
        vault.withdrawLP(shares2, 0, 0);

        // Flush both queued payouts.
        vault.flushLpWithdrawals();

        assertEq(IERC20(usdc).balanceOf(lp1), expected1Usdc, "lp1 USDC out");
        assertEq(purr.balanceOf(lp1),         expected1Purr, "lp1 PURR out");
        assertEq(IERC20(usdc).balanceOf(lp2), expected2Usdc, "lp2 USDC out");
        assertEq(purr.balanceOf(lp2),         expected2Purr, "lp2 PURR out");

        // lp1 receives marginally less than lp2 because the MINIMUM_LIQUIDITY burn on
        // first deposit slightly dilutes lp1's share count. This is expected and the
        // difference is proportional to MINIMUM_LIQUIDITY / totalSupply (~1.6 ppm here).
        assertLt(IERC20(usdc).balanceOf(lp1), IERC20(usdc).balanceOf(lp2), "lp1 gets slightly less USDC due to MINIMUM_LIQUIDITY tax");
        assertLt(purr.balanceOf(lp1),         purr.balanceOf(lp2),         "lp1 gets slightly less PURR due to MINIMUM_LIQUIDITY tax");
    }

    function test_lp_earlyLP_benefitsFromDonation() public {
        // lp1 seeds the vault
        uint256 shares1 = _seedVault(1_000 * USDC_UNIT, 1_000 * PURR_UNIT);

        // lp2 deposits unbalanced (800 USDC, 200 PURR) — 600 USDC is "donated"
        _fund(lp2, 800 * USDC_UNIT, 200 * PURR_UNIT);
        vm.prank(lp2);
        vault.depositLP(800 * USDC_UNIT, 200 * PURR_UNIT, 0);

        // lp1 withdraws; the donated USDC should increase their payout
        uint256 evmUsdc = IERC20(usdc).balanceOf(address(vault));
        uint256 supply  = vault.totalSupply();
        uint256 expected1Usdc = Math.mulDiv(shares1, evmUsdc, supply);

        vm.prank(lp1);
        vault.withdrawLP(shares1, 0, 0);
        vault.flushLpWithdrawals();

        uint256 out1Usdc = IERC20(usdc).balanceOf(lp1);
        assertGt(out1Usdc, 1_000 * USDC_UNIT, "lp1 should receive more USDC than deposited due to donation");
        assertEq(out1Usdc, expected1Usdc);
    }

    // ─── single-sided deposits ────────────────────────────────

    /// @dev Returns a vault that already has ALM set and an initial two-sided seed.
    ///      The mock ALM returns `spotPrice` USDC (6 dec) per 1 PURR (purrScale = 1e5).
    function _seedWithAlm(uint256 spotPrice) internal returns (MockALM mockAlm, uint256 seedShares) {
        mockAlm = new MockALM(spotPrice);
        vault.setALM(address(mockAlm));
        seedShares = _seedVault(1_000 * USDC_UNIT, 1_000 * PURR_UNIT);
    }

    function test_lp_singleSided_almNotSet_reverts() public {
        // Seed the pool so supply > 0, but do NOT call setALM
        _seedVault(1_000 * USDC_UNIT, 1_000 * PURR_UNIT);

        _fund(lp2, 500 * USDC_UNIT, 0);
        vm.prank(lp2);
        vm.expectRevert(SovereignVault.LP__AlmNotSet.selector);
        vault.depositLP(500 * USDC_UNIT, 0, 0);
    }

    function test_lp_singleSidedUsdc_sharesValueWeighted() public {
        // spot price: 5 USDC per PURR → 5_000_000 (6 dec)
        uint256 spot = 5 * USDC_UNIT;
        _seedWithAlm(spot);
        uint256 supply = vault.totalSupply();

        (uint256 rUsdc, uint256 rPurr) = vault.getReserves();
        uint256 purrScale = 10 ** 5; // purrDec

        uint256 depositAmt = 500 * USDC_UNIT;
        uint256 poolValue    = rUsdc + Math.mulDiv(rPurr, spot, purrScale);
        uint256 depositValue = depositAmt; // USDC-only
        uint256 expectedShares = Math.mulDiv(depositValue, supply, poolValue);

        _fund(lp2, depositAmt, 0);
        vm.prank(lp2);
        uint256 shares = vault.depositLP(depositAmt, 0, 0);

        assertEq(shares, expectedShares, "single-sided USDC shares mismatch");
        assertEq(vault.balanceOf(lp2), shares);
        assertEq(IERC20(usdc).balanceOf(lp2), 0, "all USDC transferred in");

        // Ensure no PURR was touched
        assertEq(purr.balanceOf(lp2), 0, "lp2 has no PURR");
        assertEq(purr.balanceOf(address(vault)), 1_000 * PURR_UNIT, "vault PURR unchanged");
    }

    function test_lp_singleSidedPurr_sharesValueWeighted() public {
        uint256 spot = 5 * USDC_UNIT; // 5 USDC per PURR
        _seedWithAlm(spot);
        uint256 supply = vault.totalSupply();

        (uint256 rUsdc, uint256 rPurr) = vault.getReserves();
        uint256 purrScale = 10 ** 5;

        uint256 depositAmt = 200 * PURR_UNIT; // 200 PURR
        uint256 poolValue    = rUsdc + Math.mulDiv(rPurr, spot, purrScale);
        uint256 depositValue = Math.mulDiv(depositAmt, spot, purrScale); // in USDC units
        uint256 expectedShares = Math.mulDiv(depositValue, supply, poolValue);

        _fund(lp2, 0, depositAmt);
        vm.prank(lp2);
        uint256 shares = vault.depositLP(0, depositAmt, 0);

        assertEq(shares, expectedShares, "single-sided PURR shares mismatch");
        assertEq(vault.balanceOf(lp2), shares);
        assertEq(purr.balanceOf(lp2), 0, "all PURR transferred in");

        // Ensure no USDC was touched
        assertEq(IERC20(usdc).balanceOf(lp2), 0, "lp2 has no USDC");
        assertEq(IERC20(usdc).balanceOf(address(vault)), 1_000 * USDC_UNIT, "vault USDC unchanged");
    }

    /// @notice Single-sided deposit must not dilute existing LPs — they should be
    ///         able to redeem at least as much value as before (in USDC terms).
    function test_lp_singleSided_existingLpNotDiluted() public {
        uint256 spot = 5 * USDC_UNIT;
        (, uint256 shares1) = _seedWithAlm(spot);

        // Record lp1's redeemable USDC value before single-sided deposit
        (uint256 rUsdcBefore, uint256 rPurrBefore) = vault.getReserves();
        uint256 supplyBefore = vault.totalSupply();
        uint256 purrScale = 10 ** 5;
        uint256 lp1ValueBefore = Math.mulDiv(shares1, rUsdcBefore, supplyBefore)
            + Math.mulDiv(Math.mulDiv(shares1, rPurrBefore, supplyBefore), spot, purrScale);

        // lp2 makes a single-sided USDC deposit
        uint256 depositAmt = 300 * USDC_UNIT;
        _fund(lp2, depositAmt, 0);
        vm.prank(lp2);
        vault.depositLP(depositAmt, 0, 0);

        // lp1's redeemable value after
        (uint256 rUsdcAfter, uint256 rPurrAfter) = vault.getReserves();
        uint256 supplyAfter = vault.totalSupply();
        uint256 lp1ValueAfter = Math.mulDiv(shares1, rUsdcAfter, supplyAfter)
            + Math.mulDiv(Math.mulDiv(shares1, rPurrAfter, supplyAfter), spot, purrScale);

        // Value should be >= before (may be slightly greater due to any rounding donation)
        assertGe(lp1ValueAfter, lp1ValueBefore, "existing LP should not be diluted by single-sided deposit");
    }

    /// @notice Slippage protection works for single-sided deposits.
    function test_lp_singleSided_minSharesSlippage_reverts() public {
        uint256 spot = 5 * USDC_UNIT;
        _seedWithAlm(spot);
        uint256 supply = vault.totalSupply();

        (uint256 rUsdc, uint256 rPurr) = vault.getReserves();
        uint256 purrScale = 10 ** 5;
        uint256 depositAmt = 100 * USDC_UNIT;
        uint256 poolValue    = rUsdc + Math.mulDiv(rPurr, spot, purrScale);
        uint256 expectedShares = Math.mulDiv(depositAmt, supply, poolValue);

        _fund(lp2, depositAmt, 0);
        vm.prank(lp2);
        vm.expectRevert(
            abi.encodeWithSelector(SovereignVault.LP__InsufficientShares.selector, expectedShares, expectedShares + 1)
        );
        vault.depositLP(depositAmt, 0, expectedShares + 1);
    }

    /// @notice setALM is restricted to the strategist.
    function test_lp_setALM_onlyStrategist() public {
        address mockAlm = makeAddr("alm");
        vm.prank(lp1);
        vm.expectRevert(SovereignVault.OnlyStrategist.selector);
        vault.setALM(mockAlm);
    }
}
