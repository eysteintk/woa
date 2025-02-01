'use client';

import React, { useEffect, useState } from 'react';
import {
  Box,
  Button,
  HStack,
  Image,
  Spinner,
  Text,
} from '@chakra-ui/react';
import { Alert } from '@chakra-ui/react'; // Chakra UI v3 "Alert" import
import { useData } from '@/context/DataContext';
import { useConnectedProfiles } from '@/hooks/useConnectedProfiles';

interface NavLink {
  name: string;
  file: string;
}

function parseLinksFromContent(content: string): NavLink[] {
  const lines = content.split('\n');
  const links: NavLink[] = [];
  for (const line of lines) {
    const match = line.match(/^- \[(.*?)\]\((.*?)\)/);
    if (match) {
      const [, name, file] = match;
      links.push({ name, file });
    }
  }
  return links;
}

export function NavigationPanel() {
  const {
    contentsByFilename,
    handleSelectFile,
    selectedFile,
    groupConnectionStates = {},
    joinGroup,
    isReady,
  } = useData();

  const connected = useConnectedProfiles(selectedFile);
  const [navLinks, setNavLinks] = useState<NavLink[]>([]);
  const [retrying, setRetrying] = useState(false);

  const navigationGroupState = groupConnectionStates['navigation'] || 'disconnected';
  const navigationContent = contentsByFilename['navigation.md'];

  useEffect(() => {
    if (!isReady) {
      console.log('[NavigationPanel] Service is not yet ready, waiting...');
      return;
    }

    const connectToNavigationGroup = async () => {
      try {
        await joinGroup('navigation');
      } catch (error) {
        console.error('[NavigationPanel] Failed to join navigation group:', error);
      }
    };

    if (navigationGroupState === 'disconnected') {
      connectToNavigationGroup();
    }
  }, [isReady, navigationGroupState, joinGroup]);

  useEffect(() => {
    if (navigationContent) {
      setNavLinks(parseLinksFromContent(navigationContent));
    }
  }, [navigationContent]);

  const handleRetry = async () => {
    setRetrying(true);
    try {
      await joinGroup('navigation');
    } catch (error) {
      console.error('Retry failed:', error);
    } finally {
      setRetrying(false);
    }
  };

  if (navigationGroupState === 'connecting' || retrying) {
    return (
      <Box p="4" display="flex" alignItems="center" gap="3" fontSize="14px" color="gray.600">
        <Spinner size="sm" />
        <Text>Connecting to navigation service...</Text>
      </Box>
    );
  }

  if (navigationGroupState === 'error') {
    return (
      <Box p="4">
        <Alert.Root status="error">
          <Alert.Indicator />
          <Alert.Content>
            <Alert.Title>Failed to connect to navigation service.</Alert.Title>
            <Alert.Description>
              <Button size="sm" onClick={handleRetry} mt={2}>
                Try Again
              </Button>
            </Alert.Description>
          </Alert.Content>
        </Alert.Root>
      </Box>
    );
  }

  if (navigationGroupState === 'disconnected') {
    return (
      <Box p="4">
        <Alert.Root status="warning">
          <Alert.Indicator />
          <Alert.Content>
            <Alert.Title>Disconnected from navigation service.</Alert.Title>
            <Alert.Description>
              Attempting to reconnect...
              <Button size="sm" onClick={handleRetry} ml={2}>
                Reconnect Now
              </Button>
            </Alert.Description>
          </Alert.Content>
        </Alert.Root>
      </Box>
    );
  }

  if (!navigationContent) {
    return (
      <Box p="4" display="flex" alignItems="center" gap="3" fontSize="14px" color="gray.600">
        <Spinner size="sm" />
        <Text>Loading navigation content...</Text>
      </Box>
    );
  }

  if (navLinks.length === 0) {
    return (
      <Box p="4">
        <Alert.Root status="info">
          <Alert.Indicator />
          <Alert.Content>
            <Alert.Title>No navigation links found in content.</Alert.Title>
            <Alert.Description />
          </Alert.Content>
        </Alert.Root>
      </Box>
    );
  }

  return (
    <Box
      p="4"
      fontSize="14px"
      css={{
        '& ::-webkit-scrollbar': { width: '4px' },
        '& ::-webkit-scrollbar-track': { background: 'transparent' },
        '& ::-webkit-scrollbar-thumb': { background: '#888', borderRadius: '2px' },
        '& ::-webkit-scrollbar-thumb:hover': { background: '#555' },
      }}
      overflow="auto"
    >
      {navLinks.map((link, idx) => {
        const isActive = selectedFile === link.file;
        const itemConnected = isActive ? connected : [];

        return (
          <Box
            key={idx}
            display="flex"
            alignItems="center"
            mb="2"
            bg={isActive ? 'gray.200' : 'transparent'}
            p="1"
            borderRadius="md"
          >
            <Button
              variant="ghost"
              size="sm"
              onClick={() => handleSelectFile(link.file)}
              title={`Open ${link.name}`}
              disabled={navigationGroupState !== 'connected'}
            >
              {link.name}
            </Button>

            {itemConnected.length > 0 && (
              <HStack gap="1" ml="2">
                {itemConnected.slice(0, 3).map((p, i) => (
                  <Box
                    key={i}
                    position="relative"
                    css={{
                      '&:hover::after': {
                        content: `"${p.name}"`,
                        position: 'absolute',
                        bottom: '100%',
                        left: '50%',
                        transform: 'translateX(-50%)',
                        backgroundColor: 'gray.700',
                        color: 'white',
                        padding: '2px 6px',
                        borderRadius: 'md',
                        fontSize: 'xs',
                        whiteSpace: 'nowrap',
                      },
                    }}
                  >
                    <Image src={p.image} alt={p.name} boxSize="16px" borderRadius="full" />
                  </Box>
                ))}
                {itemConnected.length > 3 && (
                  <Text fontSize="xs" color="gray.600">
                    +{itemConnected.length - 3}
                  </Text>
                )}
              </HStack>
            )}
          </Box>
        );
      })}
    </Box>
  );
}
