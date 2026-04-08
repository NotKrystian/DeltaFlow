// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "forge-std/console2.sol";

import {SovereignPool} from "../src/SovereignPool.sol";
import {SovereignALM} from "../src/SovereignALM.sol";
import {SovereignVault} from "../src/SovereignVault.sol";
import {SovereignPoolConstructorArgs} from "../src/structs/SovereignPoolStructs.sol";

import {BalanceSeekingSwapFeeModuleV3} from "../src/SwapFeeModuleV3.sol";
import {PrecompileLib} from "@hyper-evm-lib/src/PrecompileLib.sol";
import {HedgeEscrow} from "../src/HedgeEscrow.sol";

interface ISovereignVaultAgentApprover {
    function approveAgent(address agent, string calldata name) external;
}

/// @dev Shared params + deploy sequence for one USDC/base market (base = PURR, WETH, …).
abstract contract AmmDeployBase is Script {
    struct Params {
        uint256 pk;
        address deployer;
        uint256 hlAgentPk;
        address hlAgentAddr;
        string hlAgentName;
        address purr;
        address usdc;
        address protocolFactory;
        address verifierModule;
        address poolManager;
        uint256 defaultSwapFeeBips;
        uint64 spotIndexPURR;
        uint256 rawPxScale;
        bool rawIsPurrPerUsdc;
        uint256 baseFeeBips;
        uint256 minFeeBips;
        uint256 maxFeeBips;
        uint256 liquidityBufferBps;
        bool skipHlAgent;
    }

    function _loadCommon() internal view returns (Params memory p) {
        p.pk = vm.envUint("PRIVATE_KEY");
        p.deployer = vm.addr(p.pk);

        p.hlAgentName = vm.envOr("HL_AGENT_NAME", string("hedge-bot"));

        p.usdc = vm.envAddress("USDC");

        p.protocolFactory = vm.envOr("PROTOCOL_FACTORY", address(0));
        p.verifierModule = vm.envOr("VERIFIER_MODULE", address(0));

        p.poolManager = vm.envAddress("POOL_MANAGER");
        p.defaultSwapFeeBips = vm.envUint("DEFAULT_SWAP_FEE_BIPS");

        p.baseFeeBips = vm.envUint("BASE_FEE_BIPS");
        p.minFeeBips = vm.envUint("MIN_FEE_BIPS");
        p.maxFeeBips = vm.envUint("MAX_FEE_BIPS");

        p.liquidityBufferBps = vm.envUint("LIQUIDITY_BUFFER_BPS");

        p.skipHlAgent = vm.envOr("SKIP_HL_AGENT", false);
        if (!p.skipHlAgent) {
            p.hlAgentPk = vm.envUint("HL_AGENT_PRIVATE_KEY");
            p.hlAgentAddr = vm.addr(p.hlAgentPk);
        } else {
            p.hlAgentPk = 0;
            p.hlAgentAddr = address(0);
        }
    }

    function _validateParams(Params memory p) internal pure {
        require(p.purr != address(0) && p.usdc != address(0), "TOKENS_0");
        require(p.poolManager != address(0), "PM_0");
        require(p.defaultSwapFeeBips <= 10_000, "SWAP_FEE_TOO_HIGH");

        require(p.minFeeBips <= p.baseFeeBips, "MIN_GT_BASE");
        require(p.baseFeeBips <= p.maxFeeBips, "BASE_GT_MAX");
        require(p.maxFeeBips <= 10_000, "MAX_GT_100PCT");

        if (!p.skipHlAgent) {
            require(p.hlAgentAddr != address(0), "HL_AGENT_0");
        }
        require(p.liquidityBufferBps <= 5_000, "BUF_TOO_HIGH");
        require(p.rawPxScale > 0, "RAW_PX_SCALE_0");
    }

    function _loadPurrParams() internal view returns (Params memory p) {
        p = _loadCommon();
        p.purr = vm.envAddress("PURR");
        p.spotIndexPURR = uint64(vm.envUint("SPOT_INDEX_PURR"));
        p.rawIsPurrPerUsdc = vm.envBool("INVERT_PURR_PX");
        p.rawPxScale = vm.envOr("RAW_PX_SCALE", uint256(100_000_000));
        _validateParams(p);
    }

    /// @dev Second stack in `DeployAll` when `DEPLOY_USDC_WETH=true`; reuses fee/pool env from `common`.
    function _loadWethParams(Params memory common) internal view returns (Params memory w) {
        w = common;
        w.purr = vm.envAddress("WETH");
        w.spotIndexPURR = uint64(vm.envUint("SPOT_INDEX_WETH"));
        w.rawIsPurrPerUsdc = vm.envBool("INVERT_WETH_PX");
        w.rawPxScale = vm.envOr("RAW_PX_SCALE_WETH", common.rawPxScale);
        _validateParams(w);
    }

    /// @dev Standalone WETH deploy: same common env as DeployAll, pair from `WETH` / `SPOT_INDEX_WETH` / `INVERT_WETH_PX`.
    function _loadWethOnly() internal view returns (Params memory p) {
        p = _loadCommon();
        p.purr = vm.envAddress("WETH");
        p.spotIndexPURR = uint64(vm.envUint("SPOT_INDEX_WETH"));
        p.rawIsPurrPerUsdc = vm.envBool("INVERT_WETH_PX");
        p.rawPxScale = vm.envOr("RAW_PX_SCALE_WETH", vm.envOr("RAW_PX_SCALE", uint256(100_000_000)));
        _validateParams(p);
    }

    function _deployPool(Params memory p, address vaultAddr) internal returns (SovereignPool pool) {
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
        feeModule = new BalanceSeekingSwapFeeModuleV3(
            address(pool),
            p.usdc,
            p.purr,
            p.spotIndexPURR,
            p.rawPxScale,
            p.rawIsPurrPerUsdc,
            p.baseFeeBips,
            p.minFeeBips,
            p.maxFeeBips,
            p.liquidityBufferBps
        );
    }

    function _deployOneStack(Params memory p, bool deployHedge, string memory label) internal {
        console2.log("==========", label, "==========");
        console2.log("Base token:", p.purr);
        console2.log("USDC:", p.usdc);
        console2.log("Spot index:", p.spotIndexPURR);
        console2.log("RAW_PX_SCALE:", p.rawPxScale);

        SovereignVault vault = new SovereignVault(p.usdc, p.purr);
        console2.log("SovereignVault:", address(vault));

        if (!p.skipHlAgent) {
            ISovereignVaultAgentApprover(address(vault)).approveAgent(p.hlAgentAddr, p.hlAgentName);
            console2.log("Vault approved HL agent:", p.hlAgentAddr);
        } else {
            console2.log("SKIP_HL_AGENT=true: approveAgent skipped");
        }

        SovereignPool pool = _deployPool(p, address(vault));
        console2.log("SovereignPool:", address(pool));

        vault.setAuthorizedPool(address(pool), true);

        SovereignALM alm = new SovereignALM(
            address(pool),
            p.usdc,
            p.purr,
            p.spotIndexPURR,
            p.rawPxScale,
            p.rawIsPurrPerUsdc,
            p.liquidityBufferBps
        );
        console2.log("SovereignALM:", address(alm));

        BalanceSeekingSwapFeeModuleV3 feeModule = _deployFeeModule(p, pool);
        console2.log("SwapFeeModuleV3:", address(feeModule));

        pool.setALM(address(alm));
        pool.setSwapFeeModule(address(feeModule));

        vault.setALM(address(alm));

        console2.log("--- addresses ---");
        console2.log("SOVEREIGN_VAULT_ADDRESS=", address(vault));
        console2.log("WATCH_POOL=", address(pool));
        console2.log("SOVEREIGN_ALM=", address(alm));
        console2.log("SWAP_FEE_MODULE=", address(feeModule));

        if (deployHedge) {
            uint64 baseTi = PrecompileLib.getTokenIndex(p.purr);
            uint64 spotIdx = PrecompileLib.getSpotIndex(p.purr);
            uint32 spotAsset = uint32(uint256(10000) + uint256(spotIdx));
            HedgeEscrow he = new HedgeEscrow(p.usdc, p.purr, spotAsset, baseTi);
            console2.log("HedgeEscrow:", address(he));
            console2.log("HEDGE_ESCROW=", address(he));
            console2.log("BASE_TOKEN_INDEX (backend PURR_TOKEN_INDEX)=", baseTi);
            console2.log("SPOT_ASSET_INDEX=", spotAsset);
        }
    }
}
