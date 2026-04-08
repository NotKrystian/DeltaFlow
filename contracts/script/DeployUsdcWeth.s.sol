// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "forge-std/console2.sol";

import {AmmDeployBase} from "./AmmDeployBase.s.sol";

/// @notice Deploy a single USDC/WETH stack (vault, pool, ALM, fee module). Optional HedgeEscrow.
/// @dev Env: `USDC`, `WETH`, `SPOT_INDEX_WETH`, `INVERT_WETH_PX`, plus the same pool/fee keys as `DeployAll`
///      (`POOL_MANAGER`, `DEFAULT_SWAP_FEE_BIPS`, `BASE_FEE_BIPS`, …). Optional `RAW_PX_SCALE_WETH`, `RAW_PX_SCALE`.
contract DeployUsdcWeth is AmmDeployBase {
    function run() external {
        Params memory p = _loadWethOnly();
        bool hedge = vm.envOr("DEPLOY_HEDGE_ESCROW", false);

        console2.log("ChainId:", block.chainid);
        console2.log("DeployUsdcWeth deployer:", p.deployer);

        vm.startBroadcast(p.pk);
        _deployOneStack(p, hedge, "USDC/WETH");
        vm.stopBroadcast();
    }
}
