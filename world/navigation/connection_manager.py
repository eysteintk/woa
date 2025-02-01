# connection_manager.py
import os
import time
import logging
from typing import Optional, Tuple
import redis
from azure.messaging.webpubsubservice import WebPubSubServiceClient
from azure.messaging.webpubsubclient import WebPubSubClient
from azure.messaging.webpubsubclient.models import CallbackType, SendMessageError

logger = logging.getLogger(__name__)


def create_redis_client(config: dict) -> redis.Redis:
    """
    Create Redis client with built-in retry mechanism suited for storage systems.
    Redis itself has robust retry and reconnection logic that we leverage.
    """
    try:
        redis_password = os.getenv('REDIS_PASSWORD')
        if not redis_password:
            raise ValueError("❌ REDIS_PASSWORD environment variable not set")

        is_docker = os.path.exists('/.dockerenv')
        redis_host = 'host.docker.internal' if is_docker else config.get('host', '127.0.0.1')
        redis_port = config.get('port', 6380)
        redis_ssl = config.get('use_ssl', True)

        # Redis connection parameters optimized for resilience
        connection_kwargs = {
            'host': redis_host,
            'port': redis_port,
            'password': redis_password,
            'decode_responses': True,
            'socket_keepalive': True,
            'socket_connect_timeout': 5,
            'socket_timeout': 5,
            'retry_on_timeout': True,
            'retry_on_error': [redis.exceptions.ConnectionError],
            'max_connections': 10,  # Connection pool size
        }

        # Add SSL settings if enabled
        if redis_ssl:
            connection_kwargs.update({
                'ssl': True,
                'ssl_cert_reqs': None  # Don't verify SSL certificate
            })

        logger.info(f"🔌 Connecting to Redis at {redis_host}:{redis_port} (SSL: {redis_ssl})")
        client = redis.Redis(**connection_kwargs)

        # Test connection with retry
        max_attempts = 3
        for attempt in range(max_attempts):
            try:
                client.ping()
                logger.info("✅ Successfully connected to Redis")
                return client
            except redis.ConnectionError as e:
                if attempt == max_attempts - 1:
                    raise
                delay = 2 ** attempt
                logger.warning(f"Redis connection attempt {attempt + 1} failed, retrying in {delay}s: {e}")
                time.sleep(delay)

    except redis.ConnectionError as e:
        logger.error(f"❌ Redis connection error: {e}", exc_info=True)
        raise
    except Exception as e:
        logger.error(f"❌ Unexpected error creating Redis client: {e}", exc_info=True)
        raise


def create_pubsub_client(config: dict) -> Tuple[WebPubSubServiceClient, WebPubSubClient]:
    """
    Create WebPubSub clients with messaging-specific retry logic.
    WebPubSub needs different retry handling for connection vs message delivery.
    """

    def connect_with_retry(max_attempts: int = 3, base_delay: float = 2.0) -> Tuple[
        WebPubSubServiceClient, WebPubSubClient]:
        last_exception = None
        for attempt in range(max_attempts):
            try:
                # Clean connection string (common source of errors)
                connection_string = config['connection_string'].strip().strip('"').strip("'")
                hub_name = config['hub_name'].strip().strip('"').strip("'")

                logger.info(
                    f"🔌 Connecting to Web PubSub service for hub '{hub_name}' (attempt {attempt + 1}/{max_attempts})")

                service_client = WebPubSubServiceClient.from_connection_string(connection_string, hub=hub_name)

                # Get connection URL and log it for debugging (redact sensitive parts)
                client_access_info = service_client.get_client_access_token(
                    roles=["webpubsub.joinLeaveGroup", "webpubsub.sendToGroup"]
                )

                url = client_access_info["url"]
                logger.debug(f"Got WebPubSub URL: {url[:50]}...")

                # Create client with default group
                client = WebPubSubClient(url)

                return service_client, client

            except Exception as e:
                last_exception = e
                if attempt < max_attempts - 1:
                    delay = base_delay * (2 ** attempt)
                    logger.warning(f"PubSub connection attempt {attempt + 1} failed, retrying in {delay}s: {e}")
                    time.sleep(delay)
                else:
                    logger.error(f"Failed to create PubSub client after {max_attempts} attempts: {e}")
                    raise last_exception

    return connect_with_retry()