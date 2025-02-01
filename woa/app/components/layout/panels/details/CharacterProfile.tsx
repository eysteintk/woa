'use client';

import {
  Badge,
  Box,
  Container,
  Flex,
  SimpleGrid,
  Text,
  Image
} from '@chakra-ui/react';
import {
  BadgeCheck,
  CheckCircle2,
  MapPin,
  Medal,
  MessageCircle,
  Star,
  Wallet
} from 'lucide-react';
import React from 'react';

interface ProfileData {
  name: string;
  location: string;
  language: string;
  username: string;
  rating: number;
  ratingCount: number;
  image: string;
  title: string;
  description: string;
  skills: string[];
  softwares: string[];
}

interface CharacterProfileProps {
  profileData: ProfileData;
}

export function CharacterProfile({ profileData }: CharacterProfileProps) {
  return (
    <Container
      py="4"
      px="4"
      maxW="full"
      bg="white"
      color="gray.800"
      fontFamily="'Fira Code', monospace"
      fontSize="14px"
    >
      <Flex direction="column" gap="4">
        <Flex gap="4">
          <Box position="relative">
            <Image
              src={profileData.image}
              alt={profileData.name}
              boxSize="64px"
              borderRadius="full"
              objectFit="cover"
            />
            <Box
              position="absolute"
              bottom="0"
              right="0"
              transform="translate(50%, 50%)"
              bg="green.500"
              borderRadius="full"
              display="flex"
              alignItems="center"
              justifyContent="center"
              width="20px"
              height="20px"
            >
              <BadgeCheck width={12} height={12} color="white" />
            </Box>
          </Box>

          <Flex direction="column" gap="1" flex="1" minW="0">
            <Flex gap="2" wrap="wrap" align="center" overflow="hidden">
              <Text fontWeight="semibold" whiteSpace="nowrap" overflow="hidden" textOverflow="ellipsis" maxW="200px">
                {profileData.name}
              </Text>
              <Text color="gray.600" whiteSpace="nowrap" overflow="hidden" textOverflow="ellipsis" maxW="100px">
                @{profileData.username}
              </Text>
            </Flex>

            <Flex gap="4" wrap="wrap" fontSize="sm" align="center">
              <Flex gap="1" align="center">
                <Star width={14} height={14} />
                <Text fontWeight="medium">{profileData.rating}</Text>
                <Text color="gray.500">({profileData.ratingCount})</Text>
              </Flex>

              {profileData.location && (
                <Flex gap="1" align="center" color="gray.600">
                  <MapPin width={14} height={14} />
                  <Text>{profileData.location}</Text>
                </Flex>
              )}

              <Badge variant="outline">
                <Flex align="center" gap="1">
                  <Medal width={12} height={12} />
                  <Text>Top Rated</Text>
                </Flex>
              </Badge>
            </Flex>

            <Text color="gray.700" whiteSpace="nowrap" overflow="hidden" textOverflow="ellipsis" maxW="200px">
              {profileData.title}
            </Text>

            <Flex gap="4" fontSize="sm" color="gray.700" align="center" wrap="wrap">
              <Flex gap="1" align="center">
                <Wallet width={14} height={14} />
                <Text>120K Gold earned</Text>
              </Flex>

              <Flex gap="1" align="center">
                <MessageCircle width={14} height={14} />
                <Text>{profileData.language}</Text>
              </Flex>
            </Flex>
          </Flex>
        </Flex>

        <Flex direction="column" gap="1">
          <Text fontSize="sm" fontWeight="semibold">
            About
          </Text>
          <Box fontSize="sm" color="gray.700" whiteSpace="pre-wrap">
            {profileData.description}
          </Box>
        </Flex>

        {profileData.skills && profileData.skills.length > 0 && (
          <Flex direction="column" gap="1">
            <Text fontSize="sm" fontWeight="semibold">
              Skills
            </Text>
            <SimpleGrid gap="2" columns={2} fontSize="sm">
              {profileData.skills.map((skill) => (
                <Flex key={skill} gap="1" align="center">
                  <CheckCircle2 width={14} height={14} color="green" />
                  <Text>{skill}</Text>
                </Flex>
              ))}
            </SimpleGrid>
          </Flex>
        )}

        {profileData.softwares && profileData.softwares.length > 0 && (
          <Flex direction="column" gap="1">
            <Text fontSize="sm" fontWeight="semibold">
              Tools &amp; Software
            </Text>
            <Flex wrap="wrap" gap="2">
              {profileData.softwares.map((software) => (
                <Badge key={software} variant="outline">
                  {software}
                </Badge>
              ))}
            </Flex>
          </Flex>
        )}
      </Flex>
    </Container>
  );
}
