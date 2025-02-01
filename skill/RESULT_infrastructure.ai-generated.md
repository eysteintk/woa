# Infra Analysis for Script: skill\infrastructure-prod.sh

## Overview

Main cloud services used:

- Skills Container App
- Azure Redis Cache
- Web PubSub
- Container Registry
- Confluent Kafka

## Cloud Information

Services run on Azure cloud infrastructure.

## Resource Info

- **Resource Group**: abs-rg-we-prod
- **Location**: westeurope

## Monitoring Info

Uses Log Analytics workspace and Application Insights with diagnostic settings for container app metrics

## Services

### Skills Container App
**Purpose**: Main application container running the skills service with autoscaling capabilities

**Service Flow**:
- Connects to Redis Cache for data storage
- Integrates with Web PubSub for real-time communications
- Uses Confluent Kafka for messaging
- Sends telemetry to Application Insights

### Azure Redis Cache
**Purpose**: Provides caching capabilities for the skills service

**Service Flow**:
- Used by Skills Container App for data caching

### Web PubSub
**Purpose**: Enables real-time communication capabilities

**Service Flow**:
- Connected to Skills Container App via private endpoint

### Container Registry
**Purpose**: Stores and manages container images

**Service Flow**:
- Provides images to Skills Container App

### Confluent Kafka
**Purpose**: Message broker for event streaming

**Service Flow**:
- Integrated with Skills Container App for messaging

## Infrastructure Network Graph

**Redis Node Storage Format**:
```
# Using Redis HASH for nodes
HSET skill.node.Skills Container App name Skills Container App type container_app
HSET skill.node.Redis Cache name Redis Cache type cache
HSET skill.node.Web PubSub name Web PubSub type pubsub
HSET skill.node.Container Registry name Container Registry type registry
HSET skill.node.Confluent Kafka name Confluent Kafka type messaging
HSET skill.node.Application Insights name Application Insights type monitoring
```

**Redis Edge Storage Format**:
```
# Using Redis HASH for edges
HSET skill.edge.0 from_node Skills Container App to_node Redis Cache relationship uses for caching
HSET skill.edge.1 from_node Skills Container App to_node Web PubSub relationship connects via private endpoint
HSET skill.edge.2 from_node Skills Container App to_node Confluent Kafka relationship uses for messaging
HSET skill.edge.3 from_node Container Registry to_node Skills Container App relationship provides images
HSET skill.edge.4 from_node Skills Container App to_node Application Insights relationship sends telemetry
```

**Redis Relationship Types Storage Format**:
```
# Using Redis SET for relationship types
SADD skill.relationship.types "uses for messaging" "uses for caching" "provides images" "sends telemetry" "connects via private endpoint"
```
