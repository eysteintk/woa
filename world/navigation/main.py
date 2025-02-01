# main.py
import os
import logging
from azure.messaging.webpubsubclient import WebPubSubClient
from azure.messaging.webpubsubclient.models import CallbackType, SendMessageError
from connection_manager import create_redis_client, create_pubsub_client
from sample_content import populate_initial_content
from content_manager import handle_navigation_event, handle_connect_event, handle_disconnect_event
from contextlib import contextmanager

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)
logging.getLogger("websocket").setLevel(logging.DEBUG)
logging.getLogger("azure").setLevel(logging.DEBUG)


def load_config_from_env():
    """Load configuration from environment variables"""
    try:
        redis_config = {
            "host": os.environ['REDIS_HOST'],
            "port": int(os.environ.get('REDIS_PORT', '6380')),
            "use_managed_identity": os.environ.get('USE_MANAGED_IDENTITY', 'true').lower() == 'true',
        }
        pubsub_config = {
            "connection_string": os.environ['AZURE_WEBPUBSUB_CONNECTION_STRING'],
            "hub_name": os.environ['AZURE_WEBPUBSUB_HUB_NAME'],
        }
        return redis_config, pubsub_config
    except KeyError as e:
        logger.error(f"Missing required environment variable: {e}")
        raise
    except ValueError as e:
        logger.error(f"Invalid environment variable value: {e}")
        raise


@contextmanager
def run_redis_service(config: dict):
    """Run Redis service and handle cleanup"""
    client = None
    try:
        client = create_redis_client(config)
        if client:
            populate_initial_content(client)
        yield client
    finally:
        if client:
            client.close()
            logger.info("Redis client closed")


@contextmanager
def run_pubsub_service(config: dict, redis_client=None):
    """Run PubSub service and keep the WebSocket connection alive."""
    pubsub_client = None
    navigation_group = "navigation-events"

    try:
        service_client, pubsub_client = create_pubsub_client(config)

        def on_connected(event):
            """Handle connection events"""
            logger.info(f"✅ Connected: {event.connection_id}")
            handle_connect_event(
                redis_client=redis_client,
                pubsub_service=service_client,
                connection_id=event.connection_id,
                user_data=getattr(event, 'user_data', None)
            )

        def on_disconnected(event):
            """Handle disconnection events"""
            logger.warning(f"⚠️ Disconnected: {event.message}")
            if redis_client:
                handle_disconnect_event(
                    redis_client=redis_client,
                    connection_id=event.connection_id
                )

        def on_message(event):
            """Handles incoming group messages"""
            if redis_client:
                handle_navigation_event(
                    redis_client=redis_client,
                    pubsub_service=service_client,
                    content=event.data,
                    connection_id=event.connection_id
                )

        # Set up event handlers
        pubsub_client.subscribe(CallbackType.CONNECTED, on_connected)
        pubsub_client.subscribe(CallbackType.DISCONNECTED, on_disconnected)
        pubsub_client.subscribe(CallbackType.GROUP_MESSAGE, on_message)
        pubsub_client.subscribe(CallbackType.SERVER_MESSAGE,
                              lambda e: logger.info(f"🔵 Server message: {e.data}"))

        with pubsub_client:  # Keeps the connection open
            logger.info("🔗 WebPubSub client connection established")

            # Join group
            try:
                pubsub_client.join_group(navigation_group)
                logger.info(f"✅ Successfully joined group: {navigation_group}")
            except SendMessageError as e:
                logger.warning(f"⚠️ Initial join attempt failed, retrying...")
                try:
                    pubsub_client.join_group(navigation_group, ack_id=e.ack_id)
                    logger.info(f"✅ Joined group after retry: {navigation_group}")
                except Exception as retry_error:
                    logger.error(f"❌ Failed to join group after retry: {retry_error}")
                    raise
            except Exception as e:
                logger.error(f"❌ Failed to join group: {e}")
                raise

            logger.info("🟢 WebPubSub event loop is running...")

            while pubsub_client.is_connected():
                pass  # This ensures the process stays alive

    finally:
        if pubsub_client:
            pubsub_client.close()
            logger.info("🔌 WebPubSub client closed")


def main():
    """
    Main service orchestrator - each service runs independently
    and can be managed separately
    """
    try:
        redis_config, pubsub_config = load_config_from_env()

        with run_redis_service(redis_config) as redis_client:
            logger.info("Redis service started")

            with run_pubsub_service(pubsub_config, redis_client) as pubsub_client:
                logger.info("✅ All services started successfully")

    except Exception as e:
        logger.error(f"Application failed to start: {e}", exc_info=True)
        raise


if __name__ == "__main__":
    main()