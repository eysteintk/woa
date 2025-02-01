# content_manager.py
import json
import logging
import time
import uuid
from typing import Dict, List, Optional
import redis
from azure.messaging.webpubsubservice import WebPubSubServiceClient
from azure.messaging.webpubsubclient.models import SendMessageError

logger = logging.getLogger(__name__)

MAX_DELIVERY_ATTEMPTS = 3
ROOT_NAV_KEY = "woa.world.navigation.main.markdown.root"


def store_system_event(redis_client: redis.Redis, event_type: str, connection_id: str, data: dict) -> None:
    """Store system events with TTL"""
    try:
        event_key = f"woa.system.events.{event_type}.{connection_id}"
        event_data = {
            "timestamp": time.time(),
            "connection_id": connection_id,
            **data
        }
        # Store event with 24h TTL
        redis_client.setex(event_key, 86400, json.dumps(event_data))
        logger.info(f"Stored system event: {event_type} for connection {connection_id}")
    except Exception as e:
        logger.error(f"Failed to store system event: {e}", exc_info=True)


def get_navigation_content(redis_client: redis.Redis, nav_key: str = ROOT_NAV_KEY) -> Optional[str]:
    """Get navigation content without using wildcards"""
    try:
        metadata_key = f"{nav_key}.metadata"
        metadata = redis_client.get(metadata_key)

        if not metadata:
            return None

        section_keys = json.loads(metadata)
        sections = []

        for section_key in section_keys:
            content = redis_client.get(section_key)
            if content:
                sections.append(content)

        return "\n\n".join(sections) if sections else None
    except Exception as e:
        logger.error(f"Failed to get navigation content: {e}", exc_info=True)
        return None


def handle_navigation_event(redis_client: redis.Redis,
                            pubsub_service: WebPubSubServiceClient,
                            content: str,
                            connection_id: str) -> None:
    """Handle navigation events with retry logic"""
    try:
        message = json.loads(content)
        if not all(key in message for key in ['type', 'filename']):
            logger.error("Invalid navigation event format")
            return

        nav_key = message['filename']
        content = get_navigation_content(redis_client, nav_key)

        if not content:
            logger.warning(f"No content found for {nav_key}")
            return

        for attempt in range(MAX_DELIVERY_ATTEMPTS):
            try:
                response = {
                    "type": "markdown_content",
                    "filename": nav_key,
                    "content": content
                }
                pubsub_service.send_to_connection(connection_id, json.dumps(response))
                logger.info(f"Sent navigation response for {nav_key}")
                break
            except SendMessageError as e:
                if attempt == MAX_DELIVERY_ATTEMPTS - 1:
                    raise
                delay = 1 * (2 ** attempt)
                logger.warning(f"Message delivery attempt {attempt + 1} failed, retrying in {delay}s: {e}")
                time.sleep(delay)

    except Exception as e:
        logger.error(f"Error in handle_navigation_event: {e}", exc_info=True)


def handle_connect_event(redis_client: redis.Redis,
                         pubsub_service: WebPubSubServiceClient,
                         connection_id: str,
                         user_data: Optional[dict] = None) -> None:
    """Handle client connection with initial navigation load"""
    try:
        # Store connection event
        store_system_event(redis_client, "connect", connection_id, user_data or {})

        # Get root navigation content
        content = get_navigation_content(redis_client)

        if not content:
            logger.error("Failed to get root navigation content")
            return

        for attempt in range(MAX_DELIVERY_ATTEMPTS):
            try:
                response = {
                    "type": "initial_navigation",
                    "content": content
                }
                pubsub_service.send_to_connection(connection_id, json.dumps(response))
                logger.info("Sent initial navigation content")
                break
            except SendMessageError as e:
                if attempt == MAX_DELIVERY_ATTEMPTS - 1:
                    raise
                delay = 1 * (2 ** attempt)
                logger.warning(f"Connect message delivery attempt {attempt + 1} failed, retrying in {delay}s: {e}")
                time.sleep(delay)

    except Exception as e:
        logger.error(f"Error in handle_connect_event: {e}", exc_info=True)


def handle_disconnect_event(redis_client: redis.Redis, connection_id: str) -> None:
    """Handle client disconnection"""
    try:
        store_system_event(redis_client, "disconnect", connection_id, {})
    except Exception as e:
        logger.error(f"Error in handle_disconnect_event: {e}", exc_info=True)