"""
GovDataIngestor - Bulk data ingestion from government sources
Supports:
- govinfo.gov/bulkdata
- congress.gov/api
"""

import os
import requests
import logging
from typing import Dict, List
from datetime import datetime
from urllib.parse import urljoin

from nvidia_rag.utils.common import get_config
from nvidia_rag.utils.vectorstore import create_vectorstore_langchain

class GovDataIngestor:
    def __init__(self):
        self.config = get_config()
        self.logger = logging.getLogger(__name__)
        
        # API endpoints
        self.govinfo_root = "https://api.govinfo.gov/"
        self.congress_root = "https://api.congress.gov/v3/"
        
        # Initialize vector store
        self.vector_store = create_vectorstore_langchain()
        
    def _get_api_key(self, service: str) -> str:
        """Get API key from environment variables"""
        key = os.getenv(f"{service.upper()}_API_KEY")
        if not key:
            self.logger.warning(f"No API key found for {service}")
        return key

    def fetch_govinfo_bulk(self, package: str) -> List[Dict]:
        """Fetch bulk data package from govinfo.gov"""
        endpoint = f"collections/{package}"
        params = {'offset': 0, 'pageSize': 1000}
        
        try:
            response = requests.get(
                urljoin(self.govinfo_root, endpoint),
                params=params,
                headers={'X-Api-Key': self._get_api_key('GOVINFO')}
            )
            response.raise_for_status()
            return response.json().get('packages', [])
        except Exception as e:
            self.logger.error(f"Failed to fetch govinfo data: {str(e)}")
            return []

    def fetch_congress_data(self, congress_type: str) -> List[Dict]:
        """Fetch legislative data from congress.gov"""
        endpoint = f"{congress_type}"
        results = []
        page = 1
        
        try:
            while True:
                response = requests.get(
                    urljoin(self.congress_root, endpoint),
                    params={'page': page},
                    headers={'X-Api-Key': self._get_api_key('CONGRESS')}
                )
                response.raise_for_status()
                
                data = response.json()
                results.extend(data.get('results', []))
                
                if not data.get('pagination', {}).get('nextPage'):
                    break
                page += 1
                
        except Exception as e:
            self.logger.error(f"Failed to fetch congress data: {str(e)}")
            
        return results

    def process_and_store(self, documents: List[Dict]) -> None:
        """Process documents and store in vector DB"""
        processed = []
        for doc in documents:
            processed.append({
                'content': self._extract_content(doc),
                'metadata': self._create_metadata(doc)
            })
            
        if processed:
            self.vector_store.add_documents(processed)
            self.logger.info(f"Stored {len(processed)} documents")

    def _extract_content(self, document: Dict) -> str:
        """Extract main content from API response"""
        # Implementation varies by source format
        return document.get('text') or document.get('content') or ''

    def _create_metadata(self, document: Dict) -> Dict:
        """Create standardized metadata"""
        return {
            'source': 'govinfo' if 'download' in document else 'congress',
            'date': document.get('dateIssued') or datetime.now().isoformat(),
            'document_id': document.get('packageId') or document.get('id'),
            'collection': document.get('collection')
        }

if __name__ == "__main__":
    ingestor = GovDataIngestor()
    
    # Example usage:
    bulk_data = ingestor.fetch_govinfo_bulk("BILLS")
    congress_data = ingestor.fetch_congress_data("bill")
    
    ingestor.process_and_store(bulk_data + congress_data)