import {
  ADDRESSES,
  SOVEREIGN_POOL_ABI,
  SOVEREIGN_ALM_ABI,
} from "../../contracts";

/** Same addresses as `src/contracts.ts` — hooks use this module for pool/ALM reads. */
export const CONTRACTS = {
  POOL: ADDRESSES.POOL,
  ALM: ADDRESSES.ALM,
  PURR: ADDRESSES.PURR,
  USDC: ADDRESSES.USDC,
} as const;

// Token metadata
export const TOKENS = {
  PURR: {
    address: CONTRACTS.PURR,
    symbol: "PURR",
    name: "PURR",
    decimals: 18,
    logo: "/purr.png",
  },
  USDC: {
    address: CONTRACTS.USDC,
    symbol: "USDC",
    name: "USD Coin",
    decimals: 6,
    logo: "/usdc.png",
  },
} as const;

// Minimal ERC20 ABI for token operations
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
] as const;

export const ALM_ABI = SOVEREIGN_ALM_ABI;
export const POOL_ABI = SOVEREIGN_POOL_ABI;
