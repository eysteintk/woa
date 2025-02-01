import logging
import json
from pathlib import Path
import datetime
from types import MissingDocument, DocumentType
from file_tracker import FileTrackerData, record_analysis

logger = logging.getLogger(__name__)

def create_or_update_document(
    doc: MissingDocument,
    base_path: Path,
    repo_path: Path,
    tracker_data: FileTrackerData
) -> bool:
    file_path = base_path / enforce_ai_generated_filename(doc.file_name, doc.doc_type)
    file_path.parent.mkdir(parents=True, exist_ok=True)

    logger.info(f"Creating {doc.doc_type} doc: {file_path}")
    try:
        if doc.doc_type in (DocumentType.RESULT, DocumentType.COMPILED):
            # interpret as markdown
            text_to_write = handle_doc_string_or_dict(doc.suggested_content)
            # Append the actual file path at the end
            text_to_write += f"\n\n**File Path**: `{file_path}`\n"
            file_path.write_text(text_to_write, encoding='utf-8')
        else:
            # docType = RESULT_STRUCTURE or COMPILED_STRUCTURE => JSON
            parsed = convert_to_dict(doc.suggested_content)
            if "lastUpdated" not in parsed:
                parsed["lastUpdated"] = datetime.datetime.utcnow().isoformat() + "Z"
            # Also store the path in the JSON itself
            parsed["filePath"] = str(file_path)

            doc_content = json.dumps(parsed, indent=2)
            file_path.write_text(doc_content, encoding='utf-8')

        return True
    except Exception as e:
        logger.error(f"Failed to write doc {file_path}: {e}", exc_info=True)
        return False

def handle_doc_string_or_dict(content):
    """If LLM returns dict but we want markdown, fallback to JSON text."""
    if isinstance(content, dict):
        logger.warning("Expected markdown but got dict, converting to JSON fallback.")
        return json.dumps(content, indent=2)
    return str(content)

def convert_to_dict(content):
    """If content is dict, use it. Else parse from JSON string."""
    if isinstance(content, dict):
        return content
    return json.loads(str(content))

def enforce_ai_generated_filename(file_name: str, doc_type: DocumentType) -> str:
    """
    If docType=RESULT => .md, docType=RESULT_STRUCTURE => .json, etc.
    Insert .ai-generated. into the filename if missing.
    """
    lower = file_name.lower()
    if doc_type in (DocumentType.RESULT, DocumentType.COMPILED):
        # must end with .md
        if not lower.endswith('.md'):
            file_name = file_name.rsplit('.', 1)[0] + '.md'
        if '.ai-generated.' not in lower:
            idx = file_name.rfind('.md')
            file_name = file_name[:idx] + '.ai-generated' + file_name[idx:]
    else:
        # structure => .json
        if not lower.endswith('.json'):
            file_name = file_name.rsplit('.', 1)[0] + '.json'
        if '.ai-generated.' not in lower:
            idx = file_name.rfind('.json')
            file_name = file_name[:idx] + '.ai-generated' + file_name[idx:]
    return file_name
