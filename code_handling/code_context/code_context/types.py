from dataclasses import dataclass, field
from typing import List, Dict, Optional, Union
from enum import Enum

class DocumentType(str, Enum):
    RESULT = "RESULT"
    RESULT_STRUCTURE = "RESULT_STRUCTURE"
    COMPILED = "COMPILED"
    COMPILED_STRUCTURE = "COMPILED_STRUCTURE"

@dataclass
class MissingDocument:
    doc_type: DocumentType
    file_name: str
    suggested_content: Union[str, Dict]  # The doc can be a string or a dict.

@dataclass
class References:
    microservices: List[str] = field(default_factory=list)
    infrastructure: List[str] = field(default_factory=list)
    domain_knowledge: List[str] = field(default_factory=list)

@dataclass
class LLMAnalysis:
    file_analysis: str
    missing_documents: List[MissingDocument] = field(default_factory=list)
    references: References = field(default_factory=References)

@dataclass
class FileAnalysisResult:
    folder: str
    llm_output: Union[LLMAnalysis, Dict[str, str]]

@dataclass
class ContextSummary:
    repo_path: str
    analysis: List[FileAnalysisResult] = field(default_factory=list)
    compiled_context: Optional[str] = None
