// app/components/layout/panels/navigation/tree-node.tsx
'use client';

import { Box } from '@chakra-ui/react';
import { ChevronDown, ChevronRight, Folder } from 'lucide-react';
import { FileNode } from '@/types/navigation';

function getFileIcon(name: string) {
  // Simple file icon
  return <Folder size={14} />;
}

interface TreeNodeProps {
  node: FileNode & { level: number };
  isExpanded: boolean;
  onNodeClickAction: (node: FileNode) => void;
}

export function TreeNode({ node, isExpanded, onNodeClickAction }: TreeNodeProps) {
  return (
    <Box
      onClick={() => onNodeClickAction(node)}
      cursor="pointer"
      _hover={{ bg: 'gray.200' }}
      display="flex"
      alignItems="center"
      gap="1"
      fontSize="13px"
      py="0.5"
      px={`${node.level * 16 + 8}px`}
    >
      {node.type === 'directory' ? (
        <Box color="blue.300">
          {isExpanded ? <ChevronDown size={14} /> : <ChevronRight size={14} />}
        </Box>
      ) : (
        <Box w="14px" />
      )}
      <Box color={node.type === 'directory' ? 'yellow.300' : 'gray.300'}>
        {node.type === 'directory' ? <Folder size={14} /> : getFileIcon(node.name)}
      </Box>
      <Box overflow="hidden" textOverflow="ellipsis" whiteSpace="nowrap" fontSize="13px">
        {node.name}
      </Box>
    </Box>
  );
}
