from pathlib import Path
from typing import Dict, List

def build_folder_analysis_prompt(folder_path: Path, code_map: Dict[str, str], repo_path: Path) -> str:
    """
    Summaries for each code file, to produce exactly one doc (RESULT or RESULT_STRUCTURE).
    Incorporates new headings: Use Cases, Data Flow, Edge Cases, Testing, Domain Relevance, etc.
    Also adds 'Technology & Architecture' heading for the LLM to list relevant tech details.
    """
    rel_folder = str(folder_path.relative_to(repo_path))

    code_listing = []
    for fname, content in code_map.items():
        snippet = content[:300].replace('```', '---')
        code_listing.append(f"File: {fname}\n```ts\n{snippet}...\n```\n")

    code_text = "\n".join(code_listing)

    return f"""You are analyzing the folder: {rel_folder}.
Below are partial contents of each code file in this folder.

{code_text}

Produce exactly ONE doc in JSON form:
{{
  "fileAnalysis": "...",
  "missingDocuments": [
    {{
      "docType": "RESULT or RESULT_STRUCTURE",
      "fileName": "RESULT_<folderName>.ai-generated.md or RESULT_STRUCTURE_<folderName>.ai-generated.json",
      "suggestedContent": "..."
    }}
  ],
  "references": {{
    "microservices": [],
    "infrastructure": [],
    "domainKnowledge": []
  }}
}}

If docType=RESULT => minimal markdown with headings:
# Overview
# Code Files
# Use Cases & User Stories
# Data Flow & Edge Cases
# Implementation & Domain Relevance
# External Dependencies
# Technology & Architecture
# Testing Scenarios

If docType=RESULT_STRUCTURE => minimal JSON structure:
{{
  "folderName": "...",
  "description": "...",
  "lastUpdated": "ISO8601 time",
  "files": [
    {{
      "fileName": "...",
      "imports": [...],
      "functions": [
        {{
          "name": "...",
          "signature": "...",
          "description": "short doc comment"
        }}
      ],
      "classes": [...],
      "dependencies": [...]
    }}
  ]
}}

Return ONLY that JSON, no extra text.
"""


def build_compiled_prompt(parent_folder: Path, subfolders: List[str]) -> str:
    """
    If we have subfolders, produce a COMPILED or COMPILED_STRUCTURE doc in the parent.
    Incorporates new headings like Module Boundaries, Performance & Resource, Domain Relevance, etc.
    """
    rel_parent = str(parent_folder)
    listing = "\n".join(f"- {sf}" for sf in subfolders)

    return f"""We have a parent folder: {rel_parent}
It has subfolders, each with a single doc (RESULT/STRUCTURE).
Subfolders:
{listing}

We want EXACTLY ONE doc in JSON form:
{{
  "fileAnalysis": "...",
  "missingDocuments": [
    {{
      "docType": "COMPILED or COMPILED_STRUCTURE",
      "fileName": "COMPILED_<folderName>.ai-generated.md or COMPILED_STRUCTURE_<folderName>.ai-generated.json",
      "suggestedContent": "..."
    }}
  ],
  "references": {{
    "microservices": [],
    "infrastructure": [],
    "domainKnowledge": []
  }}
}}

If docType=COMPILED => minimal markdown with headings:
# Overview
# Subfolder Summaries
# Module Boundaries & Integration
# Performance & Resource Management
# Error Handling & Security
# Domain/Business Relevance

If docType=COMPILED_STRUCTURE => minimal JSON referencing subfolders, including any constraints or architecture details.

Return ONLY that JSON, no extra text.
"""

