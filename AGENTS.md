# AGENTS.md

This file provides guidance to agents when working with code in this repository.

## Build/Lint/Test Commands

### Python Development
- Use `uv` for package management (Python 3.12+ required)
- Run with: `uv run python -m nvidia_rag.rag_server.main` or `uv run python -m nvidia_rag.ingestor_server.main`
- Install dependencies: `uv sync` or `uv sync --extra rag` or `uv sync --extra ingest`

### Frontend Development
- Install dependencies: `cd frontend && npm install`
- Development server: `cd frontend && npm run dev`
- Build for production: `cd frontend && npm run build`
- Linting: `cd frontend && npm run lint`
- Formatting: `cd frontend && npm run format`

### Docker Development
- Build RAG server: `docker compose -f deploy/compose/docker-compose-rag-server.yaml build`
- Build Ingestor server: `docker compose -f deploy/compose/docker-compose-ingestor-server.yaml build`
- Run with build: Add `--build` flag to docker compose up commands

## Code Style Guidelines

### Python
- Strict typing with Pydantic models for all API requests/responses
- Configuration uses custom `@configclass` and `configfield` decorators
- Environment variables follow pattern: `APP_SECTION_SETTINGNAME` (e.g., `APP_VECTORSTORE_URL`)
- Use `get_config()` for centralized configuration access
- Vector store operations require explicit connection management
- Custom validation functions in `validation.py` modules

### Frontend (Next.js/TypeScript)
- Tailwind CSS with strict class ordering enforcement
- Next.js App Router pattern with `src/app` structure
- API routes in `src/app/api` with proper typing
- Environment variables prefixed with `NEXT_PUBLIC_` for client-side access

## Critical Project Patterns

### Architecture
- Dual-server pattern: RAG server (query/response) + Ingestor server (document processing)
- Milvus vector database with GPU acceleration support
- NV-Ingest microservice for document extraction and processing
- Redis for task status tracking in ingestor server
- MinIO for storing multimodal content (base64 encoded images)

### Key Custom Utilities
- `get_config()` - Centralized configuration with environment variable overrides
- `create_vectorstore_langchain()` - Custom Milvus integration with hybrid search support
- `NvidiaRAG` and `NvidiaRAGIngestor` classes - Main orchestration logic
- Custom prompt templates in `prompt.yaml` with strict response formatting rules
- Reflection system for context relevance and response groundedness checking

### Non-Standard Approaches
- Custom `@configclass` decorator for configuration management (not standard dataclasses)
- Environment variable parsing with `env_name` parameter in config fields
- Vector store consistency levels controlled via `APP_VECTORSTORE_CONSISTENCYLEVEL`
- Custom metadata schema storage in Milvus collections
- VLM (Vision Language Model) integration with base64 image processing
- Multi-collection search with collection name metadata tracking

### Directory Structure Conventions
- `src/nvidia_rag/` - Python source code
- `frontend/` - Next.js frontend application
- `deploy/compose/` - Docker Compose configurations
- `deploy/helm/` - Kubernetes Helm charts
- `notebooks/` - Jupyter notebooks for API examples
- `docs/` - Documentation and API references

## Testing Information
- No unit tests found in codebase
- Testing done via Jupyter notebooks in `notebooks/` directory
- API testing through notebook examples: `rag_library_usage.ipynb`, `ingestion_api_usage.ipynb`
- Manual testing via RAG Playground UI at http://localhost:8090 when running locally