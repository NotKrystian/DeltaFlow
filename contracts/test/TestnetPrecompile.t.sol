// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test, console} from "forge-std/Test.sol";
import {PrecompileLib} from "@hyper-evm-lib/src/PrecompileLib.sol";
import {PrecompileSimulator} from "@hyper-evm-lib/test/utils/PrecompileSimulator.sol";

/// @notice Test to check what's available on Hyperliquid testnet
contract TestnetPrecompileTest is Test {
    function setUp() public {
        // Fork Hyperliquid testnet
        vm.createSelectFork("https://hyperliquid-testnet.g.alchemy.com/v2/uSFYHvKqoVOUFsNnbGM7sL_EWO0tf4iS");
        PrecompileSimulator.init();
    }

    /// @notice Check if precompiles respond on testnet
    function test_l1BlockNumber() public view {
        uint64 blockNumber = PrecompileLib.l1BlockNumber();
        console.log("L1 block number:", blockNumber);
        assertGt(blockNumber, 0, "L1 block number should be > 0");
    }

    /// @notice Check USDC token info (index 0 should always be USDC)
    function test_usdcTokenInfo() public view {
        PrecompileLib.TokenInfo memory info = PrecompileLib.tokenInfo(0);
        console.log("Token 0 name:", info.name);
        console.log("Token 0 weiDecimals:", info.weiDecimals);
        console.log("Token 0 szDecimals:", info.szDecimals);
    }

    /// @notice Check HYPE token info (index 150 is typically HYPE)
    function test_hypeTokenInfo() public view {
        try this.getTokenInfo(150) returns (PrecompileLib.TokenInfo memory info) {
            console.log("Token 150 name:", info.name);
            console.log("Token 150 weiDecimals:", info.weiDecimals);
        } catch {
            console.log("Token 150 (HYPE) not found on testnet");
        }
    }

    /// @notice Try to find available spot markets
    function test_spotInfo() public view {
        // Try spot index 0
        try this.getSpotInfo(0) returns (PrecompileLib.SpotInfo memory info) {
            console.log("Spot 0 name:", info.name);
            console.log("Spot 0 token0:", info.tokens[0]);
            console.log("Spot 0 token1:", info.tokens[1]);
        } catch {
            console.log("Spot 0 not found");
        }

        // Try a few more spot indices
        for (uint64 i = 1; i <= 10; i++) {
            try this.getSpotInfo(i) returns (PrecompileLib.SpotInfo memory info) {
                console.log("---");
                console.log("Spot index:", i);
                console.log("Spot name:", info.name);
                console.log("Token0 index:", info.tokens[0]);
                console.log("Token1 index:", info.tokens[1]);
            } catch {
                // Not found, continue
            }
        }
    }

    /// @notice Check spot price for index 0
    function test_spotPrice() public view {
        try this.getSpotPx(0) returns (uint64 price) {
            console.log("Spot 0 price:", price);
        } catch {
            console.log("Spot 0 price not available");
        }
    }

    /// @notice Get PURR token info (index 1 on testnet)
    function test_purrTokenInfo() public view {
        PrecompileLib.TokenInfo memory info = PrecompileLib.tokenInfo(1);
        console.log("PURR name:", info.name);
        console.log("PURR weiDecimals:", info.weiDecimals);
        console.log("PURR szDecimals:", info.szDecimals);
        console.log("PURR evmContract:", info.evmContract);
    }

    // Helper functions to use try/catch
    function getTokenInfo(uint64 index) external view returns (PrecompileLib.TokenInfo memory) {
        return PrecompileLib.tokenInfo(index);
    }

    function getSpotInfo(uint64 index) external view returns (PrecompileLib.SpotInfo memory) {
        return PrecompileLib.spotInfo(index);
    }

    function getSpotPx(uint64 index) external view returns (uint64) {
        return PrecompileLib.spotPx(index);
    }
}
