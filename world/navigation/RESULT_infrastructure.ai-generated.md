# Infra Analysis for Script: world\navigation\infrastructure-prod.sh

## Overview

Main cloud services used:

- World Navigation Container App
- Azure Redis Cache
- Web PubSub
- Confluent Cloud
- Container Registry

## Cloud Information

Services run on Azure cloud infrastructure.

## Resource Info

- **Resource Group**: abs-rg-we-prod
- **Location**: westeurope

## Monitoring Info

Uses Log Analytics workspace, Application Insights, and container app diagnostics with metrics collection

## Services

### World Navigation Container App
**Purpose**: Main application container running world navigation service

**Service Flow**:
- Receives external HTTP traffic
- Connects to Redis cache
- Publishes/subscribes to Confluent Cloud topics
- Integrates with Web PubSub
- Sends telemetry to Application Insights

### Azure Redis Cache
**Purpose**: Caching service for the application

**Service Flow**:
- Used by World Navigation Container App for caching

### Web PubSub
**Purpose**: Real-time messaging and communication service

**Service Flow**:
- Connected to Container App via private endpoint

### Confluent Cloud
**Purpose**: Managed Kafka service for event streaming

**Service Flow**:
- Provides topic 'world' for Container App messaging

### Container Registry
**Purpose**: Stores and manages container images

**Service Flow**:
- Provides images to Container App

## Infrastructure Network Graph

**Redis Node Storage Format**:
```
# Using Redis HASH for nodes
HSET world.node.World Navigation App name World Navigation App type container_app
HSET world.node.Redis Cache name Redis Cache type cache
HSET world.node.Web PubSub name Web PubSub type messaging
HSET world.node.Confluent Cloud name Confluent Cloud type event_streaming
HSET world.node.Container Registry name Container Registry type registry
HSET world.node.Application Insights name Application Insights type monitoring
```

**Redis Edge Storage Format**:
```
# Using Redis HASH for edges
HSET world.edge.0 from_node World Navigation App to_node Redis Cache relationship uses for caching
HSET world.edge.1 from_node World Navigation App to_node Web PubSub relationship connects via private endpoint
HSET world.edge.2 from_node World Navigation App to_node Confluent Cloud relationship publishes/subscribes to topics
HSET world.edge.3 from_node World Navigation App to_node Application Insights relationship sends telemetry
HSET world.edge.4 from_node Container Registry to_node World Navigation App relationship provides images
```

**Redis Relationship Types Storage Format**:
```
# Using Redis SET for relationship types
SADD world.relationship.types "publishes/subscribes to topics" "uses for caching" "sends telemetry" "provides images" "connects via private endpoint"
```
