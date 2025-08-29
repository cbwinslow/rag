import pytest
from gov_ingest import GovernmentDataIngestor
from unittest.mock import patch, MagicMock

@patch('gov_ingest.requests.get')
def test_fetch_govinfo_bulk(mock_get):
    """Test GovInfo API response handling"""
    mock_response = MagicMock()
    mock_response.json.return_value = {'packages': [{'packageId': 'TEST-123'}]}
    mock_get.return_value = mock_response
    
    ingestor = GovernmentDataIngestor()
    results = ingestor.fetch_govinfo_bulk("BILLS")
    
    assert len(results) == 1
    assert results[0]['packageId'] == 'TEST-123'

@patch('gov_ingest.GovernmentDataIngestor._connect_vectorstore')
def test_vectorstore_connection(mock_connect):
    """Test vector store connection management"""
    mock_connect.side_effect = Exception("Connection failed")
    
    with pytest.raises(Exception) as excinfo:
        GovernmentDataIngestor()
    
    assert "Connection failed" in str(excinfo.value)

@patch('gov_ingest.get_embedding_model')
@patch('gov_ingest.create_vectorstore_langchain')
def test_document_storage(mock_vs, mock_embed):
    """Test document processing and storage"""
    mock_vs.return_value.add_documents = MagicMock()
    
    ingestor = GovernmentDataIngestor()
    ingestor.process_and_store([{'packageId': 'TEST-456'}])
    
    mock_vs.return_value.add_documents.assert_called_once()