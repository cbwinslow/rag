# Project Coding Rules (Non-Obvious Only)

- Always use `get_config()` for centralized configuration access instead of direct environment variables
- Configuration classes use custom `@configclass` decorator with `configfield` (not standard dataclasses)
- Vector store connections require explicit connection management with `connections.connect()` and `connections.disconnect()`
- Custom `create_vectorstore_langchain()` function handles Milvus integration with hybrid search support
- Environment variables follow strict pattern: `APP_SECTION_SETTINGNAME` (e.g., `APP_VECTORSTORE_URL`)
- Use `NvidiaRAG` and `NvidiaRAGIngestor` classes as main orchestration entry points
- Custom prompt templates in `prompt.yaml` control all LLM response formatting
- Milvus consistency levels controlled via `APP_VECTORSTORE_CONSISTENCYLEVEL` environment variable
- VLM integration requires base64 image encoding/decoding for multimodal content
- Redis used for task status tracking in ingestor server, not just caching
- MinIO storage used for multimodal content with base64 encoding
- Custom metadata schema storage in Milvus collections requires special handling
- Multi-collection search requires collection name tracking in document metadata