"use client";

import React, { useEffect, useMemo, useState } from "react";
import {
  useAccount,
  useBalance,
  useReadContract,
  useWriteContract,
  useWaitForTransactionReceipt,
} from "wagmi";
import { formatUnits, parseEther, parseUnits } from "viem";
import {
  RefreshCw,
  ChevronDown,
  ChevronRight,
  AlertCircle,
  CheckCircle2,
  Copy,
  ExternalLink,
  Loader2,
  Send,
  ArrowDownToLine,
  ArrowUpFromLine,
} from "lucide-react";
import {
  SOVEREIGN_POOL_ABI,
  SOVEREIGN_VAULT_ABI,
  SOVEREIGN_ALM_ABI,
  ERC20_ABI,
} from "@/contracts";
import { useMarket } from "@/app/context/MarketContext";
import { useMarketEvmDecimals } from "@/app/hooks/useMarketEvmDecimals";
import PoolSkewFeeCard from "@/app/components/PoolSkewFeeCard";

// ──────────────────────────────────────────────────────────────
// HyperCore Read Precompile (Spot Balance)
// Precompile addresses start at 0x...0800, spot balance is 0x...0801
// spotBalance(address user, uint64 token) -> SpotBalance { total, hold, entryNtl }
// ──────────────────────────────────────────────────────────────
const SPOT_BALANCE_PRECOMPILE =
  "0x0000000000000000000000000000000000000801" as const;

const L1READ_SPOT_BALANCE_ABI = [
  {
    type: "function",
    name: "spotBalance",
    stateMutability: "view",
    inputs: [
      { name: "user", type: "address" },
      { name: "token", type: "uint64" },
    ],
    outputs: [
      {
        name: "",
        type: "tuple",
        components: [
          { name: "total", type: "uint64" },
          { name: "hold", type: "uint64" },
          { name: "entryNtl", type: "uint64" },
        ],
      },
    ],
  },
] as const;

// ──────────────────────────────────────────────────────────────
// Helper Components
// ──────────────────────────────────────────────────────────────

function AddressDisplay({
  address,
  label,
}: {
  address: string;
  label: string;
}) {
  const [copied, setCopied] = useState(false);
  const isZero =
    address === "0x0000000000000000000000000000000000000000" || !address;

  const copyToClipboard = () => {
    if (!address) return;
    navigator.clipboard.writeText(address);
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  };

  return (
    <div className="flex items-center justify-between py-2 border-b border-[var(--border)] last:border-b-0">
      <span className="text-[var(--text-muted)] text-sm">{label}</span>
      <div className="flex items-center gap-2">
        {isZero ? (
          <span className="text-[var(--danger)] text-sm flex items-center gap-1">
            <AlertCircle size={14} />
            Not Set
          </span>
        ) : (
          <>
            <span className="text-[var(--foreground)] text-sm font-mono">
              {address.slice(0, 6)}...{address.slice(-4)}
            </span>
            <button
              onClick={copyToClipboard}
              className="p-1 hover:bg-[var(--card-hover)] rounded transition"
              title="Copy address"
            >
              {copied ? (
                <CheckCircle2 size={14} className="text-[var(--accent)]" />
              ) : (
                <Copy size={14} className="text-[var(--text-muted)]" />
              )}
            </button>
            <a
              href={`https://explorer.hyperliquid-testnet.xyz/address/${address}`}
              target="_blank"
              rel="noopener noreferrer"
              className="p-1 hover:bg-[var(--card-hover)] rounded transition"
              title="View on explorer"
            >
              <ExternalLink size={14} className="text-[var(--text-muted)]" />
            </a>
          </>
        )}
      </div>
    </div>
  );
}

function DataRow({
  label,
  value,
  isLoading,
  isError,
  suffix,
}: {
  label: string;
  value: string | number | undefined;
  isLoading?: boolean;
  isError?: boolean;
  suffix?: string;
}) {
  return (
    <div className="flex items-center justify-between py-2 border-b border-[var(--border)] last:border-b-0">
      <span className="text-[var(--text-muted)] text-sm">{label}</span>
      <span className="text-[var(--foreground)] text-sm font-mono">
        {isLoading ? (
          <span className="text-[var(--text-secondary)]">Loading...</span>
        ) : isError ? (
          <span className="text-[var(--danger)]">Error</span>
        ) : (
          <>
            {value ?? "-"}
            {suffix && (
              <span className="text-[var(--text-muted)] ml-1">{suffix}</span>
            )}
          </>
        )}
      </span>
    </div>
  );
}

function Section({
  title,
  children,
  defaultOpen = true,
}: {
  title: string;
  children: React.ReactNode;
  defaultOpen?: boolean;
}) {
  const [isOpen, setIsOpen] = useState(defaultOpen);

  return (
    <div className="rounded-2xl bg-[var(--input-bg)] border border-[var(--border)] overflow-hidden">
      <button
        onClick={() => setIsOpen(!isOpen)}
        className="w-full flex items-center justify-between p-4 hover:bg-[var(--card-hover)] transition"
      >
        <span className="text-[var(--foreground)] font-medium">{title}</span>
        {isOpen ? (
          <ChevronDown size={18} className="text-[var(--text-muted)]" />
        ) : (
          <ChevronRight size={18} className="text-[var(--text-muted)]" />
        )}
      </button>
      {isOpen && <div className="px-4 pb-4">{children}</div>}
    </div>
  );
}

function AddressInput({
  label,
  value,
  onChange,
  placeholder,
}: {
  label: string;
  value: string;
  onChange: (value: string) => void;
  placeholder?: string;
}) {
  return (
    <div className="mb-4">
      <label className="block text-sm text-[var(--text-muted)] mb-2">
        {label}
      </label>
      <input
        type="text"
        value={value}
        onChange={(e) => onChange(e.target.value)}
        placeholder={placeholder || "0x..."}
        className="w-full px-4 py-3 rounded-xl bg-[var(--card)] border border-[var(--border)] text-[var(--foreground)] placeholder-[var(--text-secondary)] outline-none focus:border-[var(--accent)] transition font-mono text-sm"
      />
    </div>
  );
}

// ──────────────────────────────────────────────────────────────
// Helpers
// ──────────────────────────────────────────────────────────────
type SpotBalanceReturn =
  | { total: bigint; hold: bigint; entryNtl: bigint }
  | readonly [bigint, bigint, bigint]
  | undefined;

function pickSpotTotal(x: SpotBalanceReturn): bigint | undefined {
  if (!x) return undefined;
  if ("total" in x) return x.total;
  return x[0];
}
function pickSpotHold(x: SpotBalanceReturn): bigint | undefined {
  if (!x) return undefined;
  if ("hold" in x) return x.hold;
  return x[1];
}

function safeFormatUnits(value: bigint | undefined, decimals: number): string {
  if (value === undefined) return "-";
  try {
    return formatUnits(value, decimals);
  } catch {
    return "-";
  }
}

function hedgeLegLabel(leg: number | bigint | undefined): string {
  if (leg === undefined) return "-";
  const n = Number(leg);
  if (n === 0) return "None";
  if (n === 1) return "Open only";
  if (n === 2) return "Unwind (reduce-only)";
  if (n === 3) return "Unwind then open";
  return String(n);
}

// ──────────────────────────────────────────────────────────────
// Main Component
// ──────────────────────────────────────────────────────────────

export default function StrategistCard() {
  const { address: userAddress, isConnected } = useAccount();
  const { market } = useMarket();
  const usdcToken = market.tokens.USDC;
  const baseToken = market.tokens.BASE;
  const { baseDecimals: evmBaseDec, usdcDecimals: evmUsdcDec } =
    useMarketEvmDecimals();

  const [poolAddress, setPoolAddress] = useState<string>(market.pool);
  const [vaultAddress, setVaultAddress] = useState<string>(market.vault);
  const [almAddress, setAlmAddress] = useState<string>(market.alm);

  useEffect(() => {
    setPoolAddress(market.pool);
    setVaultAddress(market.vault);
    setAlmAddress(market.alm);
    setPullCoreToken(market.base);
  }, [market.pool, market.vault, market.alm, market.base]);

  // Deposit state (EVM transfer to vault)
  const [depositToken, setDepositToken] = useState<"USDC" | "BASE">("USDC");
  const [depositAmount, setDepositAmount] = useState("");
  const [txHash, setTxHash] = useState<`0x${string}` | undefined>();

  // Allocate state (HyperCore vault allocation)
  const [allocateAmount, setAllocateAmount] = useState("");
  const [targetVault, setTargetVault] = useState(
    "0xa15099a30BBf2e68942d6F4c43d70D04FAEab0A0",
  );
  const [actionType, setActionType] = useState<
    "deposit" | "allocate" | "deallocate" | "bridge"
  >("deposit");

  // Bridge state
  const [bridgeAmount, setBridgeAmount] = useState("");
  const [bridgeDirection, setBridgeDirection] = useState<"toCore" | "toEvm">(
    "toCore",
  );

  const [bootstrapUsdc, setBootstrapUsdc] = useState("");
  const [invToCoreAmount, setInvToCoreAmount] = useState("");
  const [hypeFundAmount, setHypeFundAmount] = useState("");
  const [pullPerpMax, setPullPerpMax] = useState("");
  const [pullCoreToken, setPullCoreToken] = useState("");
  const [pullCoreMax, setPullCoreMax] = useState("");

  const isPoolDeployed =
    poolAddress !== "0x0000000000000000000000000000000000000000";
  const isVaultDeployed =
    vaultAddress !== "0x0000000000000000000000000000000000000000";
  const isAlmDeployed =
    almAddress !== "0x0000000000000000000000000000000000000000";

  // ──────────────────────────────────────────────────────────────
  // HyperCore token metadata via spotMeta
  // ──────────────────────────────────────────────────────────────
  const [coreTokenMeta, setCoreTokenMeta] = useState<
    Record<string, { index: number; weiDecimals: number }>
  >({});

  useEffect(() => {
    // You can swap this to mainnet if needed:
    // https://api.hyperliquid.xyz/info
    const endpoint = "https://api.hyperliquid-testnet.xyz/info";

    let cancelled = false;
    (async () => {
      try {
        const res = await fetch(endpoint, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ type: "spotMeta" }),
        });

        if (!res.ok) return;
        const json = await res.json();

        // Expect: { tokens: [{ name, index, weiDecimals, ... }], universe: [...] }
        const tokens: Array<{
          name: string;
          index: number;
          weiDecimals: number;
        }> = json?.tokens ?? [];

        const map: Record<string, { index: number; weiDecimals: number }> = {};
        for (const t of tokens) {
          if (!t?.name) continue;
          map[t.name.toUpperCase()] = {
            index: Number(t.index),
            weiDecimals: Number(t.weiDecimals),
          };
        }

        if (!cancelled) setCoreTokenMeta(map);
      } catch (e) {
        // non-fatal: UI will just show "-"
        console.warn("Failed to fetch spotMeta:", e);
      }
    })();

    return () => {
      cancelled = true;
    };
  }, []);

  const coreUsdc = coreTokenMeta["USDC"];
  const coreBase = coreTokenMeta[market.baseSymbol.toUpperCase()];
  const coreHype = coreTokenMeta["HYPE"];

  // ──────────────────────────────────────────────────────────────
  // Pool Data
  // ──────────────────────────────────────────────────────────────
  const { data: poolToken0, refetch: refetchToken0 } = useReadContract({
    address: poolAddress as `0x${string}`,
    abi: SOVEREIGN_POOL_ABI,
    functionName: "token0",
    query: { enabled: isPoolDeployed },
  });

  const { data: poolToken1, refetch: refetchToken1 } = useReadContract({
    address: poolAddress as `0x${string}`,
    abi: SOVEREIGN_POOL_ABI,
    functionName: "token1",
    query: { enabled: isPoolDeployed },
  });

  const {
    data: reserves,
    isLoading: loadingReserves,
    isError: errorReserves,
    refetch: refetchReserves,
  } = useReadContract({
    address: poolAddress as `0x${string}`,
    abi: SOVEREIGN_POOL_ABI,
    functionName: "getReserves",
    query: { enabled: isPoolDeployed },
  });

  const {
    data: swapFee,
    isLoading: loadingFee,
    isError: errorFee,
    refetch: refetchFee,
  } = useReadContract({
    address: poolAddress as `0x${string}`,
    abi: SOVEREIGN_POOL_ABI,
    functionName: "defaultSwapFeeBips",
    query: { enabled: isPoolDeployed },
  });

  const {
    data: poolManagerFees,
    isLoading: loadingPMFees,
    isError: errorPMFees,
    refetch: refetchPMFees,
  } = useReadContract({
    address: poolAddress as `0x${string}`,
    abi: SOVEREIGN_POOL_ABI,
    functionName: "getPoolManagerFees",
    query: { enabled: isPoolDeployed },
  });

  const { data: poolAlm, refetch: refetchPoolAlm } = useReadContract({
    address: poolAddress as `0x${string}`,
    abi: SOVEREIGN_POOL_ABI,
    functionName: "alm",
    query: { enabled: isPoolDeployed },
  });

  const { data: poolVault, refetch: refetchPoolVault } = useReadContract({
    address: poolAddress as `0x${string}`,
    abi: SOVEREIGN_POOL_ABI,
    functionName: "sovereignVault",
    query: { enabled: isPoolDeployed },
  });

  const { data: poolManager, refetch: refetchPoolManager } = useReadContract({
    address: poolAddress as `0x${string}`,
    abi: SOVEREIGN_POOL_ABI,
    functionName: "poolManager",
    query: { enabled: isPoolDeployed },
  });

  const { data: isLocked, refetch: refetchIsLocked } = useReadContract({
    address: poolAddress as `0x${string}`,
    abi: SOVEREIGN_POOL_ABI,
    functionName: "isLocked",
    query: { enabled: isPoolDeployed },
  });

  const reserveDecimals = useMemo(() => {
    if (poolToken0 === undefined || poolToken1 === undefined) return null;
    const u = usdcToken.address.toLowerCase();
    const t0 = String(poolToken0).toLowerCase();
    const t1 = String(poolToken1).toLowerCase();
    return {
      d0: t0 === u ? evmUsdcDec : evmBaseDec,
      d1: t1 === u ? evmUsdcDec : evmBaseDec,
    };
  }, [poolToken0, poolToken1, usdcToken.address, baseToken.address, evmUsdcDec, evmBaseDec]);

  // ──────────────────────────────────────────────────────────────
  // Vault Data
  // ──────────────────────────────────────────────────────────────
  const { data: strategist, refetch: refetchStrategist } = useReadContract({
    address: vaultAddress as `0x${string}`,
    abi: SOVEREIGN_VAULT_ABI,
    functionName: "strategist",
    query: { enabled: isVaultDeployed },
  });

  const { data: vaultUsdc, refetch: refetchVaultUsdc } = useReadContract({
    address: vaultAddress as `0x${string}`,
    abi: SOVEREIGN_VAULT_ABI,
    functionName: "usdc",
    query: { enabled: isVaultDeployed },
  });

  const { data: defaultVault, refetch: refetchDefaultVault } = useReadContract({
    address: vaultAddress as `0x${string}`,
    abi: SOVEREIGN_VAULT_ABI,
    functionName: "defaultVault",
    query: { enabled: isVaultDeployed },
  });

  const {
    data: totalAllocated,
    isLoading: loadingAllocated,
    isError: errorAllocated,
    refetch: refetchAllocated,
  } = useReadContract({
    address: vaultAddress as `0x${string}`,
    abi: SOVEREIGN_VAULT_ABI,
    functionName: "getTotalAllocatedUSDC",
    query: { enabled: isVaultDeployed },
  });

  const {
    data: usdcBalance,
    isLoading: loadingUsdcBal,
    isError: errorUsdcBal,
    refetch: refetchUsdcBal,
  } = useReadContract({
    address: vaultAddress as `0x${string}`,
    abi: SOVEREIGN_VAULT_ABI,
    functionName: "getUSDCBalance",
    query: { enabled: isVaultDeployed },
  });

  const { data: isPoolAuthorized, refetch: refetchPoolAuth } = useReadContract({
    address: vaultAddress as `0x${string}`,
    abi: SOVEREIGN_VAULT_ABI,
    functionName: "authorizedPools",
    args: [poolAddress as `0x${string}`],
    query: { enabled: isVaultDeployed && isPoolDeployed },
  });

  const { data: hedgePerpIx, refetch: refetchHedgePerp } = useReadContract({
    address: vaultAddress as `0x${string}`,
    abi: SOVEREIGN_VAULT_ABI,
    functionName: "hedgePerpAssetIndex",
    query: { enabled: isVaultDeployed },
  });
  const { data: useMarkMinHedge, refetch: refetchUseMark } = useReadContract({
    address: vaultAddress as `0x${string}`,
    abi: SOVEREIGN_VAULT_ABI,
    functionName: "useMarkBasedMinHedgeSz",
    query: { enabled: isVaultDeployed },
  });
  const { data: minPerpFloor, refetch: refetchMinFloor } = useReadContract({
    address: vaultAddress as `0x${string}`,
    abi: SOVEREIGN_VAULT_ABI,
    functionName: "minPerpHedgeSz",
    query: { enabled: isVaultDeployed },
  });
  const { data: pendingBuySz, refetch: refetchPendBuy } = useReadContract({
    address: vaultAddress as `0x${string}`,
    abi: SOVEREIGN_VAULT_ABI,
    functionName: "pendingHedgeBuySz",
    query: { enabled: isVaultDeployed },
  });
  const { data: pendingSellSz, refetch: refetchPendSell } = useReadContract({
    address: vaultAddress as `0x${string}`,
    abi: SOVEREIGN_VAULT_ABI,
    functionName: "pendingHedgeSellSz",
    query: { enabled: isVaultDeployed },
  });
  const { data: hedgeThresh, refetch: refetchHedgeTh } = useReadContract({
    address: vaultAddress as `0x${string}`,
    abi: SOVEREIGN_VAULT_ABI,
    functionName: "hedgeSzThreshold",
    query: { enabled: isVaultDeployed },
  });
  const { data: lastHedgeLeg, refetch: refetchLastLeg } = useReadContract({
    address: vaultAddress as `0x${string}`,
    abi: SOVEREIGN_VAULT_ABI,
    functionName: "lastHedgeLeg",
    query: { enabled: isVaultDeployed },
  });
  const { data: minBootstrapUsdc, refetch: refetchMinBootstrap } =
    useReadContract({
      address: vaultAddress as `0x${string}`,
      abi: SOVEREIGN_VAULT_ABI,
      functionName: "MIN_CORE_BOOTSTRAP_USDC",
      query: { enabled: isVaultDeployed },
    });

  // Actual ERC20 balances at vault address (EVM)
  const { data: vaultUsdcActual, refetch: refetchVaultUsdcActual } =
    useReadContract({
      address: usdcToken.address,
      abi: ERC20_ABI,
      functionName: "balanceOf",
      args: [vaultAddress as `0x${string}`],
      query: { enabled: isVaultDeployed },
    });

  const { data: vaultBaseActual, refetch: refetchVaultBaseActual } =
    useReadContract({
      address: baseToken.address,
      abi: ERC20_ABI,
      functionName: "balanceOf",
      args: [vaultAddress as `0x${string}`],
      query: { enabled: isVaultDeployed },
    });

  // Native HYPE balance on HyperEVM for the vault
  const { data: vaultHypeEvm, refetch: refetchVaultHypeEvm } = useBalance({
    address: vaultAddress as `0x${string}`,
    query: { enabled: isVaultDeployed },
  });

  // ──────────────────────────────────────────────────────────────
  // HyperCore (spot) balances for vault address
  // Uses the spot balance precompile at 0x...0801
  // ──────────────────────────────────────────────────────────────
  const { data: vaultCoreUsdcBal, refetch: refetchVaultCoreUsdc } =
    useReadContract({
      address: SPOT_BALANCE_PRECOMPILE,
      abi: L1READ_SPOT_BALANCE_ABI,
      functionName: "spotBalance",
      args:
        isVaultDeployed && coreUsdc
          ? [vaultAddress as `0x${string}`, BigInt(coreUsdc.index)]
          : undefined,
      query: { enabled: isVaultDeployed && !!coreUsdc },
    });

  const { data: vaultCoreBaseBal, refetch: refetchVaultCoreBase } =
    useReadContract({
      address: SPOT_BALANCE_PRECOMPILE,
      abi: L1READ_SPOT_BALANCE_ABI,
      functionName: "spotBalance",
      args:
        isVaultDeployed && coreBase
          ? [vaultAddress as `0x${string}`, BigInt(coreBase.index)]
          : undefined,
      query: { enabled: isVaultDeployed && !!coreBase },
    });

  const { data: vaultCoreHypeBal, refetch: refetchVaultCoreHype } =
    useReadContract({
      address: SPOT_BALANCE_PRECOMPILE,
      abi: L1READ_SPOT_BALANCE_ABI,
      functionName: "spotBalance",
      args:
        isVaultDeployed && coreHype
          ? [vaultAddress as `0x${string}`, BigInt(coreHype.index)]
          : undefined,
      query: { enabled: isVaultDeployed && !!coreHype },
    });

  // ──────────────────────────────────────────────────────────────
  // ALM Data
  // ──────────────────────────────────────────────────────────────
  const {
    data: spotPrice,
    isLoading: loadingSpot,
    isError: errorSpot,
    refetch: refetchSpot,
  } = useReadContract({
    address: almAddress as `0x${string}`,
    abi: SOVEREIGN_ALM_ABI,
    functionName: "getSpotPriceUsdcPerBase",
    query: { enabled: isAlmDeployed },
  });

  const { data: almPool, refetch: refetchAlmPool } = useReadContract({
    address: almAddress as `0x${string}`,
    abi: SOVEREIGN_ALM_ABI,
    functionName: "pool",
    query: { enabled: isAlmDeployed },
  });

  // ──────────────────────────────────────────────────────────────
  // Token Balances (User)
  // ──────────────────────────────────────────────────────────────
  const { data: userBaseBalance, refetch: refetchBaseBal } = useReadContract({
    address: baseToken.address,
    abi: ERC20_ABI,
    functionName: "balanceOf",
    args: userAddress ? [userAddress] : undefined,
    query: { enabled: !!userAddress },
  });

  const { data: userUsdcBalance, refetch: refetchUserUsdc } = useReadContract({
    address: usdcToken.address,
    abi: ERC20_ABI,
    functionName: "balanceOf",
    args: userAddress ? [userAddress] : undefined,
    query: { enabled: !!userAddress },
  });

  // ──────────────────────────────────────────────────────────────
  // Write Contract
  // ──────────────────────────────────────────────────────────────
  const { writeContractAsync, isPending } = useWriteContract();
  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({
    hash: txHash,
  });

  const isLoading = isPending || isConfirming;

  const handleDeposit = async () => {
    if (!userAddress || !depositAmount || !isVaultDeployed) return;

    const dec = depositToken === "USDC" ? evmUsdcDec : evmBaseDec;
    const token = depositToken === "USDC" ? usdcToken : baseToken;
    try {
      const amount = parseUnits(depositAmount, dec);

      // Transfer tokens directly to the vault (EVM)
      const hash = await writeContractAsync({
        address: token.address,
        abi: ERC20_ABI,
        functionName: "transfer",
        args: [vaultAddress as `0x${string}`, amount],
      });
      setTxHash(hash);
    } catch (err) {
      console.error("Deposit failed:", err);
    }
  };

  const handleAllocate = async () => {
    if (!userAddress || !allocateAmount || !isVaultDeployed || !targetVault)
      return;

    try {
      const amount = parseUnits(allocateAmount, evmUsdcDec);

      const hash = await writeContractAsync({
        address: vaultAddress as `0x${string}`,
        abi: SOVEREIGN_VAULT_ABI,
        functionName: "allocate",
        args: [targetVault as `0x${string}`, amount],
      });
      setTxHash(hash);
    } catch (err) {
      console.error("Allocate failed:", err);
    }
  };

  const handleDeallocate = async () => {
    if (!userAddress || !allocateAmount || !isVaultDeployed || !targetVault)
      return;

    try {
      const amount = parseUnits(allocateAmount, evmUsdcDec);

      const hash = await writeContractAsync({
        address: vaultAddress as `0x${string}`,
        abi: SOVEREIGN_VAULT_ABI,
        functionName: "deallocate",
        args: [targetVault as `0x${string}`, amount],
      });
      setTxHash(hash);
    } catch (err) {
      console.error("Deallocate failed:", err);
    }
  };

  // NEW: vault bridge functions
  const handleBridge = async () => {
    if (!userAddress || !bridgeAmount || !isVaultDeployed) return;

    try {
      const amount = parseUnits(bridgeAmount, evmUsdcDec);

      const hash = await writeContractAsync({
        address: vaultAddress as `0x${string}`,
        abi: SOVEREIGN_VAULT_ABI,
        functionName:
          bridgeDirection === "toCore" ? "bridgeToCoreOnly" : "bridgeToEvmOnly",
        args: [amount],
      });
      setTxHash(hash);
    } catch (err) {
      console.error("Bridge failed:", err);
    }
  };

  const handleBootstrapCore = async () => {
    if (!isVaultDeployed || !bootstrapUsdc) return;
    try {
      const amount = parseUnits(bootstrapUsdc, evmUsdcDec);
      const hash = await writeContractAsync({
        address: vaultAddress as `0x${string}`,
        abi: SOVEREIGN_VAULT_ABI,
        functionName: "bootstrapHyperCoreAccount",
        args: [amount],
      });
      setTxHash(hash);
    } catch (err) {
      console.error("bootstrapHyperCoreAccount failed:", err);
    }
  };

  const handleBridgeInventoryToCore = async () => {
    if (!isVaultDeployed || !invToCoreAmount) return;
    try {
      const amount = parseUnits(invToCoreAmount, evmBaseDec);
      const hash = await writeContractAsync({
        address: vaultAddress as `0x${string}`,
        abi: SOVEREIGN_VAULT_ABI,
        functionName: "bridgeInventoryTokenToCore",
        args: [baseToken.address as `0x${string}`, amount],
      });
      setTxHash(hash);
    } catch (err) {
      console.error("bridgeInventoryTokenToCore failed:", err);
    }
  };

  const handleFundHype = async () => {
    if (!isVaultDeployed || !hypeFundAmount) return;
    try {
      const hash = await writeContractAsync({
        address: vaultAddress as `0x${string}`,
        abi: SOVEREIGN_VAULT_ABI,
        functionName: "fundCoreWithHype",
        value: parseEther(hypeFundAmount),
      });
      setTxHash(hash);
    } catch (err) {
      console.error("fundCoreWithHype failed:", err);
    }
  };

  const handleForceFlush = async () => {
    if (!isVaultDeployed) return;
    try {
      const hash = await writeContractAsync({
        address: vaultAddress as `0x${string}`,
        abi: SOVEREIGN_VAULT_ABI,
        functionName: "forceFlushHedgeBatch",
      });
      setTxHash(hash);
    } catch (err) {
      console.error("forceFlushHedgeBatch failed:", err);
    }
  };

  const handlePullPerp = async () => {
    if (!isVaultDeployed || !pullPerpMax) return;
    try {
      const amount = parseUnits(pullPerpMax, evmUsdcDec);
      const hash = await writeContractAsync({
        address: vaultAddress as `0x${string}`,
        abi: SOVEREIGN_VAULT_ABI,
        functionName: "pullPerpUsdcToEvm",
        args: [amount],
      });
      setTxHash(hash);
    } catch (err) {
      console.error("pullPerpUsdcToEvm failed:", err);
    }
  };

  const handlePullCoreSpot = async () => {
    if (!isVaultDeployed || !pullCoreMax || !pullCoreToken.trim()) return;
    try {
      const token = pullCoreToken.trim() as `0x${string}`;
      const dec =
        token.toLowerCase() === usdcToken.address.toLowerCase()
          ? evmUsdcDec
          : evmBaseDec;
      const amount = parseUnits(pullCoreMax, dec);
      const hash = await writeContractAsync({
        address: vaultAddress as `0x${string}`,
        abi: SOVEREIGN_VAULT_ABI,
        functionName: "pullCoreSpotTokenToEvm",
        args: [token, amount],
      });
      setTxHash(hash);
    } catch (err) {
      console.error("pullCoreSpotTokenToEvm failed:", err);
    }
  };

  // ──────────────────────────────────────────────────────────────
  // Refresh All
  // ──────────────────────────────────────────────────────────────
  const refreshAll = () => {
    // Pool
    refetchToken0();
    refetchToken1();
    refetchReserves();
    refetchFee();
    refetchPMFees();
    refetchPoolAlm();
    refetchPoolVault();
    refetchPoolManager();
    refetchIsLocked();

    // Vault
    refetchStrategist();
    refetchVaultUsdc();
    refetchDefaultVault();
    refetchAllocated();
    refetchUsdcBal();
    refetchPoolAuth();
    refetchVaultUsdcActual();
    refetchVaultBaseActual();
    refetchVaultHypeEvm();

    // HyperCore balances
    refetchVaultCoreUsdc();
    refetchVaultCoreBase();
    refetchVaultCoreHype();

    refetchHedgePerp();
    refetchUseMark();
    refetchMinFloor();
    refetchPendBuy();
    refetchPendSell();
    refetchHedgeTh();
    refetchLastLeg();
    refetchMinBootstrap();

    // ALM
    refetchSpot();
    refetchAlmPool();

    // User
    refetchBaseBal();
    refetchUserUsdc();
  };

  // After ANY tx confirms: refresh state + clear tx hash so UI doesn't feel stuck
  useEffect(() => {
    if (!isSuccess) return;
    refreshAll();
    setTxHash(undefined);
    // (optional) clear inputs
    // setDepositAmount("");
    // setAllocateAmount("");
    // setBridgeAmount("");
  }, [isSuccess]); // eslint-disable-line react-hooks/exhaustive-deps

  // ──────────────────────────────────────────────────────────────
  // Display formatting for HyperCore balances
  // spotBalance returns uint64; decimals come from spotMeta token.weiDecimals
  // ──────────────────────────────────────────────────────────────
  const vaultCoreUsdcTotal = useMemo(() => {
    const total = pickSpotTotal(vaultCoreUsdcBal as SpotBalanceReturn);
    return coreUsdc ? safeFormatUnits(total, coreUsdc.weiDecimals) : "-";
  }, [vaultCoreUsdcBal, coreUsdc]);

  const vaultCoreBaseTotal = useMemo(() => {
    const total = pickSpotTotal(vaultCoreBaseBal as SpotBalanceReturn);
    return coreBase ? safeFormatUnits(total, coreBase.weiDecimals) : "-";
  }, [vaultCoreBaseBal, coreBase]);

  const vaultCoreHypeTotal = useMemo(() => {
    const total = pickSpotTotal(vaultCoreHypeBal as SpotBalanceReturn);
    return coreHype ? safeFormatUnits(total, coreHype.weiDecimals) : "-";
  }, [vaultCoreHypeBal, coreHype]);

  const vaultCoreUsdcHold = useMemo(() => {
    const hold = pickSpotHold(vaultCoreUsdcBal as SpotBalanceReturn);
    return coreUsdc ? safeFormatUnits(hold, coreUsdc.weiDecimals) : "-";
  }, [vaultCoreUsdcBal, coreUsdc]);

  const vaultCoreBaseHold = useMemo(() => {
    const hold = pickSpotHold(vaultCoreBaseBal as SpotBalanceReturn);
    return coreBase ? safeFormatUnits(hold, coreBase.weiDecimals) : "-";
  }, [vaultCoreBaseBal, coreBase]);

  const vaultCoreHypeHold = useMemo(() => {
    const hold = pickSpotHold(vaultCoreHypeBal as SpotBalanceReturn);
    return coreHype ? safeFormatUnits(hold, coreHype.weiDecimals) : "-";
  }, [vaultCoreHypeBal, coreHype]);

  return (
    <div className="w-full">
      <div className="bg-[var(--card)] rounded-3xl border border-[var(--border)] p-4 sm:p-6 shadow-lg glow-green">
        {/* Header */}
        <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4 mb-6">
          <div>
            <h2 className="text-lg font-semibold text-[var(--foreground)]">
              Vault & pool ops
            </h2>
            <p className="text-xs text-[var(--text-muted)] mt-1">
              Env addresses from <code className="text-[var(--text-secondary)]">NEXT_PUBLIC_*</code>; override below if needed.
            </p>
          </div>
          <button
            onClick={refreshAll}
            className="flex items-center gap-2 px-3 py-2 rounded-xl bg-[var(--input-bg)] border border-[var(--border)] text-[var(--text-muted)] hover:text-[var(--foreground)] hover:border-[var(--border-hover)] transition self-start"
          >
            <RefreshCw size={16} />
            <span className="text-sm">Refresh</span>
          </button>
        </div>

        <div className="mb-6">
          <PoolSkewFeeCard
            poolAddress={poolAddress}
            vaultAddress={vaultAddress}
            almAddress={almAddress}
          />
        </div>

        {/* Contract Address Inputs */}
        <Section title="Contract Addresses" defaultOpen={true}>
          <AddressInput
            label="Pool Address"
            value={poolAddress}
            onChange={setPoolAddress}
            placeholder="0x... (SovereignPool)"
          />
          <AddressInput
            label="Vault Address"
            value={vaultAddress}
            onChange={setVaultAddress}
            placeholder="0x... (SovereignVault)"
          />
          <AddressInput
            label="ALM Address"
            value={almAddress}
            onChange={setAlmAddress}
            placeholder="0x... (ALM)"
          />

          <div className="mt-4 space-y-1">
            <AddressDisplay
              address={baseToken.address}
              label={`${market.baseSymbol} Token (EVM)`}
            />
            <AddressDisplay
              address={usdcToken.address}
              label="USDC Token (EVM)"
            />
          </div>
        </Section>

        <div className="h-4" />

        {/* User Wallet */}
        {isConnected && (
          <>
            <Section title="Your Wallet (EVM)" defaultOpen={true}>
              <AddressDisplay
                address={userAddress || ""}
                label="Connected Address"
              />
              <DataRow
                label={`${market.baseSymbol} Balance`}
                value={
                  userBaseBalance
                    ? formatUnits(userBaseBalance, evmBaseDec)
                    : undefined
                }
                suffix={market.baseSymbol}
              />
              <DataRow
                label="USDC Balance"
                value={
                  userUsdcBalance
                    ? formatUnits(userUsdcBalance, evmUsdcDec)
                    : undefined
                }
                suffix="USDC"
              />
            </Section>
            <div className="h-4" />
          </>
        )}

        {/* Actions */}
        <Section title="Actions" defaultOpen={true}>
          {!isConnected ? (
            <div className="py-4 text-center text-[var(--text-muted)]">
              <AlertCircle
                size={24}
                className="mx-auto mb-2 text-[var(--text-secondary)]"
              />
              <p>Connect your wallet to perform actions.</p>
            </div>
          ) : !isVaultDeployed ? (
            <div className="py-4 text-center text-[var(--text-muted)]">
              <AlertCircle
                size={24}
                className="mx-auto mb-2 text-[var(--danger)]"
              />
              <p>Enter a valid vault address first.</p>
            </div>
          ) : (
            <div className="space-y-4">
              {/* Action type tabs */}
              <div className="flex gap-2">
                {(["deposit", "bridge", "allocate", "deallocate"] as const).map(
                  (action) => (
                    <button
                      key={action}
                      onClick={() => setActionType(action)}
                      className={`flex-1 py-2 px-3 rounded-xl text-sm font-medium transition ${
                        actionType === action
                          ? "bg-[var(--accent)] text-white"
                          : "bg-[var(--card)] border border-[var(--border)] text-[var(--text-muted)] hover:border-[var(--border-hover)]"
                      }`}
                    >
                      {action === "deposit"
                        ? "Deposit (EVM)"
                        : action === "bridge"
                          ? "Bridge (Vault)"
                          : action === "allocate"
                            ? "Allocate"
                            : "Deallocate"}
                    </button>
                  ),
                )}
              </div>

              {/* Deposit UI */}
              {actionType === "deposit" && (
                <>
                  <p className="text-sm text-[var(--text-muted)]">
                    Transfer tokens directly to the SovereignVault (EVM ERC20
                    transfer):
                  </p>

                  {/* Token selector */}
                  <div className="flex gap-2">
                    {(["USDC", "BASE"] as const).map((token) => (
                      <button
                        key={token}
                        onClick={() => setDepositToken(token)}
                        className={`flex-1 py-2 px-4 rounded-xl text-sm font-medium transition ${
                          depositToken === token
                            ? "bg-[var(--button-primary)] text-white"
                            : "bg-[var(--card)] border border-[var(--border)] text-[var(--text-muted)] hover:border-[var(--border-hover)]"
                        }`}
                      >
                        {token === "BASE" ? market.baseSymbol : "USDC"}
                      </button>
                    ))}
                  </div>

                  {/* Amount input */}
                  <div>
                    <label className="block text-sm text-[var(--text-muted)] mb-2">
                      Amount
                    </label>
                    <input
                      type="text"
                      value={depositAmount}
                      onChange={(e) =>
                        setDepositAmount(e.target.value.replace(/[^0-9.]/g, ""))
                      }
                      placeholder="0.0"
                      className="w-full px-4 py-3 rounded-xl bg-[var(--card)] border border-[var(--border)] text-[var(--foreground)] placeholder-[var(--text-secondary)] outline-none focus:border-[var(--accent)] transition text-lg"
                    />
                    <div className="mt-1 text-xs text-[var(--text-muted)]">
                      Your balance:{" "}
                      {depositToken === "USDC"
                        ? userUsdcBalance
                          ? formatUnits(userUsdcBalance, evmUsdcDec)
                          : "0"
                        : userBaseBalance
                          ? formatUnits(userBaseBalance, evmBaseDec)
                          : "0"}{" "}
                      {depositToken === "BASE" ? market.baseSymbol : "USDC"}
                    </div>
                  </div>

                  {/* Deposit button */}
                  <button
                    onClick={handleDeposit}
                    disabled={
                      isLoading || !depositAmount || Number(depositAmount) === 0
                    }
                    className={`w-full py-3 rounded-xl font-medium transition flex items-center justify-center gap-2 ${
                      isLoading || !depositAmount || Number(depositAmount) === 0
                        ? "bg-[var(--input-bg)] text-[var(--text-secondary)] cursor-not-allowed"
                        : "bg-[var(--accent)] text-white hover:bg-[var(--accent-hover)]"
                    }`}
                  >
                    {isLoading ? (
                      <>
                        <Loader2 size={18} className="animate-spin" />
                        Confirming...
                      </>
                    ) : (
                      <>
                        <Send size={18} />
                        Transfer{" "}
                        {depositToken === "BASE" ? market.baseSymbol : "USDC"}{" "}
                        to Vault
                      </>
                    )}
                  </button>
                </>
              )}

              {/* Bridge UI */}
              {actionType === "bridge" && (
                <>
                  <p className="text-sm text-[var(--text-muted)]">
                    Call the vault strategist-only bridge functions (USDC
                    amount):
                  </p>

                  {/* Direction selector */}
                  <div className="flex gap-2">
                    <button
                      onClick={() => setBridgeDirection("toCore")}
                      className={`flex-1 py-2 px-4 rounded-xl text-sm font-medium transition ${
                        bridgeDirection === "toCore"
                          ? "bg-[var(--button-primary)] text-white"
                          : "bg-[var(--card)] border border-[var(--border)] text-[var(--text-muted)] hover:border-[var(--border-hover)]"
                      }`}
                    >
                      <span className="inline-flex items-center justify-center gap-2">
                        <ArrowDownToLine size={16} />
                        Bridge to Core
                      </span>
                    </button>
                    <button
                      onClick={() => setBridgeDirection("toEvm")}
                      className={`flex-1 py-2 px-4 rounded-xl text-sm font-medium transition ${
                        bridgeDirection === "toEvm"
                          ? "bg-[var(--button-primary)] text-white"
                          : "bg-[var(--card)] border border-[var(--border)] text-[var(--text-muted)] hover:border-[var(--border-hover)]"
                      }`}
                    >
                      <span className="inline-flex items-center justify-center gap-2">
                        <ArrowUpFromLine size={16} />
                        Bridge to EVM
                      </span>
                    </button>
                  </div>

                  {/* Amount */}
                  <div>
                    <label className="block text-sm text-[var(--text-muted)] mb-2">
                      USDC Amount
                    </label>
                    <input
                      type="text"
                      value={bridgeAmount}
                      onChange={(e) =>
                        setBridgeAmount(e.target.value.replace(/[^0-9.]/g, ""))
                      }
                      placeholder="0.0"
                      className="w-full px-4 py-3 rounded-xl bg-[var(--card)] border border-[var(--border)] text-[var(--foreground)] placeholder-[var(--text-secondary)] outline-none focus:border-[var(--accent)] transition text-lg"
                    />
                    <div className="mt-1 text-xs text-[var(--text-muted)]">
                      Vault USDC (EVM):{" "}
                      {vaultUsdcActual
                        ? formatUnits(vaultUsdcActual, evmUsdcDec)
                        : "0"}{" "}
                      USDC
                    </div>
                  </div>

                  {/* Bridge button */}
                  <button
                    onClick={handleBridge}
                    disabled={
                      isLoading || !bridgeAmount || Number(bridgeAmount) === 0
                    }
                    className={`w-full py-3 rounded-xl font-medium transition flex items-center justify-center gap-2 ${
                      isLoading || !bridgeAmount || Number(bridgeAmount) === 0
                        ? "bg-[var(--input-bg)] text-[var(--text-secondary)] cursor-not-allowed"
                        : "bg-[var(--accent)] text-white hover:bg-[var(--accent-hover)]"
                    }`}
                  >
                    {isLoading ? (
                      <>
                        <Loader2 size={18} className="animate-spin" />
                        Confirming...
                      </>
                    ) : (
                      <>
                        {bridgeDirection === "toCore" ? (
                          <ArrowDownToLine size={18} />
                        ) : (
                          <ArrowUpFromLine size={18} />
                        )}
                        {bridgeDirection === "toCore"
                          ? "bridgeToCoreOnly(USDC)"
                          : "bridgeToEvmOnly(USDC)"}
                      </>
                    )}
                  </button>

                  <div className="p-3 rounded-xl bg-[var(--accent-muted)] border border-[var(--border)]">
                    <p className="text-xs text-[var(--text-muted)]">
                      <strong>Note:</strong> These are{" "}
                      <code>onlyStrategist</code> functions. If your wallet
                      isn’t the vault strategist, the tx will revert.
                    </p>
                  </div>
                </>
              )}

              {/* Allocate/Deallocate UI */}
              {(actionType === "allocate" || actionType === "deallocate") && (
                <>
                  <p className="text-sm text-[var(--text-muted)]">
                    {actionType === "allocate"
                      ? "Move USDC from SovereignVault to HyperCore vault for yield:"
                      : "Withdraw USDC from HyperCore vault back to SovereignVault:"}
                  </p>

                  {/* Target vault input */}
                  <div>
                    <label className="block text-sm text-[var(--text-muted)] mb-2">
                      HyperCore Vault Address
                    </label>
                    <input
                      type="text"
                      value={targetVault}
                      onChange={(e) => setTargetVault(e.target.value)}
                      placeholder="0x..."
                      className="w-full px-4 py-3 rounded-xl bg-[var(--card)] border border-[var(--border)] text-[var(--foreground)] placeholder-[var(--text-secondary)] outline-none focus:border-[var(--accent)] transition font-mono text-sm"
                    />
                    <div className="mt-1 text-xs text-[var(--text-muted)]">
                      Default HLP Vault:
                      0xa15099a30BBf2e68942d6F4c43d70D04FAEab0A0
                    </div>
                  </div>

                  {/* Amount input */}
                  <div>
                    <label className="block text-sm text-[var(--text-muted)] mb-2">
                      USDC Amount
                    </label>
                    <input
                      type="text"
                      value={allocateAmount}
                      onChange={(e) =>
                        setAllocateAmount(
                          e.target.value.replace(/[^0-9.]/g, ""),
                        )
                      }
                      placeholder="0.0"
                      className="w-full px-4 py-3 rounded-xl bg-[var(--card)] border border-[var(--border)] text-[var(--foreground)] placeholder-[var(--text-secondary)] outline-none focus:border-[var(--accent)] transition text-lg"
                    />
                    <div className="mt-1 text-xs text-[var(--text-muted)]">
                      Vault USDC (EVM):{" "}
                      {vaultUsdcActual
                        ? formatUnits(vaultUsdcActual, evmUsdcDec)
                        : "0"}{" "}
                      USDC
                    </div>
                  </div>

                  {/* Allocate/Deallocate button */}
                  <button
                    onClick={
                      actionType === "allocate"
                        ? handleAllocate
                        : handleDeallocate
                    }
                    disabled={
                      isLoading ||
                      !allocateAmount ||
                      Number(allocateAmount) === 0 ||
                      !targetVault
                    }
                    className={`w-full py-3 rounded-xl font-medium transition flex items-center justify-center gap-2 ${
                      isLoading ||
                      !allocateAmount ||
                      Number(allocateAmount) === 0 ||
                      !targetVault
                        ? "bg-[var(--input-bg)] text-[var(--text-secondary)] cursor-not-allowed"
                        : actionType === "allocate"
                          ? "bg-[var(--accent)] text-white hover:bg-[var(--accent-hover)]"
                          : "bg-[var(--danger)] text-white hover:opacity-90"
                    }`}
                  >
                    {isLoading ? (
                      <>
                        <Loader2 size={18} className="animate-spin" />
                        Confirming...
                      </>
                    ) : (
                      <>
                        <Send size={18} />
                        {actionType === "allocate"
                          ? "Allocate to HyperCore"
                          : "Deallocate from HyperCore"}
                      </>
                    )}
                  </button>

                  <div className="p-3 rounded-xl bg-[var(--accent-muted)] border border-[var(--border)]">
                    <p className="text-xs text-[var(--text-muted)]">
                      <strong>Note:</strong> Only the strategist can call
                      allocate/deallocate.
                    </p>
                  </div>
                </>
              )}

              {/* Success message */}
              {isSuccess && txHash && (
                <div className="p-3 rounded-xl bg-[var(--accent-muted)] border border-[var(--accent)] text-center">
                  <p className="text-[var(--accent)] text-sm">
                    Transaction successful!{" "}
                    <a
                      href={`https://explorer.hyperliquid-testnet.xyz/tx/${txHash}`}
                      target="_blank"
                      rel="noopener noreferrer"
                      className="underline font-medium"
                    >
                      View transaction
                    </a>
                  </p>
                </div>
              )}
            </div>
          )}
        </Section>

        <div className="h-4" />

        <div className="h-4" />

        <div className="h-4" />

        {/* Pool State */}
        <Section title="Pool State" defaultOpen={true}>
          {!isPoolDeployed ? (
            <div className="py-4 text-center text-[var(--text-muted)]">
              <AlertCircle
                size={24}
                className="mx-auto mb-2 text-[var(--danger)]"
              />
              <p>Pool not deployed. Enter a valid pool address above.</p>
            </div>
          ) : (
            <>
              <AddressDisplay
                address={(poolToken0 as string) || ""}
                label="Token0"
              />
              <AddressDisplay
                address={(poolToken1 as string) || ""}
                label="Token1"
              />
              <DataRow
                label="Reserve 0"
                value={
                  reserves && reserveDecimals
                    ? formatUnits(reserves[0], reserveDecimals.d0)
                    : undefined
                }
                isLoading={loadingReserves}
                isError={errorReserves}
              />
              <DataRow
                label="Reserve 1"
                value={
                  reserves && reserveDecimals
                    ? formatUnits(reserves[1], reserveDecimals.d1)
                    : undefined
                }
                isLoading={loadingReserves}
                isError={errorReserves}
              />
              <DataRow
                label="Pool default fee (immutable)"
                value={swapFee ? `${Number(swapFee) / 100}%` : undefined}
                isLoading={loadingFee}
                isError={errorFee}
                suffix={`(${swapFee} bips fallback if no module)`}
              />

              <AddressDisplay
                address={(poolVault as string) || ""}
                label="Sovereign Vault"
              />
              <AddressDisplay
                address={(poolManager as string) || ""}
                label="Pool Manager"
              />
            </>
          )}
        </Section>

        <div className="h-4" />

        {/* Vault State */}
        <Section title="Vault State" defaultOpen={true}>
          {!isVaultDeployed ? (
            <div className="py-4 text-center text-[var(--text-muted)]">
              <AlertCircle
                size={24}
                className="mx-auto mb-2 text-[var(--danger)]"
              />
              <p>Vault not deployed. Enter a valid vault address above.</p>
            </div>
          ) : (
            <>
              <AddressDisplay
                address={(strategist as string) || ""}
                label="Strategist"
              />
              <AddressDisplay
                address={(vaultUsdc as string) || ""}
                label="USDC Token (Vault)"
              />
              <AddressDisplay
                address={(defaultVault as string) || ""}
                label="Default HLP Vault"
              />

              <DataRow
                label="getTotalAllocatedUSDC"
                value={
                  totalAllocated
                    ? formatUnits(totalAllocated, evmUsdcDec)
                    : undefined
                }
                isLoading={loadingAllocated}
                isError={errorAllocated}
                suffix="USDC"
              />

              <DataRow
                label="getUSDCBalance"
                value={
                  usdcBalance
                    ? formatUnits(usdcBalance, evmUsdcDec)
                    : undefined
                }
                isLoading={loadingUsdcBal}
                isError={errorUsdcBal}
                suffix="USDC"
              />
            </>
          )}
        </Section>

        <div className="h-4" />

        <Section title="Perp hedge queue (swap IOC batching)" defaultOpen={true}>
          {!isVaultDeployed ? (
            <p className="text-sm text-[var(--text-muted)]">Set vault address.</p>
          ) : (
            <>
              <DataRow
                label="hedgePerpAssetIndex"
                value={hedgePerpIx !== undefined ? String(hedgePerpIx) : undefined}
              />
              <DataRow
                label="useMarkBasedMinHedgeSz"
                value={
                  useMarkMinHedge === undefined
                    ? undefined
                    : useMarkMinHedge
                      ? "yes"
                      : "no"
                }
              />
              <DataRow
                label="minPerpHedgeSz (floor / fixed)"
                value={minPerpFloor !== undefined ? String(minPerpFloor) : undefined}
              />
              <DataRow
                label="hedgeSzThreshold (current)"
                value={hedgeThresh !== undefined ? String(hedgeThresh) : undefined}
              />
              <DataRow
                label="pendingHedgeBuySz"
                value={pendingBuySz !== undefined ? String(pendingBuySz) : undefined}
              />
              <DataRow
                label="pendingHedgeSellSz"
                value={
                  pendingSellSz !== undefined ? String(pendingSellSz) : undefined
                }
              />
              <DataRow
                label="lastHedgeLeg (on-chain IOC leg)"
                value={hedgeLegLabel(lastHedgeLeg)}
              />
              <p className="text-xs text-[var(--text-muted)] mt-3">
                Swap fees use memo-style unwind vs new-risk blending from the
                balance sheet (
                <code>DeltaFlowCompositeFeeModule</code>
                ). <code>lastHedgeLeg</code> records the vault&apos;s last perp leg
                (open / reduce-only / both) for ops.
              </p>
              <p className="text-xs text-[var(--text-muted)] mt-2">
                Mark mode uses ~$10 HL min notional via{" "}
                <code>normalizedMarkPx</code>. Opposite swap flow nets queued{" "}
                <code>sz</code> before the next IOC.
              </p>
            </>
          )}
        </Section>

        <div className="h-4" />

        <Section title="Core account, inventory → Core, hedge pulls" defaultOpen={true}>
          {!isVaultDeployed ? (
            <p className="text-sm text-[var(--text-muted)]">Set vault address.</p>
          ) : (
            <div className="space-y-6">
              <p className="text-xs text-[var(--text-muted)]">
                Run bootstrap in its own tx before heavy CoreWriter use. Bridge{" "}
                {market.baseSymbol} to Core when USDC is tight but base inventory
                should fund Core spot for hedging. Native HYPE funds Core gas; low Core
                HYPE is a good time to steer fee settlement toward HYPE off-chain.
              </p>

              <div className="rounded-xl border border-[var(--border)] p-4 space-y-3">
                <p className="text-sm font-medium text-[var(--foreground)]">
                  Create Core account (min USDC)
                </p>
                <p className="text-xs text-[var(--text-muted)]">
                  Min:{" "}
                  {minBootstrapUsdc !== undefined
                    ? formatUnits(minBootstrapUsdc, evmUsdcDec)
                    : "1"}{" "}
                  USDC · <code>bootstrapHyperCoreAccount</code>
                </p>
                <input
                  type="text"
                  value={bootstrapUsdc}
                  onChange={(e) =>
                    setBootstrapUsdc(e.target.value.replace(/[^0-9.]/g, ""))
                  }
                  placeholder="USDC amount"
                  className="w-full px-3 py-2 rounded-lg bg-[var(--card)] border border-[var(--border)] text-[var(--foreground)] text-sm"
                />
                <button
                  type="button"
                  onClick={handleBootstrapCore}
                  disabled={isLoading || !bootstrapUsdc}
                  className="w-full py-2 rounded-lg bg-[var(--accent)] text-white text-sm font-medium disabled:opacity-50"
                >
                  bootstrapHyperCoreAccount
                </button>
              </div>

              <div className="rounded-xl border border-[var(--border)] p-4 space-y-3">
                <p className="text-sm font-medium text-[var(--foreground)]">
                  Bridge {market.baseSymbol} (EVM → Core spot)
                </p>
                <p className="text-xs text-[var(--text-muted)]">
                  <code>bridgeInventoryTokenToCore</code>({market.baseSymbol})
                </p>
                <input
                  type="text"
                  value={invToCoreAmount}
                  onChange={(e) =>
                    setInvToCoreAmount(e.target.value.replace(/[^0-9.]/g, ""))
                  }
                  placeholder={`${market.baseSymbol} amount`}
                  className="w-full px-3 py-2 rounded-lg bg-[var(--card)] border border-[var(--border)] text-[var(--foreground)] text-sm"
                />
                <button
                  type="button"
                  onClick={handleBridgeInventoryToCore}
                  disabled={isLoading || !invToCoreAmount}
                  className="w-full py-2 rounded-lg bg-[var(--button-primary)] text-white text-sm font-medium disabled:opacity-50"
                >
                  bridgeInventoryTokenToCore
                </button>
              </div>

              <div className="rounded-xl border border-[var(--border)] p-4 space-y-3">
                <p className="text-sm font-medium text-[var(--foreground)]">
                  Fund Core with HYPE (native)
                </p>
                <input
                  type="text"
                  value={hypeFundAmount}
                  onChange={(e) =>
                    setHypeFundAmount(e.target.value.replace(/[^0-9.]/g, ""))
                  }
                  placeholder="HYPE (e.g. 0.5)"
                  className="w-full px-3 py-2 rounded-lg bg-[var(--card)] border border-[var(--border)] text-[var(--foreground)] text-sm"
                />
                <button
                  type="button"
                  onClick={handleFundHype}
                  disabled={isLoading || !hypeFundAmount}
                  className="w-full py-2 rounded-lg bg-[var(--button-primary)] text-white text-sm font-medium disabled:opacity-50"
                >
                  fundCoreWithHype
                </button>
              </div>

              <div className="rounded-xl border border-[var(--border)] p-4 space-y-3">
                <p className="text-sm font-medium text-[var(--foreground)]">
                  Flush & pull
                </p>
                <button
                  type="button"
                  onClick={handleForceFlush}
                  disabled={isLoading}
                  className="w-full py-2 rounded-lg bg-[var(--card)] border border-[var(--border)] text-sm font-medium disabled:opacity-50"
                >
                  forceFlushHedgeBatch
                </button>
                <div className="flex flex-col gap-2">
                  <input
                    type="text"
                    value={pullPerpMax}
                    onChange={(e) =>
                      setPullPerpMax(e.target.value.replace(/[^0-9.]/g, ""))
                    }
                    placeholder="max USDC (perp → EVM)"
                    className="w-full px-3 py-2 rounded-lg bg-[var(--card)] border border-[var(--border)] text-[var(--foreground)] text-sm"
                  />
                  <button
                    type="button"
                    onClick={handlePullPerp}
                    disabled={isLoading || !pullPerpMax}
                    className="w-full py-2 rounded-lg bg-[var(--card)] border border-[var(--border)] text-sm font-medium disabled:opacity-50"
                  >
                    pullPerpUsdcToEvm
                  </button>
                </div>
                <div className="flex flex-col gap-2">
                  <input
                    type="text"
                    value={pullCoreToken}
                    onChange={(e) => setPullCoreToken(e.target.value)}
                    placeholder="token address (default: base)"
                    className="w-full px-3 py-2 rounded-lg bg-[var(--card)] border border-[var(--border)] text-[var(--foreground)] font-mono text-xs"
                  />
                  <input
                    type="text"
                    value={pullCoreMax}
                    onChange={(e) =>
                      setPullCoreMax(e.target.value.replace(/[^0-9.]/g, ""))
                    }
                    placeholder="max amount (USDC: 6 dec, else base dec)"
                    className="w-full px-3 py-2 rounded-lg bg-[var(--card)] border border-[var(--border)] text-[var(--foreground)] text-sm"
                  />
                  <button
                    type="button"
                    onClick={handlePullCoreSpot}
                    disabled={isLoading || !pullCoreMax}
                    className="w-full py-2 rounded-lg bg-[var(--card)] border border-[var(--border)] text-sm font-medium disabled:opacity-50"
                  >
                    pullCoreSpotTokenToEvm
                  </button>
                </div>
              </div>
            </div>
          )}
        </Section>

        <div className="h-4" />
      </div>
    </div>
  );
}
