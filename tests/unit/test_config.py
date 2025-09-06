import os
import pytest
from unittest.mock import patch
from nvidia_rag.utils.config import RAGConfig, get_config

def test_config_defaults():
    config = RAGConfig.get()
    assert config.vectorstore_url == "http://localhost:19530"
    assert config.vectorstore_consistencylevel == "Strong"
    assert config.llm_modelname == "nvidia/llama-3.3-nemotron-super-49b-v1"
    assert config.enable_guardrails is False

def test_environment_override():
    with patch.dict(os.environ, {
        "APP_VECTORSTORE_URL": "http://test:19530",
        "APP_LLM_MODELNAME": "test/model"
    }):
        config = get_config()
        assert config.vectorstore_url == "http://test:19530"
        assert config.llm_modelname == "test/model"

def test_consistency_validation():
    with pytest.raises(ValueError):
        RAGConfig(vectorstore_consistencylevel="Invalid")

if __name__ == "__main__":
    pytest.main()