'use client';
import { ChakraProvider } from '@chakra-ui/react';

interface ProviderProps {
  value: any;
  children: React.ReactNode;
}

export function Provider({ value, children }: ProviderProps) {
  return <ChakraProvider value={value}>{children}</ChakraProvider>;
}