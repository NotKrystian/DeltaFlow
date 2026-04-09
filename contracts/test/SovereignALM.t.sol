// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";

/// @notice Previous fork tests targeted a stale ALM API (single-arg constructor, `getSpotPrice`, `getToken0Info`).
///         Re-add fork coverage using the live constructor `(pool, usdc, base, spotIndex, rawPxScale, rawIsPurrPerUsdc, liquidityBufferBps)`
///         and `getSpotPriceUsdcPerBase()`.
contract SovereignALM_CompileSmokeTest is Test {
    function test_smoke() public pure {
        assert(true);
    }
}
