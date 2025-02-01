import logging
import json
import sys
from pathlib import Path
from typing import List
import click
from types import ContextSummary, FileAnalysisResult, DocumentType
from config import APIConfig, FileConfig, CONFIG
from gitignore import load_gitignore, should_ignore
from file_tracker import (
    FileTrackerData,
    init_file_tracker,
    record_analysis
)
from analyzer import (
    AnalyzerData,
    analyze_folder,
    analyze_compiled
)
from file_handler import create_or_update_document
from types import LLMAnalysis

logger = logging.getLogger(__name__)

def setup_logging():
    logging.basicConfig(
        level=CONFIG['logging']['level'],
        format=CONFIG['logging']['format'],
        filename=CONFIG['logging']['filename']
    )
    console = logging.StreamHandler(sys.stdout)
    console.setLevel(logging.INFO)
    formatter = logging.Formatter('%(asctime)s - %(levelname)s - %(message)s')
    logging.getLogger().addHandler(console)

def process_folder(
    folder_path: Path,
    repo_path: Path,
    analyzer: AnalyzerData,
    tracker: FileTrackerData
) -> None:
    """One doc (RESULT or RESULT_STRUCTURE) for the code in this folder."""
    analysis_result = analyze_folder(analyzer, folder_path, repo_path)
    if not analysis_result:
        return
    analysis = analysis_result['analysis']
    for doc in analysis.missing_documents:
        if doc.doc_type in (DocumentType.RESULT, DocumentType.RESULT_STRUCTURE):
            success = create_or_update_document(doc, folder_path, repo_path, tracker)
            if success:
                doc_path = folder_path / doc.file_name
                record_analysis(tracker, doc_path)

def process_compiled(
    folder_path: Path,
    repo_path: Path,
    analyzer: AnalyzerData,
    tracker: FileTrackerData
) -> None:
    """
    If folder_path has subfolders, produce COMPILED or COMPILED_STRUCTURE doc merging them.
    """
    subdirs = []
    for c in folder_path.iterdir():
        if c.is_dir() and not should_ignore(c, repo_path, None):
            subdirs.append(c.name)
    if not subdirs:
        return

    analysis_result = analyze_compiled(analyzer, folder_path, subdirs)
    if not analysis_result:
        return
    analysis = analysis_result['analysis']
    for doc in analysis.missing_documents:
        if doc.doc_type in (DocumentType.COMPILED, DocumentType.COMPILED_STRUCTURE):
            success = create_or_update_document(doc, folder_path, repo_path, tracker)
            if success:
                doc_path = folder_path / doc.file_name
                record_analysis(tracker, doc_path)

@click.command()
@click.option('--repo-path', type=click.Path(exists=True), required=True)
@click.option('--provider', type=str, default="anthropic", help='Which LLM provider to use: anthropic or openai')
@click.option('--anthropic-key', required=False, help='Anthropic API key')
@click.option('--openai-key', required=False, help='OpenAI API key')
@click.option('--model', default="claude-3-5-sonnet-20241022", help='LLM model name')
@click.option('--output-file', default='context_summary.json')
def main(repo_path, provider, anthropic_key, openai_key, model, output_file):
    """
    BFS over your repo:
      - For each folder, produce one doc (RESULT or RESULT_STRUCTURE).
      - If folder has subfolders, produce COMPILED or COMPILED_STRUCTURE.
    """
    setup_logging()
    repo_p = Path(repo_path).resolve()

    # Decide which key to use based on provider
    llm_key = anthropic_key if provider.lower() == "anthropic" else openai_key
    if not llm_key:
        logger.error("No API key provided for selected provider.")
        sys.exit(1)

    api_config = APIConfig(provider=provider, api_key=llm_key, model=model)
    file_config = FileConfig()
    analyzer = AnalyzerData(api_config=api_config, file_config=file_config)
    tracker = init_file_tracker(repo_p)

    summary = ContextSummary(repo_path=str(repo_p), analysis=[])
    pathspec = load_gitignore(repo_p)

    # BFS over all subdirs
    stack = [repo_p]
    while stack:
        current = stack.pop()
        if not current.is_dir():
            continue
        if should_ignore(current, repo_p, pathspec):
            continue

        # process single doc for this folder
        process_folder(current, repo_p, analyzer, tracker)
        # then produce compiled if it has subfolders
        process_compiled(current, repo_p, analyzer, tracker)

        # queue subdirs
        subdirs = [
            d for d in current.iterdir()
            if d.is_dir() and not should_ignore(d, repo_p, pathspec)
        ]
        stack.extend(subdirs)

    # Save final summary if needed
    summary_file = repo_p / output_file
    summary_file.write_text(json.dumps(summary, default=lambda x: x.__dict__, indent=2), encoding='utf-8')
    logger.info(f"Summary saved to {summary_file}")

if __name__ == '__main__':
    main()
