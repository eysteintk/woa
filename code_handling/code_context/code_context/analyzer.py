import logging
from dataclasses import dataclass, field
from pathlib import Path
from typing import Optional, Dict, List, Set
from config import APIConfig, FileConfig
from prompts import build_folder_analysis_prompt, build_compiled_prompt
from api import call_llm_api, parse_llm_response

logger = logging.getLogger(__name__)

@dataclass
class AnalyzerData:
    api_config: APIConfig
    file_config: FileConfig
    analyzed_folders: Set[Path] = field(default_factory=set)
    compiled_folders: Set[Path] = field(default_factory=set)

def gather_code_from_folder(folder_path: Path, file_config: FileConfig) -> Dict[str, str]:
    code_map = {}
    if not folder_path.is_dir():
        return code_map

    for f in folder_path.iterdir():
        if not f.is_file():
            continue
        if f.suffix in {'.pyc', '.pyo', '.pyd', '.so', '.dll', '.class'}:
            continue
        if 'ai-generated' in f.name.lower():
            continue
        if f.suffix in file_config.code_extensions:
            try:
                content = f.read_text(encoding='utf-8')
            except UnicodeDecodeError:
                try:
                    content = f.read_text(encoding='utf-16')
                except UnicodeDecodeError:
                    logger.warning(f"Skipping non-decodable file: {f}")
                    continue
            code_map[f.name] = content
    return code_map

def analyze_folder(analyzer: AnalyzerData, folder_path: Path, repo_path: Path) -> Optional[Dict]:
    if folder_path in analyzer.analyzed_folders:
        return None

    logger.info(f"Analyzing folder: {folder_path}")
    analyzer.analyzed_folders.add(folder_path)

    code_map = gather_code_from_folder(folder_path, analyzer.file_config)
    if not code_map:
        logger.debug(f"No code found in {folder_path}")
        return None

    prompt = build_folder_analysis_prompt(folder_path, code_map, repo_path)
    response = call_llm_api(analyzer.api_config, prompt)
    if not response:
        logger.warning(f"No LLM response for folder {folder_path}")
        return None

    analysis = parse_llm_response(response)
    if not analysis:
        logger.warning(f"Failed to parse LLM response for folder {folder_path}")
        return None

    if analysis.file_analysis or analysis.missing_documents:
        return {
            'folder': str(folder_path.relative_to(repo_path)),
            'analysis': analysis
        }

    return None

def analyze_compiled(analyzer: AnalyzerData, parent_folder: Path, subfolders: List[str]) -> Optional[Dict]:
    if parent_folder in analyzer.compiled_folders:
        return None

    analyzer.compiled_folders.add(parent_folder)
    logger.info(f"Compiling subfolders for parent folder: {parent_folder}")

    prompt = build_compiled_prompt(parent_folder, subfolders)
    response = call_llm_api(analyzer.api_config, prompt)
    if not response:
        logger.warning(f"No LLM response for compiled in {parent_folder}")
        return None

    analysis = parse_llm_response(response)
    if not analysis:
        logger.warning(f"Failed parse for compiled in {parent_folder}")
        return None

    if analysis.file_analysis or analysis.missing_documents:
        return {
            'folder': str(parent_folder),
            'analysis': analysis
        }
    return None
