// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Script.sol";
import {PrecompileLib} from "@hyper-evm-lib/src/PrecompileLib.sol";

/// @notice Prints PURR token index, spot universe index, and CoreWriter limit-order asset id (10000 + spotIdx).
contract ReadSpotIndex is Script {
    function run() external view {
        address purr = vm.envAddress("TOKEN0");
        address usdc = vm.envAddress("TOKEN1");

        uint64 idxPurr = PrecompileLib.getSpotIndex(purr);
        uint64 idxUsdc = PrecompileLib.getSpotIndex(usdc);
        uint64 purrTokenIndex = PrecompileLib.getTokenIndex(purr);
        uint32 spotAssetForLimitOrders = uint32(uint256(10000) + uint256(idxPurr));

        console2.log("PURR spotIndex (universe):", idxPurr);
        console2.log("USDC spotIndex:", idxUsdc);
        console2.log("purrTokenIndex (Core token index):", purrTokenIndex);
        console2.log("spotAssetIndex for CoreWriter limit orders (10000 + spotIdx):", spotAssetForLimitOrders);
    }
}
