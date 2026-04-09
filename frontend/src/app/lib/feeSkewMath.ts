const BIPS = 10_000n;

/** Base token raw amount × px / 10^baseDec = USDC raw value of base leg. */
export function baseValueInUsdcRaw(
  baseRaw: bigint,
  pxUSDCperBase: bigint,
  baseDec: number
): bigint {
  if (baseRaw === 0n || pxUSDCperBase === 0n) return 0n;
  const scale = 10n ** BigInt(baseDec);
  return (baseRaw * pxUSDCperBase) / scale;
}

export function clampFeeBips(
  fee: bigint,
  minF: bigint,
  maxF: bigint
): bigint {
  if (fee < minF) return minF;
  if (fee > maxF) return maxF;
  return fee;
}

/**
 * Imbalance add-on only: `devBps / 10` from BalanceSeekingSwapFeeModuleV3 (pre-trade snapshot).
 */
export function imbalanceFeeAddBips(left: bigint, right: bigint): bigint {
  if (right === 0n) return 0n;
  const diff = left > right ? left - right : right - left;
  const devBps = (diff * BIPS) / right;
  return devBps / 10n;
}

/**
 * Pre-trade vault snapshot only (`left` = USDC raw, `right` = base value in USDC raw).
 * For the fee on an actual swap, the module uses projected post-trade balances; see
 * `balanceSeekingFeeBipsFuture`.
 */
export function dynamicFeeBipsFromSides(
  left: bigint,
  right: bigint,
  baseFeeBips: bigint,
  minFeeBips: bigint,
  maxFeeBips: bigint
): bigint {
  if (right === 0n) {
    return clampFeeBips(baseFeeBips, minFeeBips, maxFeeBips);
  }
  const feeAdd = imbalanceFeeAddBips(left, right);
  return clampFeeBips(baseFeeBips + feeAdd, minFeeBips, maxFeeBips);
}

function mulDiv(a: bigint, b: bigint, d: bigint): bigint {
  return (a * b) / d;
}

/**
 * Mirrors `BalanceSeekingSwapFeeModuleV3.getSwapFeeInBips` **except** it only sees EVM `balanceOf`
 * inputs. On-chain, the module uses `BalanceSheetLib` (EVM + HyperCore spot + perp `szi` + pending
 * hedge queue) for the imbalance legs; keep UI labels honest if those differ.
 */
export function balanceSeekingFeeBipsFuture(
  U: bigint,
  P: bigint,
  px: bigint,
  baseDec: number,
  amountIn: bigint,
  usdcToPurr: boolean,
  baseFeeBips: bigint,
  minFeeBips: bigint,
  maxFeeBips: bigint
): bigint {
  const BASE_SCALE = 10n ** BigInt(baseDec);
  let feeBips = baseFeeBips;
  for (let iter = 0; iter < 8; iter++) {
    const amountInNet = mulDiv(amountIn, BIPS, BIPS + feeBips);
    const estOutSwap = usdcToPurr
      ? mulDiv(amountInNet, BASE_SCALE, px)
      : mulDiv(amountInNet, px, BASE_SCALE);
    let Uf = U;
    let Pf = P;
    if (usdcToPurr) {
      Uf = U + amountIn;
      Pf = P - estOutSwap;
    } else {
      Pf = P + amountIn;
      Uf = U - estOutSwap;
    }
    const left = Uf;
    const right = mulDiv(Pf, px, BASE_SCALE);
    if (right === 0n) return clampFeeBips(baseFeeBips, minFeeBips, maxFeeBips);
    const diff = left > right ? left - right : right - left;
    const devBps = mulDiv(diff, BIPS, right);
    const feeAdd = devBps / 10n;
    const nextFee = clampFeeBips(baseFeeBips + feeAdd, minFeeBips, maxFeeBips);
    if (nextFee === feeBips) return nextFee;
    feeBips = nextFee;
  }
  return feeBips;
}

/** Recover implied `baseFeeBips` given on-chain total fee (e.g. 1 USDC probe) and vault state. */
export function inferBaseFeeBipsFromProbeTotal(
  probeTotal: bigint,
  U: bigint,
  P: bigint,
  px: bigint,
  baseDec: number,
  probeAmountIn: bigint,
  usdcToPurr: boolean,
  minBips: bigint,
  maxBips: bigint
): bigint {
  let lo = 0n;
  let hi = 10000n;
  for (let i = 0; i < 22; i++) {
    const mid = (lo + hi) / 2n;
    const got = balanceSeekingFeeBipsFuture(
      U,
      P,
      px,
      baseDec,
      probeAmountIn,
      usdcToPurr,
      mid,
      minBips,
      maxBips
    );
    if (got === probeTotal) return mid;
    if (got < probeTotal) lo = mid + 1n;
    else hi = mid - 1n;
  }
  return (lo + hi) / 2n;
}

/** Parse viem/wagmi return shapes for `SwapFeeModuleData`. */
export function extractFeeInBipsFromModuleReturn(feeDataRaw: unknown): bigint {
  if (feeDataRaw == null) return 0n;
  const r = feeDataRaw as Record<string, unknown>;
  const asB = (v: unknown) => {
    if (v == null) return 0n;
    if (typeof v === "bigint") return v;
    try {
      return BigInt(v as string | number);
    } catch {
      return 0n;
    }
  };
  if (r.feeInBips != null) return asB(r.feeInBips);
  if (Array.isArray(feeDataRaw) && feeDataRaw.length > 0) return asB(feeDataRaw[0]);
  if (r.data && typeof r.data === "object" && r.data !== null) {
    const d = r.data as Record<string, unknown>;
    if (d.feeInBips != null) return asB(d.feeInBips);
  }
  if (r.result && typeof r.result === "object" && r.result !== null) {
    const res = r.result as Record<string, unknown>;
    if (res.feeInBips != null) return asB(res.feeInBips);
  }
  const z = feeDataRaw as { 0?: { feeInBips?: unknown } };
  if (z[0]?.feeInBips != null) return asB(z[0].feeInBips);
  return 0n;
}

export function valueSplitFromVault(
  usdcRaw: bigint,
  baseRaw: bigint,
  pxUSDCperBase: bigint,
  baseDec: number
): {
  usdcValueRaw: bigint;
  baseValueRaw: bigint;
  totalValueRaw: bigint;
  usdcSharePct: number;
} {
  const usdcValueRaw = usdcRaw;
  const baseValueRaw = baseValueInUsdcRaw(baseRaw, pxUSDCperBase, baseDec);
  const totalValueRaw = usdcValueRaw + baseValueRaw;
  if (totalValueRaw === 0n) {
    return {
      usdcValueRaw,
      baseValueRaw,
      totalValueRaw,
      usdcSharePct: 50,
    };
  }
  const usdcSharePct =
    Number((usdcValueRaw * 10000n) / totalValueRaw) / 100;
  return {
    usdcValueRaw,
    baseValueRaw,
    totalValueRaw,
    usdcSharePct,
  };
}

/**
 * Hold total vault value constant; set USDC value share in tenths of a percent (0–1000 → 0.0%–100.0%).
 */
export function feeAtUsdcShareTenths(
  totalValueRaw: bigint,
  usdcShareTenths: number,
  baseFeeBips: bigint,
  minFeeBips: bigint,
  maxFeeBips: bigint
): bigint {
  const t = Math.max(0, Math.min(1000, Math.floor(usdcShareTenths)));
  const left = (totalValueRaw * BigInt(t)) / 1000n;
  const right = totalValueRaw - left;
  return dynamicFeeBipsFromSides(
    left,
    right,
    baseFeeBips,
    minFeeBips,
    maxFeeBips
  );
}

export function isZeroAddr(a: string | undefined): boolean {
  return (
    !a ||
    a.toLowerCase() === "0x0000000000000000000000000000000000000000"
  );
}
