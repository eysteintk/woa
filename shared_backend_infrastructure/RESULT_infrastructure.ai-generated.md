# Infra Analysis for Script: shared_backend_infrastructure\infrastructure-prod.sh

## Overview

Main cloud services used:

- Redis Cache
- Container Registry
- Container Apps Environment
- Confluent Kafka

## Cloud Information

Services run on Azure cloud infrastructure.

## Resource Info

- **Resource Group**: abs-rg-we-prod
- **Location**: westeurope

## Monitoring Info

Uses Log Analytics workspace for VNET, Redis, ACR diagnostics, NSG flow logs, and container app logging

## Services

### Virtual Network
**Purpose**: Core network infrastructure with private endpoints and container subnets

**Service Flow**:
- Provides network isolation
- Hosts private endpoints for Redis and ACR
- Contains container subnet for Container Apps

### Redis Cache
**Purpose**: Managed Redis cache service with private access

**Service Flow**:
- Accessible via private endpoint
- Connected to Log Analytics for monitoring
- Used by applications for caching

### Container Registry
**Purpose**: Private container image repository with vulnerability scanning

**Service Flow**:
- Accessible via private endpoint
- Used by Container Apps environment
- Stores application container images

### Container Apps Environment
**Purpose**: Managed container hosting platform

**Service Flow**:
- Runs in dedicated subnet
- Pulls images from ACR
- Sends logs to Log Analytics

### Confluent Kafka
**Purpose**: Managed Kafka messaging service

**Service Flow**:
- Exports metrics to Azure Monitor
- Provides messaging backbone for applications

## Infrastructure Network Graph

**Redis Node Storage Format**:
```
# Using Redis HASH for nodes
HSET shared_backend_infrastructure.node.Virtual Network name Virtual Network type network
HSET shared_backend_infrastructure.node.Redis Cache name Redis Cache type cache
HSET shared_backend_infrastructure.node.Container Registry name Container Registry type registry
HSET shared_backend_infrastructure.node.Container Apps name Container Apps type compute
HSET shared_backend_infrastructure.node.Confluent Kafka name Confluent Kafka type messaging
HSET shared_backend_infrastructure.node.Log Analytics name Log Analytics type monitoring
```

**Redis Edge Storage Format**:
```
# Using Redis HASH for edges
HSET shared_backend_infrastructure.edge.0 from_node Container Apps to_node Container Registry relationship pulls images
HSET shared_backend_infrastructure.edge.1 from_node Container Apps to_node Log Analytics relationship sends logs
HSET shared_backend_infrastructure.edge.2 from_node Redis Cache to_node Log Analytics relationship sends metrics
HSET shared_backend_infrastructure.edge.3 from_node Container Registry to_node Log Analytics relationship sends metrics
HSET shared_backend_infrastructure.edge.4 from_node Confluent Kafka to_node Log Analytics relationship sends metrics
HSET shared_backend_infrastructure.edge.5 from_node Container Apps to_node Virtual Network relationship runs in subnet
HSET shared_backend_infrastructure.edge.6 from_node Redis Cache to_node Virtual Network relationship private endpoint
```

**Redis Relationship Types Storage Format**:
```
# Using Redis SET for relationship types
SADD shared_backend_infrastructure.relationship.types "pulls images" "runs in subnet" "sends metrics" "sends logs" "private endpoint"
```
