// ═══════════════════════════════════════════════════════════════════════════
// Sovereign AMM Contract Configuration - Hyperliquid Testnet
// ═══════════════════════════════════════════════════════════════════════════

// Chain ID for Hyperliquid Testnet
export const HYPERLIQUID_TESTNET_CHAIN_ID = 998;

const ZERO = "0x0000000000000000000000000000000000000000" as `0x${string}`;

// Defaults match Hyperliquid testnet; override with NEXT_PUBLIC_* after `forge script DeployAll`.
// See deploy/testnet.env.example and docs/deployment/testnet-asset-ids.md
export const ADDRESSES = {
  POOL: (process.env.NEXT_PUBLIC_POOL ??
    "0x2E5bB169b596b3136C717258b40D6F83Ae5393Fd") as `0x${string}`,
  VAULT: (process.env.NEXT_PUBLIC_VAULT ??
    "0x715EB367788e71C4c6aee4E8994aD407807fec27") as `0x${string}`,
  ALM: (process.env.NEXT_PUBLIC_ALM ??
    "0x773ACA23c3B9E9EB8e7BD27Da3863957B66e9526") as `0x${string}`,

  SWAP_FEE_MODULE: (process.env.NEXT_PUBLIC_SWAP_FEE_MODULE ??
    "0xA0Fa62675a8Db6814510eEF716c67021F249a5d6") as `0x${string}`,

  USDC: (process.env.NEXT_PUBLIC_USDC ??
    "0x2B3370eE501B4a559b57D449569354196457D8Ab") as `0x${string}`,
  PURR: (process.env.NEXT_PUBLIC_PURR ??
    "0xa9056c15938f9aff34CD497c722Ce33dB0C2fD57") as `0x${string}`,
  WETH: (process.env.NEXT_PUBLIC_WETH ??
    "0x5a1A1339ad9e52B7a4dF78452D5c18e8690746f3") as `0x${string}`,

  HLP_VAULT: "0xa15099a30BBf2e68942d6F4c43d70D04FAEab0A0" as const,

  HEDGE_ESCROW: (process.env.NEXT_PUBLIC_HEDGE_ESCROW ?? ZERO) as `0x${string}`,

  /** Second-market HedgeEscrow when `DEPLOY_USDC_WETH=true` (primary UI still uses `HEDGE_ESCROW`) */
  HEDGE_ESCROW_WETH: (process.env.NEXT_PUBLIC_HEDGE_ESCROW_WETH ?? ZERO) as `0x${string}`,

  FEE_SURPLUS: (process.env.NEXT_PUBLIC_FEE_SURPLUS ?? ZERO) as `0x${string}`,
  DELTAFLOW_RISK_ENGINE: (process.env.NEXT_PUBLIC_DELTAFLOW_RISK_ENGINE ?? ZERO) as `0x${string}`,

  /** Optional second stack (USDC/WETH) when `DEPLOY_USDC_WETH=true` — primary UI uses POOL/VAULT/ALM above */
  POOL_WETH: (process.env.NEXT_PUBLIC_POOL_WETH ?? ZERO) as `0x${string}`,
  VAULT_WETH: (process.env.NEXT_PUBLIC_VAULT_WETH ?? ZERO) as `0x${string}`,
  ALM_WETH: (process.env.NEXT_PUBLIC_ALM_WETH ?? ZERO) as `0x${string}`,
  SWAP_FEE_MODULE_WETH: (process.env.NEXT_PUBLIC_SWAP_FEE_MODULE_WETH ?? ZERO) as `0x${string}`,
  FEE_SURPLUS_WETH: (process.env.NEXT_PUBLIC_FEE_SURPLUS_WETH ?? ZERO) as `0x${string}`,
  DELTAFLOW_RISK_ENGINE_WETH: (process.env.NEXT_PUBLIC_DELTAFLOW_RISK_ENGINE_WETH ??
    ZERO) as `0x${string}`,
} as const;

// ═══════════════════════════════════════════════════════════════════════════
// Token Metadata
// ═══════════════════════════════════════════════════════════════════════════
export const TOKENS = {
  PURR: {
    address: ADDRESSES.PURR,
    symbol: "PURR",
    decimals: 5,
    name: "PURR",
  },
  USDC: {
    address: ADDRESSES.USDC,
    symbol: "USDC",
    decimals: 6,
    name: "USD Coin",
  },
} as const;

// ═══════════════════════════════════════════════════════════════════════════
// ABIs
// ═══════════════════════════════════════════════════════════════════════════

// Minimal ERC20 ABI for token interactions
export const ERC20_ABI = [
  {
    name: "balanceOf",
    type: "function",
    stateMutability: "view",
    inputs: [{ name: "account", type: "address" }],
    outputs: [{ name: "", type: "uint256" }],
  },
  {
    name: "allowance",
    type: "function",
    stateMutability: "view",
    inputs: [
      { name: "owner", type: "address" },
      { name: "spender", type: "address" },
    ],
    outputs: [{ name: "", type: "uint256" }],
  },
  {
    name: "approve",
    type: "function",
    stateMutability: "nonpayable",
    inputs: [
      { name: "spender", type: "address" },
      { name: "amount", type: "uint256" },
    ],
    outputs: [{ name: "", type: "bool" }],
  },
  {
    name: "symbol",
    type: "function",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "string" }],
  },
  {
    name: "decimals",
    type: "function",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "uint8" }],
  },
  {
    name: "name",
    type: "function",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "string" }],
  },
  {
    name: "totalSupply",
    type: "function",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "uint256" }],
  },
  {
    name: "transfer",
    type: "function",
    stateMutability: "nonpayable",
    inputs: [
      { name: "to", type: "address" },
      { name: "amount", type: "uint256" },
    ],
    outputs: [{ name: "", type: "bool" }],
  },
] as const;

// SovereignPool ABI - Main swap/AMM contract
export const SOVEREIGN_POOL_ABI = [
  {
    type: "constructor",
    inputs: [
      {
        name: "args",
        type: "tuple",
        internalType: "struct SovereignPoolConstructorArgs",
        components: [
          { name: "token0", type: "address", internalType: "address" },
          { name: "token1", type: "address", internalType: "address" },
          { name: "protocolFactory", type: "address", internalType: "address" },
          { name: "poolManager", type: "address", internalType: "address" },
          { name: "sovereignVault", type: "address", internalType: "address" },
          { name: "verifierModule", type: "address", internalType: "address" },
          { name: "isToken0Rebase", type: "bool", internalType: "bool" },
          { name: "isToken1Rebase", type: "bool", internalType: "bool" },
          {
            name: "token0AbsErrorTolerance",
            type: "uint256",
            internalType: "uint256",
          },
          {
            name: "token1AbsErrorTolerance",
            type: "uint256",
            internalType: "uint256",
          },
          {
            name: "defaultSwapFeeBips",
            type: "uint256",
            internalType: "uint256",
          },
        ],
      },
    ],
    stateMutability: "nonpayable",
  },
  {
    type: "function",
    name: "alm",
    inputs: [],
    outputs: [{ name: "", type: "address", internalType: "address" }],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "claimPoolManagerFees",
    inputs: [
      { name: "_feeProtocol0Bips", type: "uint256", internalType: "uint256" },
      { name: "_feeProtocol1Bips", type: "uint256", internalType: "uint256" },
    ],
    outputs: [
      {
        name: "feePoolManager0Received",
        type: "uint256",
        internalType: "uint256",
      },
      {
        name: "feePoolManager1Received",
        type: "uint256",
        internalType: "uint256",
      },
    ],
    stateMutability: "nonpayable",
  },
  {
    type: "function",
    name: "claimProtocolFees",
    inputs: [],
    outputs: [
      { name: "", type: "uint256", internalType: "uint256" },
      { name: "", type: "uint256", internalType: "uint256" },
    ],
    stateMutability: "nonpayable",
  },
  {
    type: "function",
    name: "defaultSwapFeeBips",
    inputs: [],
    outputs: [{ name: "", type: "uint256", internalType: "uint256" }],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "depositLiquidity",
    inputs: [
      { name: "_amount0", type: "uint256", internalType: "uint256" },
      { name: "_amount1", type: "uint256", internalType: "uint256" },
      { name: "_sender", type: "address", internalType: "address" },
      { name: "_verificationContext", type: "bytes", internalType: "bytes" },
      { name: "_depositData", type: "bytes", internalType: "bytes" },
    ],
    outputs: [
      { name: "amount0Deposited", type: "uint256", internalType: "uint256" },
      { name: "amount1Deposited", type: "uint256", internalType: "uint256" },
    ],
    stateMutability: "nonpayable",
  },
  {
    type: "function",
    name: "feePoolManager0",
    inputs: [],
    outputs: [{ name: "", type: "uint256", internalType: "uint256" }],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "feePoolManager1",
    inputs: [],
    outputs: [{ name: "", type: "uint256", internalType: "uint256" }],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "feeProtocol0",
    inputs: [],
    outputs: [{ name: "", type: "uint256", internalType: "uint256" }],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "feeProtocol1",
    inputs: [],
    outputs: [{ name: "", type: "uint256", internalType: "uint256" }],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "flashLoan",
    inputs: [
      { name: "_isTokenZero", type: "bool", internalType: "bool" },
      {
        name: "_receiver",
        type: "address",
        internalType: "contract IFlashBorrower",
      },
      { name: "_amount", type: "uint256", internalType: "uint256" },
      { name: "_data", type: "bytes", internalType: "bytes" },
    ],
    outputs: [],
    stateMutability: "nonpayable",
  },
  {
    type: "function",
    name: "gauge",
    inputs: [],
    outputs: [{ name: "", type: "address", internalType: "address" }],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "getPoolManagerFees",
    inputs: [],
    outputs: [
      { name: "", type: "uint256", internalType: "uint256" },
      { name: "", type: "uint256", internalType: "uint256" },
    ],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "getReserves",
    inputs: [],
    outputs: [
      { name: "", type: "uint256", internalType: "uint256" },
      { name: "", type: "uint256", internalType: "uint256" },
    ],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "getTokens",
    inputs: [],
    outputs: [{ name: "tokens", type: "address[]", internalType: "address[]" }],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "isLocked",
    inputs: [],
    outputs: [{ name: "", type: "bool", internalType: "bool" }],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "isRebaseTokenPool",
    inputs: [],
    outputs: [{ name: "", type: "bool", internalType: "bool" }],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "isToken0Rebase",
    inputs: [],
    outputs: [{ name: "", type: "bool", internalType: "bool" }],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "isToken1Rebase",
    inputs: [],
    outputs: [{ name: "", type: "bool", internalType: "bool" }],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "poolManager",
    inputs: [],
    outputs: [{ name: "", type: "address", internalType: "address" }],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "poolManagerFeeBips",
    inputs: [],
    outputs: [{ name: "", type: "uint256", internalType: "uint256" }],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "protocolFactory",
    inputs: [],
    outputs: [{ name: "", type: "address", internalType: "address" }],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "setALM",
    inputs: [{ name: "_alm", type: "address", internalType: "address" }],
    outputs: [],
    stateMutability: "nonpayable",
  },
  {
    type: "function",
    name: "setGauge",
    inputs: [{ name: "_gauge", type: "address", internalType: "address" }],
    outputs: [],
    stateMutability: "nonpayable",
  },
  {
    type: "function",
    name: "setPoolManager",
    inputs: [{ name: "_manager", type: "address", internalType: "address" }],
    outputs: [],
    stateMutability: "nonpayable",
  },
  {
    type: "function",
    name: "setPoolManagerFeeBips",
    inputs: [
      { name: "_poolManagerFeeBips", type: "uint256", internalType: "uint256" },
    ],
    outputs: [],
    stateMutability: "nonpayable",
  },
  {
    type: "function",
    name: "setSovereignOracle",
    inputs: [
      { name: "sovereignOracle", type: "address", internalType: "address" },
    ],
    outputs: [],
    stateMutability: "nonpayable",
  },
  {
    type: "function",
    name: "setSwapFeeModule",
    inputs: [
      { name: "swapFeeModule_", type: "address", internalType: "address" },
    ],
    outputs: [],
    stateMutability: "nonpayable",
  },
  {
    type: "function",
    name: "sovereignOracleModule",
    inputs: [],
    outputs: [{ name: "", type: "address", internalType: "address" }],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "sovereignVault",
    inputs: [],
    outputs: [{ name: "", type: "address", internalType: "address" }],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "spotIndex",
    inputs: [],
    outputs: [{ name: "", type: "uint32", internalType: "uint32" }],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "swap",
    inputs: [
      {
        name: "_swapParams",
        type: "tuple",
        internalType: "struct SovereignPoolSwapParams",
        components: [
          { name: "isSwapCallback", type: "bool", internalType: "bool" },
          { name: "isZeroToOne", type: "bool", internalType: "bool" },
          { name: "amountIn", type: "uint256", internalType: "uint256" },
          { name: "amountOutMin", type: "uint256", internalType: "uint256" },
          { name: "deadline", type: "uint256", internalType: "uint256" },
          { name: "recipient", type: "address", internalType: "address" },
          { name: "swapTokenOut", type: "address", internalType: "address" },
          {
            name: "swapContext",
            type: "tuple",
            internalType: "struct SovereignPoolSwapContextData",
            components: [
              { name: "externalContext", type: "bytes", internalType: "bytes" },
              { name: "verifierContext", type: "bytes", internalType: "bytes" },
              {
                name: "swapCallbackContext",
                type: "bytes",
                internalType: "bytes",
              },
              {
                name: "swapFeeModuleContext",
                type: "bytes",
                internalType: "bytes",
              },
            ],
          },
        ],
      },
    ],
    outputs: [
      { name: "amountInUsed", type: "uint256", internalType: "uint256" },
      { name: "amountOut", type: "uint256", internalType: "uint256" },
    ],
    stateMutability: "nonpayable",
  },
  {
    type: "function",
    name: "swapFeeModule",
    inputs: [],
    outputs: [{ name: "", type: "address", internalType: "address" }],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "swapFeeModuleUpdateTimestamp",
    inputs: [],
    outputs: [{ name: "", type: "uint256", internalType: "uint256" }],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "token0",
    inputs: [],
    outputs: [{ name: "", type: "address", internalType: "address" }],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "token0AbsErrorTolerance",
    inputs: [],
    outputs: [{ name: "", type: "uint256", internalType: "uint256" }],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "token1",
    inputs: [],
    outputs: [{ name: "", type: "address", internalType: "address" }],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "token1AbsErrorTolerance",
    inputs: [],
    outputs: [{ name: "", type: "uint256", internalType: "uint256" }],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "verifierModule",
    inputs: [],
    outputs: [{ name: "", type: "address", internalType: "address" }],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "withdrawLiquidity",
    inputs: [
      { name: "_amount0", type: "uint256", internalType: "uint256" },
      { name: "_amount1", type: "uint256", internalType: "uint256" },
      { name: "_sender", type: "address", internalType: "address" },
      { name: "_recipient", type: "address", internalType: "address" },
      { name: "_verificationContext", type: "bytes", internalType: "bytes" },
    ],
    outputs: [],
    stateMutability: "nonpayable",
  },

  {
    type: "event",
    name: "ALMSet",
    inputs: [
      { name: "alm", type: "address", indexed: false, internalType: "address" },
    ],
    anonymous: false,
  },
  {
    type: "event",
    name: "DepositLiquidity",
    inputs: [
      {
        name: "amount0",
        type: "uint256",
        indexed: false,
        internalType: "uint256",
      },
      {
        name: "amount1",
        type: "uint256",
        indexed: false,
        internalType: "uint256",
      },
    ],
    anonymous: false,
  },
  {
    type: "event",
    name: "Flashloan",
    inputs: [
      {
        name: "initiator",
        type: "address",
        indexed: true,
        internalType: "address",
      },
      {
        name: "receiver",
        type: "address",
        indexed: true,
        internalType: "address",
      },
      {
        name: "amount",
        type: "uint256",
        indexed: false,
        internalType: "uint256",
      },
      {
        name: "token",
        type: "address",
        indexed: false,
        internalType: "address",
      },
    ],
    anonymous: false,
  },
  {
    type: "event",
    name: "GaugeSet",
    inputs: [
      {
        name: "gauge",
        type: "address",
        indexed: false,
        internalType: "address",
      },
    ],
    anonymous: false,
  },
  {
    type: "event",
    name: "PoolManagerFeeSet",
    inputs: [
      {
        name: "poolManagerFeeBips",
        type: "uint256",
        indexed: false,
        internalType: "uint256",
      },
    ],
    anonymous: false,
  },
  {
    type: "event",
    name: "PoolManagerFeesClaimed",
    inputs: [
      {
        name: "amount0",
        type: "uint256",
        indexed: false,
        internalType: "uint256",
      },
      {
        name: "amount1",
        type: "uint256",
        indexed: false,
        internalType: "uint256",
      },
    ],
    anonymous: false,
  },
  {
    type: "event",
    name: "PoolManagerSet",
    inputs: [
      {
        name: "poolManager",
        type: "address",
        indexed: false,
        internalType: "address",
      },
    ],
    anonymous: false,
  },
  {
    type: "event",
    name: "SovereignOracleSet",
    inputs: [
      {
        name: "sovereignOracle",
        type: "address",
        indexed: false,
        internalType: "address",
      },
    ],
    anonymous: false,
  },
  {
    type: "event",
    name: "Swap",
    inputs: [
      {
        name: "sender",
        type: "address",
        indexed: true,
        internalType: "address",
      },
      {
        name: "isZeroToOne",
        type: "bool",
        indexed: false,
        internalType: "bool",
      },
      {
        name: "amountIn",
        type: "uint256",
        indexed: false,
        internalType: "uint256",
      },
      { name: "fee", type: "uint256", indexed: false, internalType: "uint256" },
      {
        name: "amountOut",
        type: "uint256",
        indexed: false,
        internalType: "uint256",
      },
      {
        name: "usdcDelta",
        type: "int256",
        indexed: false,
        internalType: "int256",
      },
    ],
    anonymous: false,
  },
  {
    type: "event",
    name: "SwapFeeModuleSet",
    inputs: [
      {
        name: "swapFeeModule",
        type: "address",
        indexed: false,
        internalType: "address",
      },
    ],
    anonymous: false,
  },
  {
    type: "event",
    name: "WithdrawLiquidity",
    inputs: [
      {
        name: "recipient",
        type: "address",
        indexed: true,
        internalType: "address",
      },
      {
        name: "amount0",
        type: "uint256",
        indexed: false,
        internalType: "uint256",
      },
      {
        name: "amount1",
        type: "uint256",
        indexed: false,
        internalType: "uint256",
      },
    ],
    anonymous: false,
  },

  {
    type: "error",
    name: "SafeERC20FailedOperation",
    inputs: [{ name: "token", type: "address", internalType: "address" }],
  },
  { type: "error", name: "SovereignPool__ALMAlreadySet", inputs: [] },
  { type: "error", name: "SovereignPool__ZeroAddress", inputs: [] },
  {
    type: "error",
    name: "SovereignPool___claimPoolManagerFees_invalidFeeReceived",
    inputs: [],
  },
  {
    type: "error",
    name: "SovereignPool___claimPoolManagerFees_invalidProtocolFee",
    inputs: [],
  },
  {
    type: "error",
    name: "SovereignPool___handleTokenInOnSwap_excessiveTokenInErrorOnTransfer",
    inputs: [],
  },
  {
    type: "error",
    name: "SovereignPool___handleTokenInOnSwap_invalidTokenInAmount",
    inputs: [],
  },
  {
    type: "error",
    name: "SovereignPool___verifyPermission_onlyPermissionedAccess",
    inputs: [
      { name: "sender", type: "address", internalType: "address" },
      { name: "accessType", type: "uint8", internalType: "uint8" },
    ],
  },
  {
    type: "error",
    name: "SovereignPool__depositLiquidity_depositDisabled",
    inputs: [],
  },
  {
    type: "error",
    name: "SovereignPool__depositLiquidity_excessiveToken0ErrorOnTransfer",
    inputs: [],
  },
  {
    type: "error",
    name: "SovereignPool__depositLiquidity_excessiveToken1ErrorOnTransfer",
    inputs: [],
  },
  {
    type: "error",
    name: "SovereignPool__depositLiquidity_incorrectTokenAmount",
    inputs: [],
  },
  {
    type: "error",
    name: "SovereignPool__depositLiquidity_insufficientToken0Amount",
    inputs: [],
  },
  {
    type: "error",
    name: "SovereignPool__depositLiquidity_insufficientToken1Amount",
    inputs: [],
  },
  {
    type: "error",
    name: "SovereignPool__depositLiquidity_zeroTotalDepositAmount",
    inputs: [],
  },
  {
    type: "error",
    name: "SovereignPool__excessiveToken0AbsErrorTolerance",
    inputs: [],
  },
  {
    type: "error",
    name: "SovereignPool__excessiveToken1AbsErrorTolerance",
    inputs: [],
  },
  {
    type: "error",
    name: "SovereignPool__getReserves_invalidReservesLength",
    inputs: [],
  },
  { type: "error", name: "SovereignPool__onlyALM", inputs: [] },
  { type: "error", name: "SovereignPool__onlyGauge", inputs: [] },
  { type: "error", name: "SovereignPool__onlyPoolManager", inputs: [] },
  { type: "error", name: "SovereignPool__onlyProtocolFactory", inputs: [] },
  { type: "error", name: "SovereignPool__sameTokenNotAllowed", inputs: [] },
  {
    type: "error",
    name: "SovereignPool__setGauge_gaugeAlreadySet",
    inputs: [],
  },
  { type: "error", name: "SovereignPool__setGauge_invalidAddress", inputs: [] },
  {
    type: "error",
    name: "SovereignPool__setPoolManagerFeeBips_excessivePoolManagerFee",
    inputs: [],
  },
  {
    type: "error",
    name: "SovereignPool__setSovereignOracle_oracleDisabled",
    inputs: [],
  },
  {
    type: "error",
    name: "SovereignPool__setSovereignOracle_sovereignOracleAlreadySet",
    inputs: [],
  },
  {
    type: "error",
    name: "SovereignPool__setSwapFeeModule_timelock",
    inputs: [],
  },
  { type: "error", name: "SovereignPool__swap_excessiveSwapFee", inputs: [] },
  { type: "error", name: "SovereignPool__swap_expired", inputs: [] },
  {
    type: "error",
    name: "SovereignPool__swap_insufficientAmountIn",
    inputs: [],
  },
  {
    type: "error",
    name: "SovereignPool__swap_invalidLiquidityQuote",
    inputs: [],
  },
  {
    type: "error",
    name: "SovereignPool__swap_invalidPoolTokenOut",
    inputs: [],
  },
  { type: "error", name: "SovereignPool__swap_invalidRecipient", inputs: [] },
  {
    type: "error",
    name: "SovereignPool__swap_invalidSwapTokenOut",
    inputs: [],
  },
  { type: "error", name: "SovereignPool__swap_zeroAmountInOrOut", inputs: [] },
  {
    type: "error",
    name: "SovereignPool__withdrawLiquidity_insufficientReserve0",
    inputs: [],
  },
  {
    type: "error",
    name: "SovereignPool__withdrawLiquidity_insufficientReserve1",
    inputs: [],
  },
  {
    type: "error",
    name: "SovereignPool__withdrawLiquidity_invalidRecipient",
    inputs: [],
  },
  {
    type: "error",
    name: "SovereignPool__withdrawLiquidity_withdrawDisabled",
    inputs: [],
  },
  {
    type: "error",
    name: "ValantisPool__flashLoan_flashLoanDisabled",
    inputs: [],
  },
  {
    type: "error",
    name: "ValantisPool__flashLoan_flashLoanNotRepaid",
    inputs: [],
  },
  {
    type: "error",
    name: "ValantisPool__flashLoan_rebaseTokenNotAllowed",
    inputs: [],
  },
  { type: "error", name: "ValantisPool__flashloan_callbackFailed", inputs: [] },
] as const;

// SovereignVault ABI - Liquidity container
export const SOVEREIGN_VAULT_ABI = [
  // Constructor (optional to include in most clients, but kept here for completeness)
  {
    type: "constructor",
    stateMutability: "nonpayable",
    inputs: [{ name: "_usdc", type: "address" }],
  },

  // View Functions
  {
    name: "strategist",
    type: "function",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "address" }],
  },
  {
    name: "usdc",
    type: "function",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "address" }],
  },
  {
    name: "defaultVault",
    type: "function",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "address" }],
  },
  {
    name: "authorizedPools",
    type: "function",
    stateMutability: "view",
    inputs: [{ name: "", type: "address" }],
    outputs: [{ name: "", type: "bool" }],
  },
  {
    name: "allocatedToCoreVault",
    type: "function",
    stateMutability: "view",
    inputs: [{ name: "", type: "address" }],
    outputs: [{ name: "", type: "uint256" }],
  },
  {
    name: "getTokensForPool",
    type: "function",
    stateMutability: "view",
    inputs: [{ name: "_pool", type: "address" }],
    outputs: [{ name: "", type: "address[]" }],
  },
  {
    name: "getReservesForPool",
    type: "function",
    stateMutability: "view",
    inputs: [
      { name: "_pool", type: "address" },
      { name: "_tokens", type: "address[]" },
    ],
    outputs: [{ name: "", type: "uint256[]" }],
  },
  {
    name: "getTotalAllocatedUSDC",
    type: "function",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "uint256" }],
  },
  {
    name: "getUSDCBalance",
    type: "function",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "uint256" }],
  },
  {
    name: "purr",
    type: "function",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "address" }],
  },
  {
    name: "getReserves",
    type: "function",
    stateMutability: "view",
    inputs: [],
    outputs: [
      { name: "reserveUsdc", type: "uint256" },
      { name: "reservePurr", type: "uint256" },
    ],
  },
  {
    name: "depositLP",
    type: "function",
    stateMutability: "nonpayable",
    inputs: [
      { name: "usdcAmount", type: "uint256" },
      { name: "purrAmount", type: "uint256" },
      { name: "minShares", type: "uint256" },
    ],
    outputs: [{ name: "shares", type: "uint256" }],
  },
  {
    name: "withdrawLP",
    type: "function",
    stateMutability: "nonpayable",
    inputs: [
      { name: "shares", type: "uint256" },
      { name: "minUsdc", type: "uint256" },
      { name: "minPurr", type: "uint256" },
    ],
    outputs: [
      { name: "usdcOut", type: "uint256" },
      { name: "purrOut", type: "uint256" },
    ],
  },
  {
    name: "hedgePerpAssetIndex",
    type: "function",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "uint32" }],
  },
  {
    name: "useMarkBasedMinHedgeSz",
    type: "function",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "bool" }],
  },
  {
    name: "minPerpHedgeSz",
    type: "function",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "uint64" }],
  },
  {
    name: "pendingHedgeBuySz",
    type: "function",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "uint256" }],
  },
  {
    name: "pendingHedgeSellSz",
    type: "function",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "uint256" }],
  },
  {
    name: "hedgeSzThreshold",
    type: "function",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "uint256" }],
  },

  // Write Functions
  {
    name: "allocate",
    type: "function",
    stateMutability: "nonpayable",
    inputs: [
      { name: "coreVault", type: "address" },
      { name: "usdcAmount", type: "uint256" },
    ],
    outputs: [],
  },
  {
    name: "deallocate",
    type: "function",
    stateMutability: "nonpayable",
    inputs: [
      { name: "coreVault", type: "address" },
      { name: "usdcAmount", type: "uint256" },
    ],
    outputs: [],
  },
  {
    name: "setAuthorizedPool",
    type: "function",
    stateMutability: "nonpayable",
    inputs: [
      { name: "_pool", type: "address" },
      { name: "_authorized", type: "bool" },
    ],
    outputs: [],
  },
  {
    name: "changeDefaultVault",
    type: "function",
    stateMutability: "nonpayable",
    inputs: [{ name: "newVault", type: "address" }],
    outputs: [],
  },
  {
    name: "approveAgent",
    type: "function",
    stateMutability: "nonpayable",
    inputs: [
      { name: "agent", type: "address" },
      { name: "name", type: "string" },
    ],
    outputs: [],
  },
  {
    name: "bridgeToCoreOnly",
    type: "function",
    stateMutability: "nonpayable",
    inputs: [{ name: "usdcAmount", type: "uint256" }],
    outputs: [],
  },
  {
    name: "bridgeToEvmOnly",
    type: "function",
    stateMutability: "nonpayable",
    inputs: [{ name: "usdcAmount", type: "uint256" }],
    outputs: [],
  },
  {
    name: "claimPoolManagerFees",
    type: "function",
    stateMutability: "nonpayable",
    inputs: [
      { name: "_feePoolManager0", type: "uint256" },
      { name: "_feePoolManager1", type: "uint256" },
    ],
    outputs: [],
  },
  {
    name: "sendTokensToRecipient",
    type: "function",
    stateMutability: "nonpayable",
    inputs: [
      { name: "_token", type: "address" },
      { name: "recipient", type: "address" },
      { name: "_amount", type: "uint256" },
    ],
    outputs: [],
  },
  {
    name: "setAuthorizedPool",
    type: "function",
    stateMutability: "nonpayable",
    inputs: [
      { name: "_pool", type: "address" },
      { name: "_authorized", type: "bool" },
    ],
    outputs: [],
  },
] as const;

export const FEE_MODULE_ABI = [
  {
    type: "constructor",
    stateMutability: "nonpayable",
    inputs: [
      { name: "_sovereignPool", type: "address" },
      { name: "_usdc", type: "address" },
      { name: "_purr", type: "address" },
      { name: "_spotIndexPURR", type: "uint64" },
      { name: "_rawPxScale", type: "uint256" },
      { name: "_rawIsPurrPerUsdc", type: "bool" },
      { name: "_baseFeeBips", type: "uint256" },
      { name: "_minFeeBips", type: "uint256" },
      { name: "_maxFeeBips", type: "uint256" },
      { name: "_liquidityBufferBps", type: "uint256" },
    ],
  },

  {
    name: "baseFeeBips",
    type: "function",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "uint256" }],
  },

  // overload #1
  {
    name: "callbackOnSwapEnd",
    type: "function",
    stateMutability: "pure",
    inputs: [
      { name: "", type: "uint256" },
      { name: "", type: "int24" },
      { name: "", type: "uint256" },
      { name: "", type: "uint256" },
      {
        name: "",
        type: "tuple",
        components: [
          { name: "feeInBips", type: "uint256" },
          { name: "internalContext", type: "bytes" },
        ],
      },
    ],
    outputs: [],
  },

  // overload #2
  {
    name: "callbackOnSwapEnd",
    type: "function",
    stateMutability: "pure",
    inputs: [
      { name: "", type: "uint256" },
      { name: "", type: "uint256" },
      { name: "", type: "uint256" },
      {
        name: "",
        type: "tuple",
        components: [
          { name: "feeInBips", type: "uint256" },
          { name: "internalContext", type: "bytes" },
        ],
      },
    ],
    outputs: [],
  },

  {
    name: "getSwapFeeInBips",
    type: "function",
    stateMutability: "view",
    inputs: [
      { name: "tokenIn", type: "address" },
      { name: "tokenOut", type: "address" },
      { name: "amountIn", type: "uint256" },
      { name: "", type: "address" },
      { name: "", type: "bytes" },
    ],
    outputs: [
      {
        name: "data",
        type: "tuple",
        components: [
          { name: "feeInBips", type: "uint256" },
          { name: "internalContext", type: "bytes" },
        ],
      },
    ],
  },

  {
    name: "baseDec",
    type: "function",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "uint8" }],
  },
  {
    name: "rawIsPurrPerUsdc",
    type: "function",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "bool" }],
  },
  {
    name: "rawPxScale",
    type: "function",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "uint256" }],
  },
  {
    name: "liquidityBufferBps",
    type: "function",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "uint256" }],
  },
  {
    name: "maxFeeBips",
    type: "function",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "uint256" }],
  },
  {
    name: "minFeeBips",
    type: "function",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "uint256" }],
  },
  {
    name: "purr",
    type: "function",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "address" }],
  },
  {
    name: "sovereignPool",
    type: "function",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "address" }],
  },
  {
    name: "spotIndexPURR",
    type: "function",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "uint64" }],
  },
  {
    name: "usdc",
    type: "function",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "address" }],
  },
  {
    name: "usdcDec",
    type: "function",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "uint8" }],
  },

  // errors
  {
    name: "InsufficientVaultLiquidity",
    type: "error",
    inputs: [
      { name: "vault", type: "address" },
      { name: "tokenOut", type: "address" },
      { name: "balOut", type: "uint256" },
      { name: "neededOut", type: "uint256" },
    ],
  },
  {
    name: "PoolPairMismatch",
    type: "error",
    inputs: [
      { name: "token0", type: "address" },
      { name: "token1", type: "address" },
    ],
  },
  {
    name: "PrecompileLib__SpotInfoPrecompileFailed",
    type: "error",
    inputs: [],
  },
  {
    name: "PrecompileLib__SpotPxPrecompileFailed",
    type: "error",
    inputs: [],
  },
  {
    name: "PrecompileLib__TokenInfoPrecompileFailed",
    type: "error",
    inputs: [],
  },
  {
    name: "PriceZero",
    type: "error",
    inputs: [],
  },
  {
    name: "ZeroVaultBalance",
    type: "error",
    inputs: [
      { name: "vault", type: "address" },
      { name: "token", type: "address" },
    ],
  },
] as const;

// ALM ABI (SovereignALM)
export const SOVEREIGN_ALM_ABI = [
  {
    type: "constructor",
    stateMutability: "nonpayable",
    inputs: [
      { name: "_pool", type: "address" },
      { name: "_usdc", type: "address" },
      { name: "_purr", type: "address" },
      { name: "_spotIndexPURR", type: "uint64" },
      { name: "_rawPxScale", type: "uint256" },
      { name: "_rawIsPurrPerUsdc", type: "bool" },
      { name: "_liquidityBufferBps", type: "uint256" },
    ],
  },

  {
    name: "getLiquidityQuote",
    type: "function",
    stateMutability: "view",
    inputs: [
      {
        name: "input",
        type: "tuple",
        components: [
          { name: "isZeroToOne", type: "bool" },
          { name: "amountInMinusFee", type: "uint256" },
          { name: "feeInBips", type: "uint256" },
          { name: "sender", type: "address" },
          { name: "recipient", type: "address" },
          { name: "tokenOutSwap", type: "address" },
        ],
      },
      { name: "", type: "bytes" },
      { name: "", type: "bytes" },
    ],
    outputs: [
      {
        name: "quote",
        type: "tuple",
        components: [
          { name: "isCallbackOnSwap", type: "bool" },
          { name: "amountOut", type: "uint256" },
          { name: "amountInFilled", type: "uint256" },
        ],
      },
    ],
  },

  {
    name: "getSpotPriceUSDCperPURR",
    type: "function",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "pxUSDCperPURR", type: "uint256" }],
  },

  {
    name: "liquidityBufferBps",
    type: "function",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "uint256" }],
  },

  {
    name: "onDepositLiquidityCallback",
    type: "function",
    stateMutability: "nonpayable",
    inputs: [
      { name: "", type: "uint256" },
      { name: "", type: "uint256" },
      { name: "", type: "bytes" },
    ],
    outputs: [],
  },

  {
    name: "onSwapCallback",
    type: "function",
    stateMutability: "nonpayable",
    inputs: [
      { name: "", type: "bool" },
      { name: "", type: "uint256" },
      { name: "", type: "uint256" },
    ],
    outputs: [],
  },

  {
    name: "pool",
    type: "function",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "address" }],
  },

  {
    name: "purr",
    type: "function",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "address" }],
  },

  {
    name: "purrDec",
    type: "function",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "uint8" }],
  },

  {
    name: "rawIsPurrPerUsdc",
    type: "function",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "bool" }],
  },

  {
    name: "rawPxScale",
    type: "function",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "uint256" }],
  },

  {
    name: "spotIndexPURR",
    type: "function",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "uint64" }],
  },

  {
    name: "usdc",
    type: "function",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "address" }],
  },

  {
    name: "usdcDec",
    type: "function",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "uint8" }],
  },

  // errors
  {
    name: "PrecompileLib__SpotInfoPrecompileFailed",
    type: "error",
    inputs: [],
  },
  {
    name: "PrecompileLib__SpotPxPrecompileFailed",
    type: "error",
    inputs: [],
  },
  {
    name: "PrecompileLib__TokenInfoPrecompileFailed",
    type: "error",
    inputs: [],
  },
  {
    name: "SovereignALM__InsufficientVaultLiquidity",
    type: "error",
    inputs: [
      { name: "vault", type: "address" },
      { name: "tokenOut", type: "address" },
      { name: "balOut", type: "uint256" },
      { name: "neededOut", type: "uint256" },
    ],
  },
  {
    name: "SovereignALM__OnlyPool",
    type: "error",
    inputs: [],
  },
  {
    name: "SovereignALM__UnsupportedPair",
    type: "error",
    inputs: [
      { name: "tokenIn", type: "address" },
      { name: "tokenOut", type: "address" },
    ],
  },
  {
    name: "SovereignALM__ZeroPrice",
    type: "error",
    inputs: [],
  },
] as const;

// HedgeEscrow — CoreWriter limit orders + claim (see `contracts/src/HedgeEscrow.sol`)
export const HEDGE_ESCROW_ABI = [
  {
    type: "function",
    name: "openBuyPurrWithUsdc",
    stateMutability: "nonpayable",
    inputs: [
      { name: "usdcEvmIn", type: "uint256" },
      { name: "limitPx1e8", type: "uint64" },
      { name: "sz1e8", type: "uint64" },
      { name: "tif", type: "uint8" },
      { name: "cloid", type: "uint128" },
    ],
    outputs: [{ name: "id", type: "uint256" }],
  },
  {
    type: "function",
    name: "claimPurrBuy",
    stateMutability: "nonpayable",
    inputs: [{ name: "id", type: "uint256" }],
    outputs: [],
  },
  {
    type: "function",
    name: "canClaimBuy",
    stateMutability: "view",
    inputs: [{ name: "id", type: "uint256" }],
    outputs: [{ type: "bool" }],
  },
  {
    type: "function",
    name: "nextTradeId",
    stateMutability: "view",
    inputs: [],
    outputs: [{ type: "uint256" }],
  },
] as const;

/// @notice DeltaFlow fee surplus buffer (USDC accounting from swap fees)
export const FEE_SURPLUS_ABI = [
  {
    name: "surplusUsdc",
    type: "function",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "uint256" }],
  },
] as const;

// ═══════════════════════════════════════════════════════════════════════════
// Type Exports
// ═══════════════════════════════════════════════════════════════════════════
export type TokenKey = keyof typeof TOKENS;
export type Token = (typeof TOKENS)[TokenKey];
