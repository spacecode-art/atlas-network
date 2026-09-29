# Packet Flows

## 1. Hub → Dev (allowed)

```mermaid
sequenceDiagram
    participant H as Hub subnet (10.100.10.x)
    participant HRT as Hub private RT
    participant TGW as Transit Gateway
    participant TRT as TGW rtb-hub
    participant D as Dev subnet (10.101.10.x)
    H->>HRT: dst 10.101.x.x
    HRT->>TGW: route 10.101.0.0/16 → tgw
    TGW->>TRT: lookup (attachment-hub is associated here)
    TRT->>D: 10.101.0.0/16 propagated from attach-dev
```

## 2. Dev → Prod (blocked by design)

```mermaid
sequenceDiagram
    participant D as Dev subnet (10.101.10.x)
    participant DRT as Dev private RT
    D->>DRT: dst 10.102.x.x
    Note over DRT: only 10.100.0.0/16 → TGW and 0.0.0.0/0 → NAT exist
    DRT-->>D: no TGW route; 10.102.x.x is not private-routed to prod
    Note over DRT: even if a route existed, TGW rtb-dev has no 10.102.0.0/16 (no propagation from attach-prod)
```

## 3. Egress via NAT (Prod, per-AZ)

```mermaid
flowchart LR
    A[Private subnet az-a] --> RA[Private RT az-a<br/>0.0.0.0/0 → NAT az-a]
    RA --> NA[NAT GW az-a<br/>in public subnet az-a]
    NA --> IGW[Internet Gateway]
    B[Private subnet az-b] --> RB[Private RT az-b<br/>0.0.0.0/0 → NAT az-b]
    RB --> NB[NAT GW az-b] --> IGW
```

## 4. S3 via Interface Endpoint (Dev)

```mermaid
flowchart LR
    C[Client in dev private subnet] -->|s3.us-east-1.amazonaws.com<br/>private DNS| E[Endpoint ENI<br/>SG: 443 from 10.101.0.0/16]
    E -->|endpoint policy: GetObject, ListBucket| S3[(Amazon S3)]
```