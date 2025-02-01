# sample_content.py
import json
import redis
import logging
from typing import Dict

logger = logging.getLogger(__name__)

def create_navigation_key(path: str) -> str:
    """Create consistent navigation keys"""
    return f"woa.world.navigation.{path}"

def create_metadata_key(nav_key: str) -> str:
    """Create metadata key from navigation key"""
    return f"{nav_key}.metadata"

def store_navigation_content(redis_client: redis.Redis,
                           nav_key: str,
                           content: str) -> None:
    """Store navigation content with metadata"""
    try:
        redis_client.set(nav_key, content)
        metadata_key = create_metadata_key(nav_key)
        redis_client.set(metadata_key, json.dumps([nav_key]))
        logger.info(f"Stored content and metadata for {nav_key}")
    except Exception as e:
        logger.error(f"Failed to store navigation content: {e}", exc_info=True)
        raise

def populate_initial_content(redis_client: redis.Redis) -> None:
    """Populate Redis with initial navigation and world content"""
    content_map = {
        "main.markdown.root": """# World Navigation
- [City](/woa.world.navigation.city.markdown.index)
- [Characters](/woa.world.characters.markdown.index)
- [Quests](/woa.world.quests.markdown.index)""",

        "city.markdown.index": """# Cities of the World
- [Asko Norge](/woa.world.navigation.city.markdown.asko_norge)
- [Trade Routes](/woa.world.navigation.city.markdown.trade_routes)""",

        "city.markdown.asko_norge": """# Asko Norge
A prominent northern city known for its strategic importance.

## Location
Situated in the mountainous region of the northern territories.

## Governance
Governed by a council of elected representatives.""",

        'woa.world.navigation.city.markdown.trade_routes': """# Trade Routes
Crucial economic pathways connecting major cities and regions.

## Main Routes
1. Northern Mountain Pass
2. Coastal Trade Line
3. River Valley Corridor""",

        # Characters navigation
        'woa.world.characters.markdown.index': """# Characters
- [Hero](/woa.world.characters.markdown.hero)
- [Mentor](/woa.world.characters.markdown.mentor)""",

        # Specific character content
        'woa.world.characters.markdown.hero': """# Hero Character
Name: The Protagonist
Background: A young adventurer seeking their destiny.

## Skills
- Sword Fighting
- Magic
- Survival""",

        'woa.world.characters.markdown.mentor': """# Mentor Character
Name: Wise Elder
Role: Guiding the protagonist on their journey.

## Knowledge
- Ancient Lore
- Magical Teachings
- Strategic Wisdom"""
    }

    content_metadata = {
        'woa.world.navigation.main.markdown.root.metadata': json.dumps([
            'woa.world.navigation.main.markdown.root'
        ]),
        'woa.world.navigation.city.markdown.index.metadata': json.dumps([
            'woa.world.navigation.city.markdown.index'
        ]),
        'woa.world.navigation.city.markdown.asko_norge.metadata': json.dumps([
            'woa.world.navigation.city.markdown.asko_norge'
        ]),
        'woa.world.navigation.city.markdown.trade_routes.metadata': json.dumps([
            'woa.world.navigation.city.markdown.trade_routes'
        ]),
        'woa.world.characters.markdown.index.metadata': json.dumps([
            'woa.world.characters.markdown.index'
        ]),
        'woa.world.characters.markdown.hero.metadata': json.dumps([
            'woa.world.characters.markdown.hero'
        ]),
        'woa.world.characters.markdown.mentor.metadata': json.dumps([
            'woa.world.characters.markdown.mentor'
        ])
    }

    try:
        for path, content in content_map.items():
            nav_key = create_navigation_key(path)
            store_navigation_content(redis_client, nav_key, content)

        logger.info("✅ Successfully populated initial content")
    except Exception as e:
        logger.error(f"❌ Failed to populate content: {e}", exc_info=True)
        raise