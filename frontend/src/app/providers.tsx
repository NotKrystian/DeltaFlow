"use client";

import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { type ReactNode, useState } from "react";
import { WagmiProvider } from "wagmi";
import { darkTheme, RainbowKitProvider } from "@rainbow-me/rainbowkit";
import config from "@/rainbowKitConfig";
import "@rainbow-me/rainbowkit/styles.css";
import { MarketProvider } from "@/app/context/MarketContext";

export function Providers({ children }: { children: ReactNode }) {
  const [queryClient] = useState(() => new QueryClient());

  return (
    <WagmiProvider config={config}>
      <QueryClientProvider client={queryClient}>
        <RainbowKitProvider theme={darkTheme({ borderRadius: "medium" })}>
          <MarketProvider>{children}</MarketProvider>
        </RainbowKitProvider>
      </QueryClientProvider>
    </WagmiProvider>
  );
}
