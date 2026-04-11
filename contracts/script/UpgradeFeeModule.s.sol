// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "forge-std/console2.sol";

import {AmmDeployBase} from "./AmmDeployBase.s.sol";
import {SovereignPool} from "../src/SovereignPool.sol";

/// @notice Fee-stack-only upgrade path: deploy new fee contracts and rewire `pool.setSwapFeeModule(...)`
///         without redeploying vault/pool/ALM.
///
/// Required env:
/// - EXISTING_POOL (for runPrimary)
/// - EXISTING_POOL_WETH (for runWeth)
/// - plus regular fee/env knobs from deploy/testnet.env.example
contract UpgradeFeeModule is AmmDeployBase {
    error SwapFeeModuleTimelocked(uint256 unlockAt, uint256 nowTs);

    function runPrimary() external {
        Params memory p = _loadPurrParams();
        address poolAddr = vm.envAddress("EXISTING_POOL");
        _upgradePoolFeeStack(poolAddr, p, "USDC/PURR");
    }

    function runWeth() external {
        Params memory p = _loadWethOnly();
        address poolAddr = vm.envAddress("EXISTING_POOL_WETH");
        _upgradePoolFeeStack(poolAddr, p, "USDC/WETH");
    }

    function _upgradePoolFeeStack(address poolAddr, Params memory p, string memory label) internal {
        require(poolAddr != address(0), "POOL_0");
        address strategist_ = vm.envOr("STRATEGIST", p.deployer);
        SovereignPool pool = SovereignPool(poolAddr);
        uint256 unlockAt = pool.swapFeeModuleUpdateTimestamp();
        if (block.timestamp < unlockAt) {
            revert SwapFeeModuleTimelocked(unlockAt, block.timestamp);
        }

        console2.log("========== Fee Module Upgrade ==========");
        console2.log("Market:", label);
        console2.log("Pool:", poolAddr);
        console2.log("Deployer:", p.deployer);
        console2.log("Strategist/Fee owner:", strategist_);
        console2.log("swapFeeModule timelock passed at:", unlockAt);

        vm.startBroadcast(p.pk);
        (address feeAddr, address surplusAddr, address riskAddr) = _deployFeeStack(p, pool, strategist_);
        pool.setSwapFeeModule(feeAddr);
        vm.stopBroadcast();

        console2.log("New swapFeeModule:", feeAddr);
        if (surplusAddr != address(0)) {
            console2.log("New FeeSurplus:", surplusAddr);
            console2.log("New DeltaFlowRiskEngine:", riskAddr);
        }
        console2.log("Remember to update frontend/backend envs for fee/risk addresses.");
    }
}

