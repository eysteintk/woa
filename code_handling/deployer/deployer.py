import os
import logging
import threading
import time
from datetime import datetime

# Hypothetical modules you might create:
from redis_utils import RedisListener, RedisClient
from azure_acr import build_and_push_image, delete_image, retag_image
from azure_pubsub import WebPubSubClient

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("deployer")

# Global store to track which services are currently building
BUILD_IN_PROGRESS = {}


def on_metadata_change(key_name, event_type):
    """
    Callback when the metadata key changes in Redis.
    key_name: e.g. "world/navigation/.metadata"
    event_type: e.g. "set" or "expired" or something from Redis notifications
    """
    logger.info(f"Detected Redis event {event_type} for key {key_name}")

    # Parse out the service path: "world/navigation"
    service_path = key_name.rsplit("/", 1)[0]

    # If we're already building this service, ignore
    if service_path in BUILD_IN_PROGRESS:
        logger.info(f"Build already in progress for {service_path}, skipping.")
        return

    # Mark that we're building so subsequent events are ignored
    BUILD_IN_PROGRESS[service_path] = True

    # Run the build steps in a new thread or in the same thread.
    # A thread can help if you want non-blocking behavior.
    build_thread = threading.Thread(target=process_service_build, args=(service_path,))
    build_thread.start()


def process_service_build(service_path):
    """
    Orchestrates the entire build -> notify -> accept/reject -> finalize flow.
    """
    redis_client = RedisClient().get_client()

    try:
        # Step 1: Load Dockerfile content from Redis
        dockerfile_key = f"{service_path}/Dockerfile"
        dockerfile_content = redis_client.get(dockerfile_key)
        if not dockerfile_content:
            logger.error(f"No Dockerfile found at {dockerfile_key} in Redis.")
            return

        # Step 2: Perform Docker build & push
        timestamp_tag = datetime.now().strftime("%Y%m%d%H%M%S")
        image_name = f"myregistry.azurecr.io/{service_path.replace('/', '_')}:{timestamp_tag}"
        logger.info(f"Building and pushing image {image_name}...")

        build_logs = build_and_push_image(
            service_path=service_path,
            dockerfile_content=dockerfile_content,
            image_name=image_name
        )

        # Step 3: Store build details in Redis
        build_details_key = f"{service_path}.build.details"
        redis_client.hmset(build_details_key, {
            "image_name": image_name,
            "timestamp": timestamp_tag,
            "build_status": "Built",
            "logs": build_logs
        })

        # Step 4: Notify Web PubSub (and store the event in Redis for reliability)
        webpubsub_client = WebPubSubClient()
        build_event = {
            "service_path": service_path,
            "image_name": image_name,
            "action": "BUILD_COMPLETE",
            "timestamp": timestamp_tag
        }
        # Publish to Web PubSub
        webpubsub_client.send_event_to_group(group="deployer", event=build_event)

        # Also store an event in Redis
        redis_client.rpush(f"{service_path}.events", str(build_event))

        # Step 5: Wait for acceptance/rejection (blocking call or some async approach)
        # For example, poll Redis or wait on a message from Web PubSub
        logger.info(f"Waiting for acceptance or rejection of {image_name}...")

        result = wait_for_acceptance(redis_client, webpubsub_client, service_path, image_name)
        logger.info(f"Result for {image_name} = {result}")

        # Step 6: Promote or Delete
        if result == "accepted":
            latest_tag = f"myregistry.azurecr.io/{service_path.replace('/', '_')}:latest"
            retag_image(image_name, latest_tag)

            # Store acceptance in Redis
            redis_client.set(f"{service_path}.build.result", "accepted")
            logger.info(f"Promoted {image_name} to {latest_tag}")
        else:
            delete_image(image_name)
            redis_client.set(f"{service_path}.build.result", "rejected")
            logger.info(f"Deleted {image_name}")

        # Step 7: (Optional) Create container app if needed
        # e.g. pseudo_create_container_app_if_not_exists(service_path, latest_tag)

    except Exception as ex:
        logger.exception(f"Error building or deploying {service_path}: {ex}")
    finally:
        # Release the lock so new builds can happen
        BUILD_IN_PROGRESS.pop(service_path, None)


def wait_for_acceptance(redis_client, webpubsub_client, service_path, image_name, timeout=300):
    """
    Wait for acceptance or rejection from the UI.
    1) Poll a Redis key or 2) Listen to Web PubSub messages in a loop
    Return either 'accepted' or 'rejected' or None if timed out.
    """
    start_time = time.time()
    while True:
        # 1. Check if there's a known result in Redis
        build_result = redis_client.get(f"{service_path}.build.result")
        if build_result in (b"accepted", b"rejected"):
            return build_result.decode("utf-8")

        # 2. Alternatively, check a Web PubSub queue if you store acceptance events
        # This might be part of your WebPubSubClient or a separate process listening on a queue.

        # 3. Timeout logic
        if time.time() - start_time > timeout:
            logger.warning(f"Acceptance wait timed out for {image_name}")
            return "rejected"  # or None

        time.sleep(5)


def main():
    # Create a Redis listener for all .metadata keys
    # e.g. something like "*/.metadata"
    redis_listener = RedisListener(pattern="*/*.metadata", callback=on_metadata_change)

    logger.info("Starting Deployer service. Listening for metadata changes...")
    redis_listener.listen_forever()


if __name__ == "__main__":
    main()
