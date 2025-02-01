import json
import logging
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path
from typing import Dict

logger = logging.getLogger(__name__)

@dataclass
class FileTrackerData:
    """
    Tracks analysis records, storing them in .code_context/analysis_log.json
    """
    repo_path: Path
    analysis_log: Dict[str, dict] = field(default_factory=dict)
    log_file: Path = None

def init_file_tracker(repo_path: Path) -> FileTrackerData:
    tracker = FileTrackerData(repo_path=repo_path)
    tracker.log_file = repo_path / '.code_context' / 'analysis_log.json'
    if not tracker.log_file.parent.exists():
        tracker.log_file.parent.mkdir(parents=True, exist_ok=True)

    if tracker.log_file.exists():
        try:
            data = json.loads(tracker.log_file.read_text(encoding='utf-8'))
            tracker.analysis_log = data
            logger.info(f"Loaded {len(data)} analysis records from {tracker.log_file}")
        except Exception as e:
            logger.error(f"Failed to load analysis log: {e}")
            tracker.analysis_log = {}
    else:
        logger.info(f"No existing analysis log found at {tracker.log_file}, starting fresh.")

    return tracker

def save_tracker(tracker: FileTrackerData) -> None:
    try:
        content = json.dumps(tracker.analysis_log, indent=2)
        tracker.log_file.write_text(content, encoding='utf-8')
        logger.info(f"Saved {len(tracker.analysis_log)} analysis records to {tracker.log_file}")
    except Exception as e:
        logger.error(f"Failed to save analysis records: {e}")

def record_analysis(tracker: FileTrackerData, doc_path: Path) -> None:
    rel_path = str(doc_path.relative_to(tracker.repo_path))
    tracker.analysis_log[rel_path] = {
        'generated': datetime.now().isoformat()
    }
    save_tracker(tracker)

def get_analysis_log(tracker: FileTrackerData) -> dict:
    return {
        'last_updated': datetime.now().isoformat(),
        'files': tracker.analysis_log
    }
