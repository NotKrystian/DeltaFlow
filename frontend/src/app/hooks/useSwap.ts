"use client";

import { useWriteContract, useWaitForTransactionReceipt } from "wagmi";
import { parseUnits } from "viem";
import { POOL_ABI, ERC20_ABI } from "../lib/contracts";
import { useMarket } from "@/app/context/MarketContext";
import { useMarketEvmDecimals } from "./useMarketEvmDecimals";

export interface SwapParams {
  isZeroToOne: boolean;
  amountIn: string;
  amountOutMin: string;
  recipient: `0x${string}`;
}

export function useApprove() {
  const {
    writeContract,
    data: hash,
    isPending,
    error,
    reset,
  } = useWriteContract();

  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({
    hash,
  });

  const approve = async (
    tokenAddress: `0x${string}`,
    spender: `0x${string}`,
    amount: bigint
  ) => {
    writeContract({
      address: tokenAddress,
      abi: ERC20_ABI,
      functionName: "approve",
      args: [spender, amount],
    });
  };

  return {
    approve,
    hash,
    isPending,
    isConfirming,
    isSuccess,
    error,
    reset,
  };
}

export function useSwap() {
  const { market } = useMarket();
  const { baseDecimals, usdcDecimals } = useMarketEvmDecimals();
  const {
    writeContract,
    data: hash,
    isPending,
    error,
    reset,
  } = useWriteContract();

  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({
    hash,
  });

  const swap = async (params: SwapParams) => {
    const { isZeroToOne, amountIn, amountOutMin, recipient } = params;
    const base = market.tokens.BASE;
    const usdc = market.tokens.USDC;

    const tokenInDecimals = isZeroToOne ? baseDecimals : usdcDecimals;
    const tokenOutDecimals = isZeroToOne ? usdcDecimals : baseDecimals;
    const tokenOut = isZeroToOne ? usdc.address : base.address;

    const amountInParsed = parseUnits(amountIn, tokenInDecimals);
    const amountOutMinParsed = parseUnits(amountOutMin || "0", tokenOutDecimals);

    const deadline = BigInt(Math.floor(Date.now() / 1000) + 1200);

    const swapParams = {
      isSwapCallback: false,
      isZeroToOne,
      amountIn: amountInParsed,
      amountOutMin: amountOutMinParsed,
      deadline,
      recipient,
      swapTokenOut: tokenOut,
      swapContext: {
        externalContext: "0x" as `0x${string}`,
        verifierContext: "0x" as `0x${string}`,
        swapCallbackContext: "0x" as `0x${string}`,
        swapFeeModuleContext: "0x" as `0x${string}`,
      },
    };

    writeContract({
      address: market.pool,
      abi: POOL_ABI,
      functionName: "swap",
      args: [swapParams],
    });
  };

  return {
    swap,
    hash,
    isPending,
    isConfirming,
    isSuccess,
    error,
    reset,
  };
}

export function calculateExpectedOutput(
  amountIn: string,
  spotPrice: number,
  isZeroToOne: boolean,
  feeBips: number = 30,
  baseDecimals: number = 18
): string {
  if (!amountIn || isNaN(Number(amountIn)) || Number(amountIn) <= 0) {
    return "0";
  }

  const amount = Number(amountIn);
  const feeMultiplier = 1 - feeBips / 10000;

  if (isZeroToOne) {
    const output = amount * spotPrice * feeMultiplier;
    return output.toFixed(6);
  }
  const output = (amount / spotPrice) * feeMultiplier;
  return output.toFixed(Math.min(baseDecimals, 8));
}
