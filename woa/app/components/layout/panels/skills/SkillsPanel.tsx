'use client';

import { Box } from '@chakra-ui/react';
import { useData } from '@/context/DataContext';
import React from 'react';

export default function SkillsPanel() {
  const { skills, spells } = useData();

  return (
    <Box p="4" fontFamily="'Fira Code', monospace" fontSize="14px" overflow="auto">
      <Box fontWeight="bold">Skills:</Box>
      {skills.length === 0 ? <Box>No skills available.</Box> : (
        skills.map((s, idx) => (
          <Box key={idx}>- {s.name} ({s.state})</Box>
        ))
      )}

      <Box mt="4" fontWeight="bold">Spells:</Box>
      {spells.length === 0 ? <Box>No spells available.</Box> : (
        spells.map((sp, idx) => (
          <Box key={idx}>- {sp.name} ({sp.state})</Box>
        ))
      )}
    </Box>
  );
}
