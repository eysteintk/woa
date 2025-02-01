# skills/domain/skill.py
from dataclasses import dataclass
from typing import Optional, Dict, Any, List, Tuple
from datetime import datetime
from enum import Enum

class SkillType(Enum):
    DATA_QUERY = "data_query"
    ANALYSIS = "analysis"
    TRANSFORMATION = "transformation"

@dataclass
class SkillMetadata:
    skill_id: str
    name: str
    skill_type: SkillType
    required_level: int
    cooldown_seconds: int
    last_used: Optional[datetime] = None

@dataclass
class SkillResult:
    success: bool
    data: Optional[Dict[str, Any]] = None
    error_message: Optional[str] = None
    execution_time_ms: Optional[int] = None