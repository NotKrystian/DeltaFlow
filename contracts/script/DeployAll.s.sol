// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "forge-std/console2.sol";

import {SovereignPool} from "../src/SovereignPool.sol";
import {SovereignALM} from "../src/SovereignALM.sol";
import {SovereignVault} from "../src/SovereignVault.sol";
import {SovereignPoolConstructorArgs} from "../src/structs/SovereignPoolStructs.sol";

// IMPORTANT: update path + name to match your repo
import {BalanceSeekingSwapFeeModuleV3} from "../src/SwapFeeModuleV3.sol";

interface ISovereignVaultAgentApprover {
    function approveAgent(address agent, string calldata name) external;
}

contract DeployAll is Script {
    struct Params {
        uint256 pk;
        address deployer;

        // HL agent wallet private key (python server / API wallet)
        uint256 hlAgentPk;
        address hlAgentAddr;
        string hlAgentName;

        address purr;
        address usdc;

        // optional / can be 0
        address protocolFactory;
        address verifierModule;

        address poolManager;
        uint256 defaultSwapFeeBips;

        // fee module specifics
        uint64 spotIndexPURR;
        bool invertPurrPx;

        uint256 baseFeeBips;
        uint256 minFeeBips;
        uint256 maxFeeBips;

        // liquidity sanity buffer (bps). e.g. 50 = 0.50%
        uint256 liquidityBufferBps;
    }

    function run() external {
        Params memory p = _load();

        console2.log("ChainId:", block.chainid);
        console2.log("Deployer:", p.deployer);
        console2.log("PoolManager:", p.poolManager);
        console2.log("PURR:", p.purr);
        console2.log("USDC:", p.usdc);
        console2.log("HL Agent:", p.hlAgentAddr);

        vm.startBroadcast(p.pk);

        // 0) ALWAYS deploy a fresh vault
        SovereignVault vault = new SovereignVault(p.usdc, p.purr);
        console2.log("Deployed SovereignVault:", address(vault));

        // 0.1) Approve HL agent wallet to trade the VAULT's Core balances
        ISovereignVaultAgentApprover(address(vault)).approveAgent(
            p.hlAgentAddr,
            p.hlAgentName
        );
        console2.log("Vault approved HL agent:", p.hlAgentAddr);

        // 1) Deploy pool in external-vault mode
        SovereignPool pool = _deployPool(p, address(vault));
        console2.log("Deployed SovereignPool:", address(pool));

        // 2) Authorize pool on vault ASAP
        vault.setAuthorizedPool(address(pool), true);
        console2.log("Vault authorized pool");

        // 3) Deploy ALM
        SovereignALM alm = new SovereignALM(
            address(pool),
            p.usdc,
            p.purr,
            p.spotIndexPURR,
            p.invertPurrPx,
            p.liquidityBufferBps
        );
        console2.log("Deployed SovereignALM:", address(alm));

        // 4) Deploy fee module (V3 = 9 args)
        BalanceSeekingSwapFeeModuleV3 feeModule = _deployFeeModule(p, pool);
        console2.log("Deployed SwapFeeModuleV3:", address(feeModule));

        // 5) Wire pool -> modules
        pool.setALM(address(alm));
        pool.setSwapFeeModule(address(feeModule));

        vm.stopBroadcast();

        console2.log("=== FINAL ADDRS ===");
        console2.log("SOVEREIGN_VAULT_ADDRESS=", address(vault));
        console2.log("WATCH_POOL=", address(pool));
        console2.log("SOVEREIGN_ALM=", address(alm));
        console2.log("SWAP_FEE_MODULE=", address(feeModule));
        console2.log("HL_ACCOUNT_ADDRESS (vault) =", address(vault));
        console2.log("HL_AGENT_ADDRESS =", p.hlAgentAddr);
    }

    function _load() internal view returns (Params memory p) {
        // EVM deployer
        p.pk = vm.envUint("PRIVATE_KEY");
        p.deployer = vm.addr(p.pk);

        // HL agent wallet private key
        p.hlAgentPk = vm.envUint("HL_AGENT_PRIVATE_KEY");
        p.hlAgentAddr = vm.addr(p.hlAgentPk);
        p.hlAgentName = vm.envOr("HL_AGENT_NAME", string("hedge-bot"));

        // tokens
        p.purr = vm.envAddress("PURR");
        p.usdc = vm.envAddress("USDC");

        // optional / can be 0
        p.protocolFactory = vm.envOr("PROTOCOL_FACTORY", address(0));
        p.verifierModule = vm.envOr("VERIFIER_MODULE", address(0));

        // pool config
        p.poolManager = vm.envAddress("POOL_MANAGER");
        p.defaultSwapFeeBips = vm.envUint("DEFAULT_SWAP_FEE_BIPS");

        // fee module config
        p.spotIndexPURR = uint64(vm.envUint("SPOT_INDEX_PURR"));
        p.invertPurrPx = vm.envBool("INVERT_PURR_PX");

        p.baseFeeBips = vm.envUint("BASE_FEE_BIPS");
        p.minFeeBips = vm.envUint("MIN_FEE_BIPS");
        p.maxFeeBips = vm.envUint("MAX_FEE_BIPS");

        p.liquidityBufferBps = vm.envUint("LIQUIDITY_BUFFER_BPS");

        // sanity
        require(p.purr != address(0) && p.usdc != address(0), "TOKENS_0");
        require(p.poolManager != address(0), "PM_0");
        require(p.defaultSwapFeeBips <= 10_000, "SWAP_FEE_TOO_HIGH");

        require(p.minFeeBips <= p.baseFeeBips, "MIN_GT_BASE");
        require(p.baseFeeBips <= p.maxFeeBips, "BASE_GT_MAX");
        require(p.maxFeeBips <= 10_000, "MAX_GT_100PCT");

        require(p.hlAgentAddr != address(0), "HL_AGENT_0");
        require(p.liquidityBufferBps <= 5_000, "BUF_TOO_HIGH");
    }

    function _deployPool(Params memory p, address vaultAddr)
        internal
        returns (SovereignPool pool)
    {
        SovereignPoolConstructorArgs memory args = SovereignPoolConstructorArgs({
            token0: p.purr,
            token1: p.usdc,
            sovereignVault: vaultAddr,
            protocolFactory: p.protocolFactory,
            poolManager: p.poolManager,
            verifierModule: p.verifierModule,
            defaultSwapFeeBips: p.defaultSwapFeeBips,
            isToken0Rebase: false,
            isToken1Rebase: false,
            token0AbsErrorTolerance: 0,
            token1AbsErrorTolerance: 0
        });

        pool = new SovereignPool(args);
    }

    function _deployFeeModule(Params memory p, SovereignPool pool)
        internal
        returns (BalanceSeekingSwapFeeModuleV3 feeModule)
    {
        // V3 constructor = 9 args:
        // (pool, usdc, purr, spotIndexPURR, invertPurrPx, baseFeeBips, minFeeBips, maxFeeBips, liquidityBufferBps)
        feeModule = new BalanceSeekingSwapFeeModuleV3(
            address(pool),
            p.usdc,
            p.purr,
            p.spotIndexPURR,
            p.invertPurrPx,
            p.baseFeeBips,
            p.minFeeBips,
            p.maxFeeBips,
            p.liquidityBufferBps
        );
    }
}