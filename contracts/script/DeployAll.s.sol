// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "forge-std/console2.sol";

import {AmmDeployBase} from "./AmmDeployBase.s.sol";
import {SovereignVault} from "../src/SovereignVault.sol";

contract DeployAll is AmmDeployBase {
    /// @dev First on-chain tx only: deploy USDC/PURR `SovereignVault`. The deploy shell runs this with `--slow`, then `runAfterFirstTx()`.
    function bootstrapFirstTx() external {
        Params memory p = _loadPurrParams();

        console2.log("ChainId:", block.chainid);
        console2.log("DeployAll: bootstrapFirstTx (SovereignVault only)");
        console2.log("Deployer:", p.deployer);

        vm.startBroadcast(p.pk);
        _deployVaultOnly(p);
        vm.stopBroadcast();

        console2.log("--- Next: runAfterFirstTx() with SOVEREIGN_VAULT_BOOTSTRAP=<vault above> ---");
    }

    /// @dev Completes USDC/PURR stack (and optional USDC/WETH) using vault from `bootstrapFirstTx`. Requires `SOVEREIGN_VAULT_BOOTSTRAP`.
    function runAfterFirstTx() external {
        Params memory p = _loadPurrParams();
        address bootstrapVault = vm.envOr("SOVEREIGN_VAULT_BOOTSTRAP", address(0));
        require(bootstrapVault != address(0), "SOVEREIGN_VAULT_BOOTSTRAP");
        bool wethToo = vm.envOr("DEPLOY_USDC_WETH", false);

        console2.log("ChainId:", block.chainid);
        console2.log("DeployAll: runAfterFirstTx");
        console2.log("Deployer:", p.deployer);
        console2.log("SOVEREIGN_VAULT_BOOTSTRAP:", bootstrapVault);

        vm.startBroadcast(p.pk);
        _finishStackAfterVault(p, SovereignVault(bootstrapVault), "USDC/PURR", false);

        if (wethToo) {
            Params memory w = _loadWethParams(p);
            _deployOneStack(w, "USDC/WETH", true);
        }

        vm.stopBroadcast();

        console2.log("--- post-deploy: sync env files (addresses) ---");
        console2.log(
            "python3 scripts/sync_env_from_broadcast.py --broadcast-json .../run-bootstrap.json --broadcast-json .../run-latest.json"
        );
    }

    /// @dev Full deploy in one broadcast (big blocks for all heavy CREATE txs — slow block time throughout).
    function run() external {
        Params memory p = _loadPurrParams();
        bool wethToo = vm.envOr("DEPLOY_USDC_WETH", false);

        console2.log("ChainId:", block.chainid);
        console2.log("Deployer:", p.deployer);
        console2.log("PoolManager:", p.poolManager);
        console2.log("HL Agent:", p.hlAgentAddr);

        vm.startBroadcast(p.pk);

        _deployOneStack(p, "USDC/PURR", false);

        if (wethToo) {
            Params memory w = _loadWethParams(p);
            _deployOneStack(w, "USDC/WETH", true);
        }

        vm.stopBroadcast();

        console2.log("--- post-deploy: sync env files (addresses) ---");
        console2.log("python3 scripts/sync_env_from_broadcast.py   # merges broadcast/.../run-latest.json into frontend/.env.local + backend/.env");
    }

    /// @dev Phase 1 only — USDC/PURR. Use when pausing between stacks to switch wallet from big blocks to small blocks.
    function runStackPurr() external {
        Params memory p = _loadPurrParams();

        console2.log("ChainId:", block.chainid);
        console2.log("DeployAll phase: runStackPurr (USDC/PURR only)");
        console2.log("Deployer:", p.deployer);

        vm.startBroadcast(p.pk);
        address bootstrapVault = vm.envOr("SOVEREIGN_VAULT_BOOTSTRAP", address(0));
        if (bootstrapVault != address(0)) {
            _finishStackAfterVault(p, SovereignVault(bootstrapVault), "USDC/PURR", false);
        } else {
            _deployOneStack(p, "USDC/PURR", false);
        }
        vm.stopBroadcast();

        console2.log("--- Next: switch deployer to SMALL blocks, then run runStackWeth() or deploy_all_testnet.sh phase 2 ---");
    }

    /// @dev Phase 2 only — USDC/WETH. Run after `runStackPurr` with small blocks (and DEPLOY_USDC_WETH=true in env).
    function runStackWeth() external {
        require(vm.envOr("DEPLOY_USDC_WETH", false), "DEPLOY_USDC_WETH must be true for runStackWeth");

        Params memory p = _loadPurrParams();
        Params memory w = _loadWethParams(p);

        console2.log("ChainId:", block.chainid);
        console2.log("DeployAll phase: runStackWeth (USDC/WETH only)");
        console2.log("Deployer:", p.deployer);

        vm.startBroadcast(p.pk);
        _deployOneStack(w, "USDC/WETH", true);
        vm.stopBroadcast();
    }
}
