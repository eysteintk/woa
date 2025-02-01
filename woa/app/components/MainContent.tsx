// components/MainContent.tsx
'use client';

import React, { useEffect, useMemo } from 'react';
import { Box, Flex } from '@chakra-ui/react';
import { useData } from '@/context/DataContext';
import { NavigationPanel } from './layout/panels/navigation/NavigationPanel';
import { StoryPanel } from './layout/panels/story/StoryPanel';
import { DetailsPanel } from './layout/panels/details/DetailsPanel';
import { EventsPanel } from './layout/panels/events/EventsPanel';

export default function MainContent() {
  const { selectedFile } = useData();

  const isDarkContext = useMemo(() => {
    if (!selectedFile) return false;
    const lower = selectedFile.toLowerCase();
    return lower.includes('fortress') || lower.includes('opponents');
  }, [selectedFile]);

  // Manually toggle dark mode class if needed:
  useEffect(() => {
    if (typeof document !== 'undefined') {
      document.documentElement.classList.toggle('dark', isDarkContext);
    }
  }, [isDarkContext]);

  return (
    <Flex minH="calc(100vh - 40px)" overflow="hidden" fontFamily="'Fira Code', monospace" fontSize="14px">
      <Box width="15%" minWidth="150px" borderRight="1px solid" borderColor="gray.300">
        <NavigationPanel />
      </Box>
      <Box width="40%" borderRight="1px solid" borderColor="gray.300">
        <StoryPanel />
      </Box>
      <Box width="25%" borderRight="1px solid" borderColor="gray.300">
        <DetailsPanel />
      </Box>
      <Box width="20%">
        <EventsPanel />
      </Box>
    </Flex>
  );
}
