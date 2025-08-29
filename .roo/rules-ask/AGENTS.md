# Project Documentation Rules (Non-Obvious Only)

- "src/nvidia_rag/" contains Python backend code, not generic source files
- Provider examples in notebooks are the canonical reference (docs often outdated)
- UI runs in browser via RAG Playground, not traditional webview with restrictions
- Package.json scripts must be run from specific directories (frontend/ for frontend, root for python)
- Locales are handled via environment variables, not i18n files
- Vector store consistency levels controlled via `APP_VECTORSTORE_CONSISTENCYLEVEL` (not obvious from Milvus docs)
- Custom `@configclass` decorator replaces standard Python dataclasses for configuration
- Environment variable naming pattern `APP_SECTION_SETTINGNAME` is project-specific convention
- Multi-collection search requires collection name metadata tracking (not standard RAG pattern)
- VLM integration uses base64 image encoding (not file paths or URLs)
- Redis used for task status tracking in ingestor (not just caching)
- MinIO storage for multimodal content (not standard file system storage)
- Custom metadata schema storage in Milvus collections (not standard Milvus usage)
- Reflection system for response quality checking (context relevance and groundedness)
- Hybrid search requires specific Milvus configuration (dense + sparse vector fields)