# Server Port Map & Service Allocation

| Service                | Port  | Purpose                          | Network Group |
|------------------------|-------|----------------------------------|---------------|
| Traefik (Edge Router)  | 80    | HTTP traffic                     | public        |
| Traefik (Edge Router)  | 443   | HTTPS traffic                    | public        |
| Kong API Gateway       | 8000  | API routing/mgmt                 | internal      |
| FastAPI                | 8001  | Core application logic           | internal      |
| Haystack               | 8002  | NLP/ML pipelines                 | internal      |
| FalkorDB               | 6379  | Graph database                   | internal      |
| Supabase               | 3000  | Auth & realtime DB               | public        |
| Prometheus             | 9090  | Metrics monitoring               | internal      |
| Grafana                | 3001  | Dashboards                       | internal      |
| Loki                   | 3100  | Log aggregation                  | internal      |
| OpenSearch             | 9200  | Search/analytics                 | internal      |
| Sentry                 | 9000  | Error tracking                   | internal      |
| Cloudflare WAF         | 8888  | Web application firewall         | public        |
| Coderabbit             | 8080  | Code analysis                    | internal      |
| Podman API             | 8085  | Container management             | internal      |
| Agent Orchestrator     | 8050  | AI control plane                 | internal      |
| Detailer               | 8060  | Code analysis                    | internal      |