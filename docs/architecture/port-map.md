# AI Operations Port Map (v1.0)

| Service                | Port  | Protocol | Access    | Description                              |
|------------------------|-------|----------|-----------|------------------------------------------|
| Traefik Edge Router    | 80    | HTTP     | Public    | Main web entrypoint                      |
| Traefik Edge Router    | 443   | HTTPS    | Public    | Secure web entrypoint                    |
| Kong API Gateway       | 8000  | HTTP     | Internal  | API management and routing               |
| FastAPI Core           | 8001  | HTTP     | Internal  | Main application logic                   |
| Haystack NLP           | 8002  | HTTP     | Internal  | Question answering & search              |
| FalkorDB               | 6379  | Redis    | Internal  | Graph database operations                |
| Supabase               | 3000  | HTTP     | Public    | Authentication & database               |
| Prometheus             | 9090  | HTTP     | Internal  | Metrics collection                       |
| Grafana                | 3001  | HTTP     | Internal  | Monitoring dashboards                    |
| Loki                   | 3100  | HTTP     | Internal  | Log aggregation                          |
| OpenSearch             | 9200  | HTTP     | Internal  | Search & analytics                       |
| Sentry                 | 9000  | HTTP     | Internal  | Error tracking                           |
| Cloudflare WAF         | 8888  | HTTP     | Public    | Web application firewall                 |
| Podman API             | 8085  | HTTP     | Internal  | Container management                     |
| AI Orchestrator        | 8050  | gRPC     | Internal  | Agent coordination                       |
| Agent Healthcheck      | 8051  | HTTP     | Internal  | Agent status monitoring                  |
| Detailer Analysis      | 8060  | HTTP     | Internal  | Code insights engine                     |
| Coderabbit             | 8070  | HTTP     | Internal  | AI code reviews                          |
| Langfuse               | 8081  | HTTP     | Internal  | AI observability                         |
| Vercel Edge            | 8082  | HTTP     | Public    | Frontend hosting                         |