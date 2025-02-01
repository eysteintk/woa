// app/components/layout/panels/events/EventItem.tsx
'use client';

import React from 'react';
import { Box, Button } from '@chakra-ui/react';
import { AppEvent } from '@/types/app';

interface EventItemProps {
  ev: AppEvent;
  idx: number;
  onMergeRequestAction: (content: string) => void;
}

export function EventItem({ ev, idx, onMergeRequestAction }: EventItemProps) {
  return (
    <Box key={ev.id} mb="2" position="relative" whiteSpace="pre-wrap">
      {ev.content}
      {ev.echartsOption && (
        <Box mt="2" fontStyle="italic">
          [ECharts visualization]
        </Box>
      )}
      <Button
        variant="ghost"
        size="xs"
        position="absolute"
        top="0"
        right="0"
        title="Merge into"
        onClick={() => onMergeRequestAction(ev.content)}
      >
        🔗
      </Button>
    </Box>
  );
}
