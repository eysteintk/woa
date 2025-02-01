'use client';

import { useState, useEffect } from 'react';
import { Box, Button, Textarea, Spinner, Flex } from '@chakra-ui/react';

interface MarkdownEditorProps {
  filePath: string | null;
  content: string | null;
  isLoading: boolean;
  onSaveAction: (filePath: string, newContent: string) => Promise<void>; // Renamed prop
}

export function MarkdownEditor({ filePath, content, isLoading, onSaveAction }: MarkdownEditorProps) {
  const [draftContent, setDraftContent] = useState(content || '');

  useEffect(() => {
    setDraftContent(content || '');
  }, [content]);

  if (!filePath) {
    return (
      <Box p="4" color="gray.600">
        Select a file to view and edit its content.
      </Box>
    );
  }

  if (isLoading) {
    return (
      <Box p="4" display="flex" justifyContent="center" alignItems="center">
        <Spinner />
      </Box>
    );
  }

  const handleSaveAction = async () => {
    if (!filePath) return;
    await onSaveAction(filePath, draftContent);
  };

  return (
    <Flex direction="column" height="100%">
      <Box p="4" bg="white" borderBottom="1px solid" borderColor="gray.300">
        <Box fontWeight="bold" mb="2">
          Editing: {filePath}
        </Box>
        <Textarea
          value={draftContent}
          onChange={(e) => setDraftContent(e.target.value)}
          height="calc(100vh - 200px)"
          resize="vertical"
        />
        <Flex mt="2" gap="2">
          <Button onClick={handleSaveAction} colorScheme="blue" size="sm">
            Save
          </Button>
        </Flex>
      </Box>
    </Flex>
  );
}
