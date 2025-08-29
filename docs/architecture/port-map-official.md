# NVIDIA RAG Port Allocation (v2.1)

| Service                   | Port  | Protocol | Network    | Description                              |
|---------------------------|-------|----------|------------|------------------------------------------|
| **Core Services**         |       |          |            |                                          |
| RAG Server                | 8081  | HTTP     | Internal   | Main query/response endpoint             |
| Ingestor Server           | 8082  | HTTP     | Internal   | Document processing pipeline             |
| Vector Store (Milvus)     | 19530 | gRPC     | Internal   | Vector database operations               |
| **AI Orchestration**      |       |          |            |                                          |
| Agent Controller          | 8050  | gRPC     | Internal   | Autonomous agent coordination            |
| System Health Agent       | 8051  | HTTP     | Internal   | Infrastructure monitoring                |
| Log Analyst Agent         | 8052  | HTTP     | Internal   | Log pattern analysis                     |
| **Security & Auth**       |       |          |            |                                          |
| Supabase Auth             | 3000  | HTTP     | Public     | JWT authentication endpoint              |
| Cloudflare WAF            | 8888  | HTTPS    | Public     | Web application firewall                 |
| **Monitoring**            |       |          |            |                                          |
| Prometheus                | 9090  | HTTP     | Internal   | Metrics collection                       |
| Grafana                   | 3001  | HTTP     | Internal   | Monitoring dashboards                    |
| Loki                      | 3100  | HTTP     | Internal   | Log aggregation                          |
| **Utilities**             |       |          |            |                                          |
| NVIDIA Embedding Service  | 8001  | HTTP     | Internal   | Text embedding generation                |
| NVIDIA Ranking Service    | 8002  | HTTP     | Internal   | Document reranking                       |