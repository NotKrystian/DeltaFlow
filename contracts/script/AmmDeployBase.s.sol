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

import {DeltaFlowRiskPolicy} from "../src/deltaflow/DeltaFlowTypes.sol";
import {DeltaFlowFeeMath} from "../src/deltaflow/DeltaFlowFeeMath.sol";
import {DeltaFlowRiskEngine} from "../src/deltaflow/DeltaFlowRiskEngine.sol";
import {DeltaFlowCompositeFeeModule} from "../src/deltaflow/DeltaFlowCompositeFeeModule.sol";
import {FeeSurplus} from "../src/deltaflow/FeeSurplus.sol";

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
        bool usePerpPriceForQuote;
        uint256 baseFeeBips;
        uint256 minFeeBips;
        uint256 maxFeeBips;
        uint256 liquidityBufferBps;
        bool skipHlAgent;
        /// @dev DeltaFlow composite fee: `type(uint32).max` skips perp reads.
        uint32 dfPerpIndex;
        /// @dev BBO asset id for spread check; 0 = `10000 + spotIndex`.
        uint32 dfSpotAssetBbo;
        uint256 dfCapacityWad;
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
        p.usePerpPriceForQuote = vm.envOr("USE_PERP_PRICE_FOR_QUOTE_PURR", false);

        p.dfPerpIndex = uint32(vm.envOr("PERP_INDEX_PURR", uint256(type(uint32).max)));
        p.dfSpotAssetBbo = uint32(vm.envOr("SPOT_ASSET_BBO_PURR", uint256(0)));
        p.dfCapacityWad = vm.envOr("CAPACITY_WAD_PURR", uint256(1_000 ether));

        _validateParams(p);
    }

    function _loadWethParams(Params memory common) internal view returns (Params memory w) {
        w = common;
        w.purr = vm.envAddress("WETH");
        w.spotIndexPURR = uint64(vm.envUint("SPOT_INDEX_WETH"));
        w.rawIsPurrPerUsdc = vm.envBool("INVERT_WETH_PX");
        w.rawPxScale = vm.envOr("RAW_PX_SCALE_WETH", common.rawPxScale);
        w.usePerpPriceForQuote = vm.envOr("USE_PERP_PRICE_FOR_QUOTE_WETH", false);

        w.dfPerpIndex = uint32(vm.envOr("PERP_INDEX_WETH", uint256(type(uint32).max)));
        w.dfSpotAssetBbo = uint32(vm.envOr("SPOT_ASSET_BBO_WETH", uint256(0)));
        w.dfCapacityWad = vm.envOr("CAPACITY_WAD_WETH", common.dfCapacityWad);

        _validateParams(w);
    }

    function _loadWethOnly() internal view returns (Params memory p) {
        p = _loadCommon();
        p.purr = vm.envAddress("WETH");
        p.spotIndexPURR = uint64(vm.envUint("SPOT_INDEX_WETH"));
        p.rawIsPurrPerUsdc = vm.envBool("INVERT_WETH_PX");
        p.rawPxScale = vm.envOr("RAW_PX_SCALE_WETH", vm.envOr("RAW_PX_SCALE", uint256(100_000_000)));
        p.usePerpPriceForQuote = vm.envOr("USE_PERP_PRICE_FOR_QUOTE_WETH", false);

        p.dfPerpIndex = uint32(vm.envOr("PERP_INDEX_WETH", uint256(type(uint32).max)));
        p.dfSpotAssetBbo = uint32(vm.envOr("SPOT_ASSET_BBO_WETH", uint256(0)));
        p.dfCapacityWad = vm.envOr("CAPACITY_WAD_WETH", uint256(1_000 ether));

        _validateParams(p);
    }

    function _riskPolicyFromEnv() internal view returns (DeltaFlowRiskPolicy memory pol) {
        bool useMarketRisk = vm.envOr("DF_USE_MARKET_RISK_COMPONENT", false);
        pol.capacityWad = vm.envOr("DF_POLICY_CAPACITY_WAD", uint256(0));
        pol.navSoftWad = vm.envOr("DF_NAV_SOFT_WAD", uint256(0));
        pol.navWarnWad = vm.envOr("DF_NAV_WARN_WAD", uint256(0));
        pol.navHardWad = vm.envOr("DF_NAV_HARD_WAD", uint256(0));
        pol.maxShortfallWad = vm.envOr("DF_MAX_SHORTFALL_WAD", type(uint256).max);
        pol.maxSpreadBps = useMarketRisk ? vm.envOr("DF_MAX_SPREAD_BPS", uint256(500)) : 0;
        pol.minSurplusUsdcNewRisk = vm.envOr("DF_MIN_SURPLUS_USDC_NEW_RISK", uint256(0));
        pol.rawFeeRejectBps = vm.envOr("DF_RAW_FEE_REJECT_BPS", uint256(80));
        pol.displayedFeeCapBps = vm.envOr("DF_DISPLAYED_FEE_CAP_BPS", uint256(60));
        pol.requirePositiveSurplusTrend = vm.envOr("DF_REQUIRE_SURPLUS_TREND", false);
    }

    function _feeParamsFromEnv() internal view returns (DeltaFlowFeeMath.FeeParams memory fp) {
        fp.execPerpBps = vm.envOr("DF_EXEC_PERP_BPS", uint256(4));
        fp.execSpotShortfallBps = vm.envOr("DF_EXEC_SPOT_SHORTFALL_BPS", uint256(7));
        fp.delayNormalBps = vm.envOr("DF_DELAY_NORMAL_BPS", uint256(2));
        fp.delayStressedBps = vm.envOr("DF_DELAY_STRESSED_BPS", uint256(5));
        fp.basisMaxBps = vm.envOr("DF_BASIS_MAX_BPS", uint256(5));
        fp.fundingCapBps = vm.envOr("DF_FUNDING_CAP_BPS", uint256(8));
        fp.invKappaWad = vm.envOr("DF_INV_KAPPA_WAD", uint256(24e17));
        fp.exhaustLinearWad = vm.envOr("DF_EXHAUST_LINEAR_WAD", uint256(12e18));
        fp.exhaustQuadWad = vm.envOr("DF_EXHAUST_QUAD_WAD", uint256(80e18));
        fp.safetyBaseBps = vm.envOr("DF_SAFETY_BASE_BPS", uint256(2));
        fp.delayStressed = vm.envOr("DF_DELAY_STRESSED", false);
        fp.perpDepthWad = vm.envOr("DF_PERP_DEPTH_WAD", uint256(1_500_000 ether));
        fp.impactCoeff = vm.envOr("DF_IMPACT_COEFF", uint256(12));
        fp.hMaxSz = vm.envOr("DF_H_MAX_SZ", uint256(200_000));
        fp.poolNavWad = vm.envOr("DF_POOL_NAV_WAD", uint256(0));
    }

    function _deployPool(Params memory p, address vaultAddr) internal returns (SovereignPool pool) {
        require(p.dfPerpIndex != type(uint32).max, "PERP_INDEX_REQUIRED_FOR_VAULT_POOL");
        SovereignPoolConstructorArgs memory args = SovereignPoolConstructorArgs({
            token0: p.purr,
            token1: p.usdc,
            sovereignVault: vaultAddr,
            protocolFactory: p.protocolFactory,
            poolManager: p.poolManager,
            verifierModule: p.verifierModule,
            defaultSwapFeeBips: p.defaultSwapFeeBips,
            swapFeeModuleUpdateDelay: vm.envOr("SWAP_FEE_MODULE_TIMELOCK_SEC", uint256(0)),
            isToken0Rebase: false,
            isToken1Rebase: false,
            token0AbsErrorTolerance: 0,
            token1AbsErrorTolerance: 0,
            hedgePerpAssetIndex: p.dfPerpIndex
        });

        pool = new SovereignPool(args);
    }

    function _deployFeeModuleV3(Params memory p, SovereignPool pool)
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

    /// @dev If `DEPLOY_DELTAFLOW_FEE` is true (default), deploys FeeSurplus + RiskEngine + Composite fee module.
    function _deployFeeStack(Params memory p, SovereignPool pool, address strategist)
        internal
        returns (address feeModule, address surplus, address riskEngine)
    {
        bool deployDf = vm.envOr("DEPLOY_DELTAFLOW_FEE", true);
        if (!deployDf) {
            BalanceSeekingSwapFeeModuleV3 v3 = _deployFeeModuleV3(p, pool);
            return (address(v3), address(0), address(0));
        }

        FeeSurplus fs = new FeeSurplus(p.usdc, strategist);
        DeltaFlowRiskPolicy memory pol = _riskPolicyFromEnv();
        DeltaFlowRiskEngine risk = new DeltaFlowRiskEngine(
            pol,
            fs,
            vm.envOr("DF_REQUIRE_SURPLUS_NEW_RISK", false),
            strategist
        );

        DeltaFlowFeeMath.FeeParams memory fp = _feeParamsFromEnv();
        uint32 spotBbo = p.dfSpotAssetBbo;
        if (spotBbo == 0) {
            spotBbo = uint32(uint256(10000) + uint256(p.spotIndexPURR));
        }

        DeltaFlowCompositeFeeModule comp = new DeltaFlowCompositeFeeModule(
            address(pool),
            p.usdc,
            p.purr,
            p.spotIndexPURR,
            p.rawPxScale,
            p.rawIsPurrPerUsdc,
            p.dfPerpIndex,
            spotBbo,
            p.dfCapacityWad,
            risk,
            fs,
            vm.envOr("SURPLUS_FRACTION_BPS", uint256(1000)),
            fp,
            vm.envOr("VOLATILE_REGIME", false),
            vm.envOr("DF_USE_MARKET_RISK_COMPONENT", false)
        );

        fs.setPool(address(pool));
        // Composite calls `accrueFromPool` (msg.sender = fee module), not SovereignPool directly.
        fs.setSwapFeeModule(address(comp));

        return (address(comp), address(fs), address(risk));
    }

    /// @dev First on-chain tx of a stack: deploy SovereignVault only (use alone with `--slow` if RPC nonce is flaky).
    function _deployVaultOnly(Params memory p) internal returns (SovereignVault vault) {
        vault = new SovereignVault(p.usdc, p.purr);
        console2.log("SovereignVault:", address(vault));
    }

    /// @notice Completes one market stack after `SovereignVault` exists (approve agent, pool, ALM, fee, HedgeEscrow, …).
    function _finishStackAfterVault(Params memory p, SovereignVault vault, string memory label, bool isWethStack) internal {
        console2.log("==========", label, "==========");
        console2.log("Base token:", p.purr);
        console2.log("USDC:", p.usdc);
        console2.log("Spot index:", p.spotIndexPURR);
        console2.log("RAW_PX_SCALE:", p.rawPxScale);
        console2.log("ALM uses perp mark quote:", p.usePerpPriceForQuote);
        if (p.usePerpPriceForQuote) {
            console2.log("ALM perp index:", p.dfPerpIndex);
        }
        console2.log("SovereignVault (existing):", address(vault));

        address strategist = vm.envOr("STRATEGIST", p.deployer);

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
            p.usePerpPriceForQuote,
            p.dfPerpIndex,
            p.liquidityBufferBps
        );
        console2.log("SovereignALM:", address(alm));

        (address feeAddr, address surplusAddr, address riskAddr) = _deployFeeStack(p, pool, strategist);

        if (vm.envOr("DEPLOY_DELTAFLOW_FEE", true)) {
            console2.log("FeeSurplus:", surplusAddr);
            console2.log("DeltaFlowRiskEngine:", riskAddr);
            console2.log("DeltaFlowCompositeFeeModule:", feeAddr);
        } else {
            console2.log("SwapFeeModuleV3 (balance-seeking):", feeAddr);
        }

        pool.setALM(address(alm));
        pool.setSwapFeeModule(feeAddr);

        vault.setALM(address(alm));

        if (p.dfPerpIndex != type(uint32).max) {
            vault.setHedgePerpAsset(p.dfPerpIndex);
            console2.log("HEDGE_PERP_ASSET_INDEX (swap hedge):", p.dfPerpIndex);
            bool useMarkMin = vm.envOr("USE_MARK_MIN_HEDGE_SZ", true);
            vault.setUseMarkBasedMinHedgeSz(useMarkMin);
            console2.log("USE_MARK_MIN_HEDGE_SZ (mark $10 notional threshold):", useMarkMin);
            uint64 floorSz = uint64(vm.envOr("MIN_PERP_HEDGE_SZ_FLOOR", uint256(0)));
            if (floorSz > 0) {
                vault.setMinPerpHedgeSz(floorSz);
                console2.log("MIN_PERP_HEDGE_SZ_FLOOR (optional sz floor):", floorSz);
            }
        }

        // HedgeEscrow args: Core token index comes from the on-chain registry via `getTokenIndex` (works
        // under forge fork). Spot *universe* index must match `PrecompileLib.getSpotIndex` on-chain, but
        // that path calls token info precompile `0x…080C`, which Foundry’s fork does not execute — calls
        // revert with “non-contract address”. Use the same value from env (`SPOT_INDEX_PURR` / `SPOT_INDEX_WETH`
        // → `p.spotIndexPURR`) that you verified via spotMeta / ReadSpotIndex.
        uint64 baseTi = PrecompileLib.getTokenIndex(p.purr);
        uint64 spotIdx = p.spotIndexPURR;
        uint32 spotAsset = uint32(uint256(10000) + uint256(spotIdx));
        HedgeEscrow he = new HedgeEscrow(p.usdc, p.purr, spotAsset, baseTi);
        console2.log("HedgeEscrow:", address(he));

        console2.log("--- addresses (copy to backend .env) ---");
        console2.log("SOVEREIGN_VAULT=", address(vault));
        console2.log("WATCH_POOL=", address(pool));
        console2.log("SOVEREIGN_ALM=", address(alm));
        console2.log("SWAP_FEE_MODULE=", feeAddr);
        if (surplusAddr != address(0)) {
            console2.log("FEE_SURPLUS=", surplusAddr);
            console2.log("DELTAFLOW_RISK_ENGINE=", riskAddr);
        }
        console2.log("HEDGE_ESCROW=", address(he));
        console2.log("PURR_TOKEN_INDEX=", baseTi);
        console2.log("SPOT_ASSET_INDEX (10000+spotIdx)=", spotAsset);
        console2.log("SPOT_INDEX (universe)=", spotIdx);

        console2.log("--- frontend .env (NEXT_PUBLIC_*, Hyperliquid testnet chain 998) ---");
        if (!isWethStack) {
            console2.log("NEXT_PUBLIC_POOL=", vm.toString(address(pool)));
            console2.log("NEXT_PUBLIC_VAULT=", vm.toString(address(vault)));
            console2.log("NEXT_PUBLIC_ALM=", vm.toString(address(alm)));
            console2.log("NEXT_PUBLIC_SWAP_FEE_MODULE=", vm.toString(feeAddr));
            console2.log("NEXT_PUBLIC_HEDGE_ESCROW=", vm.toString(address(he)));
            console2.log("NEXT_PUBLIC_USDC=", vm.toString(p.usdc));
            console2.log("NEXT_PUBLIC_PURR=", vm.toString(p.purr));
            if (surplusAddr != address(0)) {
                console2.log("NEXT_PUBLIC_FEE_SURPLUS=", vm.toString(surplusAddr));
                console2.log("NEXT_PUBLIC_DELTAFLOW_RISK_ENGINE=", vm.toString(riskAddr));
            }
        } else {
            console2.log("NEXT_PUBLIC_POOL_WETH=", vm.toString(address(pool)));
            console2.log("NEXT_PUBLIC_VAULT_WETH=", vm.toString(address(vault)));
            console2.log("NEXT_PUBLIC_ALM_WETH=", vm.toString(address(alm)));
            console2.log("NEXT_PUBLIC_SWAP_FEE_MODULE_WETH=", vm.toString(feeAddr));
            console2.log("NEXT_PUBLIC_HEDGE_ESCROW_WETH=", vm.toString(address(he)));
            console2.log("NEXT_PUBLIC_WETH=", vm.toString(p.purr));
            if (surplusAddr != address(0)) {
                console2.log("NEXT_PUBLIC_FEE_SURPLUS_WETH=", vm.toString(surplusAddr));
                console2.log("NEXT_PUBLIC_DELTAFLOW_RISK_ENGINE_WETH=", vm.toString(riskAddr));
            }
        }
    }

    /// @notice Deploys one full market stack including **HedgeEscrow** (core liquidity / hedge surface via CoreWriter).
    function _deployOneStack(Params memory p, string memory label, bool isWethStack) internal {
        SovereignVault vault = _deployVaultOnly(p);
        _finishStackAfterVault(p, vault, label, isWethStack);
    }
}
