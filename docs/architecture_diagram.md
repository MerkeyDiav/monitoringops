# Monitoring Stack Architecture — Production
# Copy this Mermaid code into https://mermaid.live

```mermaid
flowchart TD
    A[Ops Engineer<br/>MobaXterm] -->|Manual SSH| B[CyberArk Vault<br/>Password Prompt]
    B -->|Type password| C[Bastion Server<br/>Ansible Control Node]
    C -->|Ansible Playbooks| D{Target Servers}
    D -->|SSH + password| E[K8s Cluster<br/>20 nodes]
    D -->|SSH + password| F[Docker Servers<br/>5 nodes]
    E --> G[Loki + Alloy<br/>Helm / K8s]
    F --> H[Loki + Alloy<br/>Docker]
    G --> I[Push logs<br/>to Loki]
    H --> I
    I --> J[Prometheus<br/>Metrics]
    I --> K[Alertmanager<br/>Alerts]
    J --> L[Grafana<br/>Dashboards]
    K --> L

    style A fill:#f9f,stroke:#333,stroke-width:2px
    style B fill:#ff9,stroke:#333,stroke-width:3px
    style C fill:#9af,stroke:#333,stroke-width:2px
    style D fill:#f9f,stroke:#333,stroke-width:2px
    style E fill:#9f9,stroke:#333,stroke-width:1px
    style F fill:#9f9,stroke:#333,stroke-width:1px
    style I fill:#9af,stroke:#333,stroke-width:2px
    style L fill:#9af,stroke:#333,stroke-width:2px
```

## Legend

| Color | Meaning |
|-------|---------|
| Yellow | CyberArk — interactive password required |
| Blue | Working / desired state |
| Pink | User / operator |
| Green | Target servers |
| Blue (bottom) | Monitoring stack |

## Key Message for Head of Cybersecurity

> **Current state:** Ansible is blocked because every target server prompts for an interactive CyberArk password. Manual login via MobaXterm works, but deploying 30+ servers manually is not sustainable.
>
> **Requested:** Non-interactive access from the bastion — SSH key deployed via CyberArk, a service account, or a proxy configuration. The architecture, playbooks, and everything else is ready.