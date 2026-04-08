// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "forge-std/console2.sol";

import {AmmDeployBase} from "./AmmDeployBase.s.sol";

contract DeployAll is AmmDeployBase {
    function run() external {
        Params memory p = _loadPurrParams();
        bool hedge = vm.envOr("DEPLOY_HEDGE_ESCROW", false);
        bool wethToo = vm.envOr("DEPLOY_USDC_WETH", false);

        console2.log("ChainId:", block.chainid);
        console2.log("Deployer:", p.deployer);
        console2.log("PoolManager:", p.poolManager);
        console2.log("HL Agent:", p.hlAgentAddr);

        vm.startBroadcast(p.pk);

        _deployOneStack(p, hedge, "USDC/PURR");

        if (wethToo) {
            Params memory w = _loadWethParams(p);
            _deployOneStack(w, hedge, "USDC/WETH");
        }

        vm.stopBroadcast();
    }
}
