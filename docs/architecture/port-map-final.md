# NVIDIA RAG Port Allocation (Official v2.2)

| Service                   | Port    | Protocol | Network    | Description                                |
|---------------------------|---------|----------|------------|--------------------------------------------|
| **Core RAG Services**     |         |          |            |                                            |
| RAG Query Server          | 8081    | HTTP     | Internal   | Main query endpoint                        |
| Ingestor Server           | 8082    | HTTP     | Internal   | Document processing pipeline               |
| Milvus Vector Store       | 19530   | gRPC     | Internal   | Vector similarity search                   |
| **AI Orchestration**      |         |          |            |                                            |
| Agent Controller          | 8050    | gRPC     | Internal   | Coordinates autonomous agents              |
| System Health Agent       | 8051    | HTTP     | Internal   | Infrastructure monitoring                  |
| **Security & Auth**       |         |          |            |                                            |
| Supabase Auth             | 3000    | HTTP     | Public     | JWT authentication endpoint                |
| **Monitoring**            |         |          |            |                                            |
| Prometheus                | 9090    | HTTP     | Internal   | Metrics collection                         |
| Grafana                   | 3001    | HTTP     | Internal   | Monitoring dashboards                      |
| Loki                      | 3100    | HTTP     | Internal   | Log aggregation                            |
| **NVIDIA Services**       |         |          |            |                                            |
| NIM LLM Endpoint          | 8000    | HTTP     | Internal   | Large language model inference             |
| Nemotron Embedding        | 8001    | HTTP     | Internal   | Text embedding service                     |
| Nemotron Reranking        | 8002    | HTTP     | Internal   | Document reranking service                 |