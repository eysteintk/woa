// app/layout.tsx
import React from 'react';
import './globals.css';
import { Providers } from './providers';
import { TopBanner } from './components/TopBanner';
import MainContent from './components/MainContent';
import { Box } from '@chakra-ui/react';

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body>
        <Providers>
          <TopBanner />
          <Box>
            <MainContent />
          </Box>
          {children}
        </Providers>
      </body>
    </html>
  );
}
