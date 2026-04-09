// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "forge-std/console2.sol";

import {PrecompileLib} from "@hyper-evm-lib/src/PrecompileLib.sol";
import {HedgeEscrow} from "../src/HedgeEscrow.sol";

/// @title DeployHedgeEscrow
/// @notice Standalone HedgeEscrow deploy (e.g. replacement / custom pair). **`DeployAll` already deploys HedgeEscrow per stack.**
/// @dev Uses registry `getTokenIndex` via `PrecompileLib`. Spot universe index is taken from env
/// (`SPOT_INDEX_PURR`) — must match on-chain `getSpotIndex`; do not use `getSpotIndex` here (token info
/// precompile `0x080C` is not runnable under `forge script` simulation).
contract DeployHedgeEscrow is Script {
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(pk);
        address usdc = vm.envAddress("USDC");
        address purr = vm.envAddress("PURR");

        uint64 purrTokenIndex = PrecompileLib.getTokenIndex(purr);
        uint64 spotIdx = uint64(vm.envUint("SPOT_INDEX_PURR"));
        uint32 spotAssetIndex = uint32(uint256(10000) + uint256(spotIdx));

        console2.log("=== HedgeEscrow deploy ===");
        console2.log("Deployer:", deployer);
        console2.log("USDC:", usdc);
        console2.log("PURR:", purr);
        console2.log("purrTokenIndex (Core):", purrTokenIndex);
        console2.log("spotIdx (universe index):", spotIdx);
        console2.log("spotAssetIndex (10000+spotIdx) for CoreWriter limit orders:", spotAssetIndex);

        vm.startBroadcast(pk);

        HedgeEscrow escrow = new HedgeEscrow(usdc, purr, spotAssetIndex, purrTokenIndex);

        vm.stopBroadcast();

        console2.log("=== Deployed HedgeEscrow ===");
        console2.log("HEDGE_ESCROW=", address(escrow));
        console2.log("PURR_TOKEN_INDEX (for backend)=", purrTokenIndex);
        console2.log("SPOT_ASSET_INDEX=", spotAssetIndex);
    }
}
