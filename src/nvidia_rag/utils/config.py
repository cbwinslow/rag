from functools import wraps
from pydantic import BaseModel, Field, validator
from typing import Any, Type, TypeVar
import os
import logging

logger = logging.getLogger(__name__)

T = TypeVar('T', bound='BaseModel')

def configclass(cls: Type[T]) -> Type[T]:
    """Custom decorator to enhance configuration classes with environment variable loading"""
    @wraps(cls, updated=())
    class ConfigWrapper(cls):  # type: ignore
        class Config:
            env_prefix = 'APP_'
            case_sensitive = False
            validate_all = True
            extra = 'ignore'

        @classmethod
        def get(cls) -> T:
            """Load config with environment variable overrides"""
            # Instantiate the class so __init__ runs and picks up env vars
            return cls()
            
        def __init__(self, **data: Any):
            env_data = {}
            # Iterate over the class-level fields to support multiple Pydantic versions.
            cls_fields = getattr(type(self), '__fields__', {})
            for name, field in cls_fields.items():
                # Try to extract 'env_name' from known metadata locations safely.
                env_name = None
                # Pydantic v1: ModelField has .field_info.extra
                field_info = getattr(field, 'field_info', None)
                if field_info is not None and getattr(field_info, 'extra', None):
                    env_name = field_info.extra.get('env_name')

                # Pydantic v2: FieldInfo may expose json_schema_extra
                if env_name is None:
                    json_extra = getattr(field, 'json_schema_extra', None)
                    if json_extra and isinstance(json_extra, dict):
                        env_name = json_extra.get('env_name')

                # Fall back to convention if not specified
                if not env_name:
                    env_name = name.upper()

                # Prefer prefixed env var (e.g., APP_VECTORSTORE_URL), then raw env_name
                prefixed = f"{self.Config.env_prefix}{env_name}"
                if prefixed in os.environ:
                    env_data[name] = os.environ[prefixed]
                elif env_name in os.environ:
                    env_data[name] = os.environ[env_name]
            super().__init__(**{**data, **env_data})

    return ConfigWrapper

def configfield(**kwargs: Any) -> Any:
    """Custom field decorator for configuration parameters"""
    # If callers pass a `default` in kwargs, use it as the Field default.
    # Otherwise, keep the field required by using Ellipsis.
    default = kwargs.pop('default', ...)
    return Field(default, **kwargs)

@configclass
class RAGConfig(BaseModel):
    """Central configuration for RAG components"""
    vectorstore_url: str = configfield(
        env_name='VECTORSTORE_URL',
        default='https://vectorstore.opendiscourse.net',
        description='Milvus vector database endpoint'
    )
    vectorstore_consistencylevel: str = configfield(
        default='Strong',
        description='Consistency level for vector store operations',
        choices=['Strong', 'Bounded', 'Session']
    )
    llm_modelname: str = configfield(
        env_name='LLM_MODELNAME',
        default='nvidia/llama-3.3-nemotron-super-49b-v1',
        description='LLM model name for generation'
    )
    enable_guardrails: bool = configfield(
        default=False,
        description='Enable NeMo Guardrails content safety checks'
    )

    try:
        from pydantic import field_validator
        _validator_decorator = field_validator
    except ImportError:
        from pydantic import validator
        _validator_decorator = validator

    @_validator_decorator('vectorstore_consistencylevel')
    def validate_consistency(cls, v: str) -> str:  # pylint: disable=no-self-argument,e0213  # type: ignore[no-self-argument]
        """Validate that the consistency level is one of the allowed values."""
        if v not in ['Strong', 'Bounded', 'Session']:
            raise ValueError('Invalid consistency level')
        return v

def get_config() -> RAGConfig:  # type: ignore[no-any-return]
    """Get initialized configuration instance"""
    return RAGConfig()  # type: ignore[call-arg]