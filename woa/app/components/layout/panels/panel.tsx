// components/panel.tsx
'use client';

import { Box } from '@chakra-ui/react';
import React from 'react';

interface PanelProps {
  type: 'navigation' | 'story' | 'events' | 'details';
  isOpen: boolean;
  width: string;
  minWidth: string;
  bg?: string;
  color?: string;
  children?: React.ReactNode;
}

export function Panel({ isOpen, width, minWidth, bg = "white", color = "gray.800", children }: PanelProps) {
  return (
    <Box
      width={width}
      minWidth={minWidth}
      overflow="auto"
      bg={bg}
      color={color}
      display={isOpen ? 'block' : 'none'}
      fontFamily="'Fira Code', monospace"
      fontSize="14px"
    >
      {children}
    </Box>
  );
}
