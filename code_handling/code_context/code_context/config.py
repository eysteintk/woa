import os
from dataclasses import dataclass, field
from typing import Dict

@dataclass
class APIConfig:
    provider: str        # "anthropic" or "openai"
    api_key: str
    model: str = "claude-3-5-sonnet-20241022"
    max_tokens: int = 8192
    temperature: float = 0.2

# @dataclass
# class APIConfig:
#     provider: str        # "anthropic" or "openai"
#     api_key: str
#     model: str = "gpt-4o"    # Vi er paa en lav tier.... o1 kommer en vakker dag, o1 pro lenge etter det....
#     max_tokens: int = 100000  # Adjust based on your application's needs
#     temperature: float = 0.2             # Adjust for desired response creativity


@dataclass
class FileConfig:
    code_extensions: tuple = ('.py', '.js', '.ts', '.tsx', '.sh')
    chunk_size: int = 8000

CONFIG = {
    'logging': {
        'level': 'DEBUG',
        'format': '%(asctime)s - %(name)s - %(levelname)s - %(message)s',
        'filename': 'code_context.log'
    }
}
