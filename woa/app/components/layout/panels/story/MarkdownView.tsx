'use client';

import React from 'react';
import { Box } from '@chakra-ui/react';

interface MarkdownViewProps {
  content: string | null;
}

export function MarkdownView({ content }: MarkdownViewProps) {
  if (!content) {
    return <Box p="4" color="gray.600">No content selected.</Box>;
  }

  // Just display the content as plain text for now
  return (
    <Box p="4" color="gray.800" fontFamily="'Fira Code', monospace" fontSize="14px" whiteSpace="pre-wrap">
      {content}
    </Box>
  );
}
