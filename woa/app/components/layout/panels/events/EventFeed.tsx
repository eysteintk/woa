// app/components/layout/panels/events/EventFeed.tsx
'use client';

import React from 'react';
import { Box, Button } from '@chakra-ui/react';
import { useData } from '@/context/DataContext';
import { EChartsViz } from '@/components/ui/EChartsViz';
import { AppEvent } from '@/types/app';

export function EventFeed() {
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
      {events.map((event: AppEvent, idx: number) => (
        <Box key={event.id} mb="2" position="relative" whiteSpace="pre-wrap">
          {event.content}
          {event.echartsOption && <EChartsViz option={event.echartsOption} />}
          <Button
            variant="ghost"
            size="xs"
            position="absolute"
            top="0"
            right="0"
            title="Merge into"
            onClick={() => sendMergeRequest(event.content)}
          >
            🔗
          </Button>
        </Box>
      ))}
    </Box>
  );
}
