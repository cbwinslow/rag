#!/usr/bin/env python3
"""Run a local ingest test by monkeypatching heavy dependencies.

Patches minimal modules so importing the project's ingestor does not
trigger heavy config parsing or external connections. Loads the
`/tmp/local_sample.ndjson` file and runs
GovernmentDataIngestor.process_and_store.
"""
import json
import os
import sys
from types import SimpleNamespace
import types

# Ensure repo root is on sys.path so 'scripts' package can be imported
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(__file__)))
if ROOT not in sys.path:
    sys.path.insert(0, ROOT)

# Create lightweight mocks for functions/classes used by gov_ingest
def fake_get_config():
    return SimpleNamespace(
        embeddings=SimpleNamespace(
            model_name="fake", server_url="http://localhost"
        )
    )

class FakeVectorStore:
    def __init__(self):
        self.added = []

    def add_documents(self, documents, collection_name=None):
        # Keep the message short to satisfy line-length checks
        print(
            f"FakeVectorStore.add_documents: {len(documents)} docs to {collection_name}"
        )
        self.added.extend(documents)

    def disconnect(self):
        """No-op disconnect for fake vectorstore used in local tests."""
        return None

def fake_create_vectorstore_langchain(_embedder):
    # embedder is unused in this fake implementation
    return FakeVectorStore()

def fake_get_embedding_model(model=None, url=None, **_kwargs):
    # Accept keyword args to match real signature; model and url are unused
    return lambda x: [0.0]

# Monkeypatch sys.modules entries before importing gov_ingest
common_module = types.SimpleNamespace()
common_module.get_config = fake_get_config
sys.modules['nvidia_rag.utils.common'] = common_module

vectorstore_module = types.SimpleNamespace()
vectorstore_module.create_vectorstore_langchain = fake_create_vectorstore_langchain
sys.modules['nvidia_rag.utils.vectorstore'] = vectorstore_module

embedding_module = types.SimpleNamespace()
embedding_module.get_embedding_model = fake_get_embedding_model
sys.modules['nvidia_rag.utils.embedding'] = embedding_module

# Note: the real import happens inside main() after monkeypatching sys.modules

def load_ndjson(path):
    docs = []
    # Explicit encoding for cross-platform consistency
    with open(path, encoding="utf-8") as f:
        for line in f:
            if line.strip():
                docs.append(json.loads(line))
    return docs

def main() -> None:
    path = '/tmp/local_sample.ndjson'
    if not os.path.exists(path):
        print(f"Sample file not found: {path}")
        sys.exit(2)
    docs = load_ndjson(path)

    # Import after the sys.modules monkeypatch so heavy runtime deps are
    # avoided
    from scripts.ingest.gov_ingest import GovernmentDataIngestor

    ingestor = GovernmentDataIngestor()
    ingestor.process_and_store(docs, collection="test_local")
    print("Local ingest test finished")


if __name__ == '__main__':
    main()
