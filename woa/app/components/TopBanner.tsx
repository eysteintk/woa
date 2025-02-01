// components/TopBanner.tsx
'use client';

import { Flex, Box, Button } from '@chakra-ui/react';
import React from 'react';
import { useData } from '@/context/DataContext';
import { FolderGit, Settings, Home, Globe2 } from 'lucide-react';

function renderButton(label: string, onClick?: () => void, IconComponent?: React.ComponentType<React.SVGProps<SVGSVGElement>>) {
  if (!onClick) {
    return (
      <Button variant="ghost" size="sm" aria-label={label} title={label} disabled>
        {IconComponent ? <IconComponent width={16} height={16} /> : null}
      </Button>
    );
  }
  return (
    <Button variant="ghost" size="sm" onClick={onClick} aria-label={label} title={label}>
      {IconComponent ? <IconComponent width={16} height={16} /> : null}
    </Button>
  );
}

export function TopBanner() {
  const { selectedFile, handleSelectFile } = useData();

  const onToggleHome = () => {
    handleSelectFile('navigation/navigation_navigation.md');
  };

  const onToggleWorld = () => {
    // no event for world
  };

  const onToggleProfile = () => {
    handleSelectFile('profiles/profiles_navigation.md');
  };

  return (
    <Flex
      as="header"
      bg="#eaeaea"
      borderBottom="1px solid #ccc"
      p="2"
      align="center"
      justify="space-between"
      fontFamily="'Fira Code', monospace"
      fontSize="14px"
      color="gray.800"
      style={{ height: '40px' }}
    >
      <Box
        fontWeight="500"
        fontSize="14px"
        whiteSpace="nowrap"
        overflow="hidden"
        textOverflow="ellipsis"
        maxW="50%"
      >
        File: {selectedFile || 'None'}
      </Box>

      <Flex gap="2">
        {renderButton('Home', onToggleHome, Home)}
        {renderButton('World', onToggleWorld, Globe2)}
        {renderButton('Profile', onToggleProfile, Settings)}
        {renderButton('Toggle Navigation Panel', undefined, FolderGit)}
      </Flex>
    </Flex>
  );
}
