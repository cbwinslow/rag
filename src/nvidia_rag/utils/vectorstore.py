from pymilvus import connections, utility
from typing import Optional, Any
from langchain.vectorstores import Milvus
from nvidia_rag.utils.config import get_config
import logging

logger = logging.getLogger(__name__)

def create_vectorstore_langchain(embedding: Any, collection_name: Optional[str] = None) -> Milvus:
    """Create Milvus vector store with enhanced error handling"""
    config = get_config()
    
    try:
        logger.info(f"Connecting to Milvus at {config.vectorstore_url}")
        connections.connect(
            alias="default",
            host=config.vectorstore_url.split("://")[-1].split(":")[0],
            port=int(config.vectorstore_url.split(":")[-1])
        )
        
        collection_name_to_use = collection_name or "default_collection"
        if not utility.has_collection(collection_name_to_use):
            logger.warning(f"Collection {collection_name_to_use} not found, will be created automatically")
            
        return Milvus(
            embedding,
            collection_name=collection_name_to_use,
            connection_args={
                "host": config.vectorstore_url.split("://")[-1].split(":")[0],
                "port": config.vectorstore_url.split(":")[-1]
            },
            consistency_level=config.vectorstore_consistencylevel
        )
    except Exception as e:
        logger.error(f"Vector store connection failed: {str(e)}")
        raise RuntimeError(
            f"Failed to initialize vector store: {e.__class__.__name__}. "
            "Check connection settings and collection existence."
        ) from e

def get_vectorstore(embedding: Any, collection_name: str, url: str) -> Milvus:
    """Get vector store with connection validation"""
    try:
        store = create_vectorstore_langchain(embedding, collection_name)
        # Milvus will create collection automatically if it doesn't exist
        return store
    except Exception as e:
        logger.error(f"Vector store validation failed: {str(e)}")
        raise
