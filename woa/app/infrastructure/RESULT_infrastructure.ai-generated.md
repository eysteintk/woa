# Infra Analysis for Script: woa\app\infrastructure\infrastructure-prod.sh

## Overview

Main cloud services used:

- Static Web App
- Front Door
- Application Insights

## Cloud Information

Services run on Azure cloud infrastructure.

## Resource Info

- **Resource Group**: abs-rg-we-prod
- **Location**: westeurope

## Monitoring Info

Uses Log Analytics workspace and Application Insights with diagnostic settings for Static Web App and Front Door metrics/logs

## Services

### Static Web App
**Purpose**: Hosts the web application frontend

**Service Flow**:
- Exposed via Front Door
- Sends telemetry to Application Insights

### Front Door
**Purpose**: Provides global load balancing and security layer for the web application

**Service Flow**:
- Routes traffic to Static Web App
- Applies security headers
- Enforces HTTPS

### Application Insights
**Purpose**: Provides application monitoring and telemetry

**Service Flow**:
- Collects data from Static Web App
- Stores data in Log Analytics workspace

### Log Analytics
**Purpose**: Central logging and monitoring storage

**Service Flow**:
- Receives diagnostics from Static Web App
- Receives diagnostics from Front Door
- Stores Application Insights data

## Infrastructure Network Graph

**Redis Node Storage Format**:
```
# Using Redis HASH for nodes
HSET woa.node.Static Web App name Static Web App type hosting
HSET woa.node.Front Door name Front Door type cdn
HSET woa.node.Application Insights name Application Insights type monitoring
HSET woa.node.Log Analytics name Log Analytics type logging
```

**Redis Edge Storage Format**:
```
# Using Redis HASH for edges
HSET woa.edge.0 from_node Front Door to_node Static Web App relationship routes traffic
HSET woa.edge.1 from_node Static Web App to_node Application Insights relationship sends telemetry
HSET woa.edge.2 from_node Application Insights to_node Log Analytics relationship stores data
HSET woa.edge.3 from_node Static Web App to_node Log Analytics relationship sends diagnostics
HSET woa.edge.4 from_node Front Door to_node Log Analytics relationship sends diagnostics
```

**Redis Relationship Types Storage Format**:
```
# Using Redis SET for relationship types
SADD woa.relationship.types "stores data" "sends telemetry" "sends diagnostics" "routes traffic"
```
