from pathlib import Path
from typing import Optional
import logging
from pathspec import PathSpec
from pathspec.patterns import GitWildMatchPattern

logger = logging.getLogger(__name__)

def load_gitignore(repo_path: Path) -> Optional[PathSpec]:
    """Load and compile .gitignore patterns."""
    gitignore_path = repo_path / '.gitignore'

    try:
        if gitignore_path.exists():
            with open(gitignore_path, 'r', encoding='utf-8') as f:
                patterns = []
                for line in f:
                    line = line.strip()
                    if line and not line.startswith('#'):
                        if not line.startswith('/'):
                            line = f"**/{line}"
                        patterns.append(line)

            logger.info(f"Loaded {len(patterns)} patterns from {gitignore_path}")
            return PathSpec.from_lines(GitWildMatchPattern, patterns)
        return None
    except Exception as e:
        logger.error(f"Error loading .gitignore: {e}")
        return None

def should_ignore(path: Path, repo_path: Path, pathspec: Optional[PathSpec]) -> bool:
    """Check if a path should be ignored based on .gitignore rules."""
    if not pathspec:
        return False

    try:
        rel_path = path.relative_to(repo_path)
        rel_path_str = str(rel_path).replace('\\', '/')

        # Ignore dotfiles
        if any(part.startswith('.') for part in rel_path.parts):
            logger.debug(f"Ignoring dotfile/directory: {rel_path}")
            return True

        # gitignore patterns
        matched = pathspec.match_file(rel_path_str)
        if matched:
            logger.debug(f"Path {rel_path} matched gitignore pattern")

        return matched

    except Exception as e:
        logger.error(f"Error checking ignore status for {path}: {e}")
        return False
