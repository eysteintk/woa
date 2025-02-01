// app/providers.tsx
'use client';

import { ChakraProvider } from '@chakra-ui/react';
import { DataProvider } from '@/context/DataContext';
import { system } from '@/theme/theme';

export function Providers({ children }: { children: React.ReactNode }) {
  return (
    <ChakraProvider value={system}>
      <DataProvider>
        {children}
      </DataProvider>
    </ChakraProvider>
  );
}
