// app/components/layout/panels/story/StoryPanel.tsx
'use client';

import React, { useState } from 'react';
import { Box, Button, Flex, Textarea } from '@chakra-ui/react';
import { useData } from '@/context/DataContext';

export function StoryPanel() {
  const { selectedFile, contentsByFilename, sendMergeRequest } = useData();
  const [userInput, setUserInput] = useState('');

  // Determine if the selected file is a story file
  const isStoryFile = selectedFile && selectedFile.endsWith('_story.md');

  // If it's a story file, get its content; otherwise empty
  const content = (isStoryFile && selectedFile && contentsByFilename[selectedFile]) || '';

  const lines = content ? content.split('\n\n') : [];

  const options = [
    { label: 'Use a Rune of Query Mastery', value: 'query_mastery' },
    { label: 'Ask Arcane Oracle for direction', value: 'ask_oracle' },
  ];

  function handleOptionSelect(opt: { label: string; value: string }) {
    sendMergeRequest(opt.label);
  }

  function handleUserAction() {
    if (userInput.trim()) {
      sendMergeRequest(userInput.trim());
      setUserInput('');
    }
  }

  return (
    <Flex direction="column" height="100%" overflow="auto" p="4">
      <Box flex="1" overflow="auto" mb="2">
        {isStoryFile ? (
          lines.length > 0 ? (
            lines.map((line, idx) => (
              <Box key={idx} position="relative" mb="4" whiteSpace="pre-wrap" borderRadius="md" p="2" bg="gray.50">
                {line}
                <Button
                  variant="ghost"
                  size="xs"
                  position="absolute"
                  top="0"
                  right="0"
                  title="Merge into"
                  onClick={() => sendMergeRequest(line)}
                >
                  🔗
                </Button>
              </Box>
            ))
          ) : (
            <Box>No story available. Waiting for updates...</Box>
          )
        ) : (
          <Box>No story available.</Box>
        )}
      </Box>
      <Flex gap="2" wrap="wrap" mb="2">
        {options.map((opt, idx) => (
          <Button key={idx} size="sm" onClick={() => handleOptionSelect(opt)} title={`Choose: ${opt.label}`}>
            {opt.label}
          </Button>
        ))}
      </Flex>
      <Flex gap="2">
        <Textarea
          placeholder="Type your action..."
          value={userInput}
          onChange={(e) => setUserInput(e.target.value)}
          size="sm"
        />
        <Button size="sm" colorScheme="blue" onClick={handleUserAction} title="Submit your action">
          Submit
        </Button>
      </Flex>
    </Flex>
  );
}
