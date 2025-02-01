'use client';

import { Box } from '@chakra-ui/react';
import React from 'react';

interface GenericDetailsProps {
  content: string;
}

export function GenericDetails({ content }: GenericDetailsProps) {
  return (
    <Box p="4" color="gray.800" fontFamily="'Fira Code', monospace" fontSize="14px" whiteSpace="pre-wrap"
      overflow="auto"
      css={{
        '&::-webkit-scrollbar': { width: '4px' },
        '&::-webkit-scrollbar-track': { background: 'transparent' },
        '&::-webkit-scrollbar-thumb': { background: '#888', borderRadius: '2px' },
        '&::-webkit-scrollbar-thumb:hover': { background: '#555' },
      }}
    >
      {content}
    </Box>
  );
}
