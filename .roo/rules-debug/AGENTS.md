# Project Debug Rules (Non-Obvious Only)

- Webview dev tools accessed via RAG Playground UI at http://localhost:8090
- Vector store connections fail silently if not properly disconnected - always call `connections.disconnect()`
- Milvus GPU indexing/search can cause silent accuracy issues on B200/A100 - disable with `APP_VECTORSTORE_ENABLEGPUINDEX=False` and `APP_VECTORSTORE_ENABLEGPUSEARCH=False`
- NV-Ingest microservice takes 5-30 minutes to start first time (model download) - check health endpoint
- LLM NIM startup time varies greatly by GPU type (H100: 2-5 mins, A100: 5-10 mins, B200: 10-15 mins)
- Redis task status tracking in ingestor server - check Redis if document ingestion hangs
- MinIO storage failures for multimodal content appear as base64 encoding/decoding errors
- Milvus collection creation failures often due to metadata schema conflicts - check DEFAULT_METADATA_SCHEMA_COLLECTION
- VLM inference failures manifest as "images do not contain enough information" responses
- Environment variable mismatches between docker-compose files cause silent service connection failures
- GPU memory allocation issues in Milvus appear as "CUDA out of memory" in logs but may not crash service
- Reflection system loops can cause infinite response generation - check MAX_REFLECTION_LOOP setting