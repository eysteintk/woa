// app/components/layout/panels/events/EventsPanel.tsx
'use client';

import { Box, Button } from '@chakra-ui/react';
import { useData } from '@/context/DataContext';
import React from 'react';
import { EChartsViz } from '@/components/ui/EChartsViz';

export function EventsPanel() {
  const { events, sendMergeRequest } = useData();

  if (events.length === 0) {
    return (
      <Box p="4" color="gray.600" fontFamily="'Fira Code', monospace" fontSize="14px">
        No events available.
      </Box>
    );
  }

  return (
    <Box p="4" color="gray.800" fontFamily="'Fira Code', monospace" fontSize="14px" overflow="auto"
      css={{
        '&::-webkit-scrollbar': { width: '4px' },
        '&::-webkit-scrollbar-track': { background: 'transparent' },
        '&::-webkit-scrollbar-thumb': { background: '#888', borderRadius: '2px' },
        '&::-webkit-scrollbar-thumb:hover': { background: '#555' },
      }}
    >
      {events.map((ev) => (
        <Box key={ev.id} mb="2" position="relative" whiteSpace="pre-wrap">
          {ev.content}
          {ev.echartsOption && <EChartsViz option={ev.echartsOption} />}
          <Button
            variant="ghost"
            size="xs"
            position="absolute"
            top="0"
            right="0"
            title="Merge into"
            onClick={() => sendMergeRequest(ev.content)}
          >
            🔗
          </Button>
        </Box>
      ))}
    </Box>
  );
}
