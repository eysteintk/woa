// components/layout/panels/DetailsPanel.tsx
'use client';

import React from 'react';
import {
    Box, Flex, Image, Button, HStack,
    Tabs // import Tabs root
} from '@chakra-ui/react';
import {useData} from '@/context/DataContext';
import {useConnectedProfiles} from '@/hooks/useConnectedProfiles';

export function DetailsPanel() {
    const {selectedFile, requestMarkdown, contentsByFilename, skills, spells, trainer} = useData();
    const connected = useConnectedProfiles(selectedFile);

    React.useEffect(() => {
        if (selectedFile && selectedFile.endsWith('.md') && !selectedFile.endsWith('_story.md')) {
            requestMarkdown(selectedFile);
        }
    }, [selectedFile, requestMarkdown]);

    const mainContent = selectedFile ? contentsByFilename[selectedFile] || 'No data for this file.' : 'No file selected.';
    const technicalContent = 'No technical details.';
    const legalContent = 'No legal details.';

    const trainerLine = trainer ? trainer.name : 'No trainer assigned';
    const skillLines = (skills && skills.length > 0)
        ? skills.map(s => `- ${s.name} (${s.state})`).join('\n')
        : 'None';
    const spellLines = (spells && spells.length > 0)
        ? spells.map(sp => `- ${sp.name} (${sp.state})`).join('\n')
        : 'None';

    const extendedMain = `
${mainContent.trim() === '' ? 'No data for this file.' : mainContent}

## Trainer
${trainerLine}

## Skills
${skillLines}

## Spells
${spellLines}
`.trim();

    const mainEditors = connected.slice(0, 3);
    const technicalEditors: any[] = [];
    const legalEditors: any[] = [];

    function renderPresenceAvatars(profiles: any[]) {
        return (
            <HStack gap="1" ml="2">
                {profiles.map((p, idx) => (
                    <Image
                        key={idx}
                        src={p.image}
                        alt={p.name}
                        boxSize="20px"
                        borderRadius="full"
                        title={p.name}
                    />
                ))}
            </HStack>
        );
    }

    return (
        <Flex direction="column" height="100%">
            <Tabs.Root defaultValue="main" orientation="horizontal">
                <Tabs.List>
                    <Tabs.Trigger value="main">
                        Main {mainEditors.length > 0 && renderPresenceAvatars(mainEditors)}
                    </Tabs.Trigger>
                    <Tabs.Trigger value="technical">
                        Technical {technicalEditors.length > 0 && renderPresenceAvatars(technicalEditors)}
                    </Tabs.Trigger>
                    <Tabs.Trigger value="legal">
                        Legal {legalEditors.length > 0 && renderPresenceAvatars(legalEditors)}
                    </Tabs.Trigger>
                </Tabs.List>

                <Tabs.Content value="main">
                    <Box whiteSpace="pre-wrap">
                        {extendedMain}
                        <Button size="xs" variant="ghost" title="Request Edit" mt="2">
                            ✏️ Edit here
                        </Button>
                    </Box>
                </Tabs.Content>

                <Tabs.Content value="technical">
                    <Box whiteSpace="pre-wrap">
                        {technicalContent}
                        <Button size="xs" variant="ghost" title="Request Edit" mt="2">
                            ✏️ Edit here
                        </Button>
                    </Box>
                </Tabs.Content>

                <Tabs.Content value="legal">
                    <Box whiteSpace="pre-wrap">
                        {legalContent}
                        <Button size="xs" variant="ghost" title="Request Edit" mt="2">
                            ✏️ Edit here
                        </Button>
                    </Box>
                </Tabs.Content>
            </Tabs.Root>
        </Flex>
    );
}
