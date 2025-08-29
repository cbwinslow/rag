"""
Government Document Ingestor - Handles bulk data from govinfo.gov and congress.gov
"""

import os
import logging
import requests
import time
from typing import List, Dict, Optional
from datetime import datetime
from urllib.parse import urljoin
import json

from nvidia_rag.utils.common import get_config
from nvidia_rag.utils.vectorstore import create_vectorstore_langchain
from nvidia_rag.utils.embedding import get_embedding_model

class GovernmentDataIngestor:
    def __init__(self):
        self.config = get_config()
        self.logger = logging.getLogger(__name__)
        self.vector_store = None
        self._connect_vectorstore()

    def _connect_vectorstore(self):
        """Initialize and connect to vector store with retries and proper cleanup"""
        max_retries = 3
        for attempt in range(max_retries):
            try:
                document_embedder = get_embedding_model(
                    model=self.config.embeddings.model_name,
                    url=self.config.embeddings.server_url
                )
                self.vector_store = create_vectorstore_langchain(document_embedder)
                self.logger.info(f"Connected to vector store successfully (attempt {attempt+1})")
                return
            except Exception as e:
                self.logger.error(f"Connection attempt {attempt+1} failed: {str(e)}")
                if attempt == max_retries - 1:
                    raise RuntimeError(f"Failed to connect after {max_retries} attempts") from e
                time.sleep(2 ** attempt)  # Exponential backoff
            finally:
                if hasattr(self.vector_store, 'disconnect'):
                    try:
                        self.vector_store.disconnect()
                        self.logger.debug("Successfully disconnected from vector store")
                    except Exception as e:
                        self.logger.error("Error disconnecting from vector store: %s", e, exc_info=True)

    def _get_api_key(self, service: str) -> str:
        """Get API key from environment variables with validation"""
        key = os.getenv(f"{service.upper()}_API_KEY")
        if not key:
            raise ValueError(f"Missing {service.upper()}_API_KEY environment variable")
        return key

    def fetch_govinfo_bulk(self, package: str) -> List[Dict]:
        """Fetch bulk data from govinfo.gov with error handling and pagination"""
        results = []
        page_size = 1000
        offset = 0
        
        try:
            while True:
                response = requests.get(
                    f"https://api.govinfo.gov/collections/{package}",
                    params={'offset': offset, 'pageSize': page_size},
                    headers={'X-Api-Key': self._get_api_key('GOVINFO')},
                    timeout=30
                )
                response.raise_for_status()
                
                data = response.json()
                results.extend(data.get('packages', []))
                
                if len(data.get('packages', [])) < page_size:
                    break
                    
                offset += page_size
                
        except Exception as e:
            self.logger.error(f"GovInfo API error: {str(e)}")
            raise
            
        return results

    def process_and_store(self, documents: List[Dict], collection: str = "government_docs") -> None:
        """Process and store documents with metadata following project schema"""
        if not self.vector_store:
            raise ConnectionError("Vector store not initialized")

        processed = []
        error_count = 0
        for doc in documents:
            try:
                processed.append({
                    'page_content': self._extract_content(doc),
                    'metadata': self._create_metadata(doc)
                })
            except Exception as e:
                error_count += 1
                self.logger.error(f"Error processing document {doc.get('packageId')}: {str(e)}", exc_info=True)

        try:
            if processed:
                self.vector_store.add_documents(
                    documents=processed,
                    collection_name=collection
                )
                self.logger.info(f"Successfully stored {len(processed)} documents in {collection}")
                if error_count > 0:
                    self.logger.warning(f"Skipped {error_count} documents due to processing errors")
            else:
                self.logger.warning("No valid documents to store")
        except Exception as e:
            self.logger.error(f"Failed to store documents: {str(e)}", exc_info=True)
            raise
        finally:
            if hasattr(self.vector_store, 'disconnect'):
                self.vector_store.disconnect()

    def _extract_content(self, document: Dict) -> str:
        """Extract content using project-standard formatting"""
        return json.dumps({
            'text': document.get('text'),
            'summary': document.get('summary'),
            'title': document.get('title')
        })

    def _create_metadata(self, document: Dict) -> Dict:
        """Create metadata following project's DEFAULT_METADATA_SCHEMA_COLLECTION"""
        return {
            'source': 'govinfo',
            'date': document.get('dateIssued') or datetime.now().isoformat(),
            'document_id': document.get('packageId'),
            'url': document.get('detailsLink', ''),
            'collection': document.get('collection')
        }

if __name__ == "__main__":
    ingestor = GovernmentDataIngestor()
    bills = ingestor.fetch_govinfo_bulk("BILLS")
    ingestor.process_and_store(bills)