# Project Architecture Rules (Non-Obvious Only)

- Dual-server pattern is mandatory: RAG server (query/response) + Ingestor server (document processing) cannot be merged
- Milvus vector database with GPU acceleration is hard requirement (no CPU-only option for production)
- NV-Ingest microservice is required for document extraction - cannot be replaced with simple file parsing
- Redis dependency is mandatory for ingestor server task status tracking (not optional caching)
- MinIO storage is required for multimodal content (base64 encoded images) - cannot use filesystem
- Custom `@configclass` decorator creates tight coupling between configuration fields and environment variables
- Vector store consistency levels must be "Strong" for production (not "Bounded" or "Session")
- Environment variable naming pattern `APP_SECTION_SETTINGNAME` creates hidden coupling between services
- Multi-collection search requires collection name metadata tracking in ALL document operations
- VLM integration requires base64 image encoding/decoding pipeline (cannot use direct file access)
- Reflection system creates dependency loops that must be controlled with MAX_REFLECTION_LOOP
- Hybrid search requires both dense and sparse vector fields in Milvus schema (not optional)
- Custom metadata schema storage in Milvus collections creates coupling between ingestion and retrieval
- Milvus GPU indexing/search settings create hardware-specific deployment constraints
- NeMo Guardrails integration points are hardcoded in prompt templates (cannot be easily removed)