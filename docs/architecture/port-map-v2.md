# AI Operations Port Map (v2.0) - Official Standard

| Service                | Port  | Protocol | Network    | Description                              |
|------------------------|-------|----------|------------|------------------------------------------|
| **Edge Services**      |       |          |            |                                          |
| Traefik Router         | 80    | HTTP     | Public     | Primary web entrypoint                   |
| Traefik Router         | 443   | HTTPS    | Public     | Secure endpoint with auto-renewing SSL   |
| Cloudflare WAF         | 8888  | HTTPS    | Public     | Web application firewall                 |
| **Core Services**      |       |          |            |                                          |
| FastAPI Orchestrator   | 8050  | HTTP/2   | Internal   | AI agent coordination center             |
| Haystack NLP           | 8002  | HTTP     | Internal   | Document processing pipelines            |
| FalkorDB               | 6379  | Redis    | Internal   | Graph relationships storage              |
| Supabase Auth          | 3000  | HTTP     | Public     | JWT authentication endpoint              |
| **Monitoring**         |       |          |            |                                          |
| Prometheus             | 9090  | HTTP     | Internal   | Metrics collection                       |
| Grafana                | 3001  | HTTP     | Internal   | Visualization dashboard                   |
| Loki                   | 3100  | HTTP     | Internal   | Distributed logging                      |
| **AI Agents**          |       |          |            |                                          |
| System Health Agent    | 8051  | gRPC     | Internal   | Infrastructure monitoring                |
| File Optimizer         | 8052  | gRPC     | Internal   | Storage management                       |
| Log Analyst            | 8053  | gRPC     | Internal   | Log pattern detection                    |
| **Utilities**          |       |          |            |                                          |
| Podman API             | 8085  | HTTP     | Internal   | Container management                     |
| Vercel Edge            | 8082  | HTTP     | Public     | Frontend hosting                         |
| Langfuse               | 8081  | HTTP     | Internal   | AI observability                         |