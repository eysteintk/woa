import os
import logging
import time
import json
import requests
import redis
from dataclasses import dataclass, field
from typing import Optional

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

@dataclass
class BusinessConfig:
    """Configuration dataclass for the Business Analysis Service."""
    redis_host: str = field(default="localhost")
    redis_port: int = field(default=6379)
    redis_password: Optional[str] = field(default=None)
    anthropic_api_key: Optional[str] = field(default=None)
    anthropic_model: str = field(default="sonnet-3.5")

def load_business_config() -> BusinessConfig:
    """
    Loads environment variables into a BusinessConfig dataclass.
    """
    host = os.getenv("REDIS_HOST", "localhost")
    port_str = os.getenv("REDIS_PORT", "6379")
    redis_password = os.getenv("REDIS_PASSWORD")
    anthropic_key = os.getenv("ANTHROPIC_API_KEY")

    try:
        port = int(port_str)
    except ValueError:
        logger.error(f"Invalid REDIS_PORT value: {port_str}")
        raise

    if not anthropic_key:
        logger.warning("No ANTHROPIC_API_KEY provided. The service might fail to call the LLM.")

    return BusinessConfig(
        redis_host=host,
        redis_port=port,
        redis_password=redis_password,
        anthropic_api_key=anthropic_key
    )

def create_redis_client(cfg: BusinessConfig) -> redis.Redis:
    """
    Creates a Redis client with built-in retry logic.
    """
    ssl_enabled = os.getenv("REDIS_SSL", "false").lower() == "true"
    connection_kwargs = {
        "host": cfg.redis_host,
        "port": cfg.redis_port,
        "password": cfg.redis_password,
        "decode_responses": True,
        "socket_keepalive": True,
        "socket_connect_timeout": 5,
        "socket_timeout": 5,
        "retry_on_timeout": True,
        "max_connections": 10
    }
    if ssl_enabled:
        connection_kwargs.update({
            "ssl": True,
            "ssl_cert_reqs": None
        })

    client = redis.Redis(**connection_kwargs)

    # Test the connection
    max_attempts = 3
    for attempt in range(max_attempts):
        try:
            client.ping()
            logger.info("✅ Business service connected to Redis successfully.")
            break
        except redis.ConnectionError as e:
            if attempt == max_attempts - 1:
                logger.error("❌ Failed to connect to Redis after several attempts.")
                raise
            delay = 2 ** attempt
            logger.warning(f"Ping failed (attempt {attempt+1}), retrying in {delay}s...")
            time.sleep(delay)

    return client

def call_anthropic_llm(
    api_key: str,
    prompt: str,
    model: str = "sonnet-3.5",
    temperature: float = 0.2,
    max_tokens: int = 2048
) -> str:
    """
    Minimal Anthropic LLM call, same approach as in quality service.
    """
    if not api_key:
        return "Error: No ANTHROPIC_API_KEY configured."

    url = "https://api.anthropic.com/v1/sonnet"
    headers = {
        "x-api-key": api_key,
        "Content-Type": "application/json"
    }
    payload = {
        "model": model,
        "prompt": prompt,
        "max_tokens_to_sample": max_tokens,
        "temperature": temperature
    }

    try:
        response = requests.post(url, headers=headers, json=payload, timeout=15)
        response.raise_for_status()
        data = response.json()
        return data.get("completion", "No completion found in response.")
    except Exception as e:
        logger.error(f"Anthropic LLM request failed: {e}", exc_info=True)
        return f"Error calling Anthropic LLM: {str(e)}"

def perform_business_analysis(redis_client: redis.Redis, cfg: BusinessConfig) -> None:
    """
    Periodically checks Redis for "business" tasks, calls the LLM with the code diff and
    model KPI context, then writes the result back to Redis in a dot-delimited key.
    """
    task_list_key = "woa.business.tasks"
    check_interval_sec = 10

    logger.info("🟢 Business Analysis Service started (functional style).")
    while True:
        task_data = redis_client.lpop(task_list_key)
        if task_data:
            try:
                task = json.loads(task_data)
                code_diff = task.get("code_diff", "")
                model_metrics = task.get("model_metrics", {})
                analysis_key = task.get("analysis_key", "woa.business.unknown.analysis.py")

                # Format metrics for prompt
                metrics_lines = "\n".join([f"- {k}: {v}" for k,v in model_metrics.items()])

                prompt = (
                    f"Please provide a business/AI outcome analysis focusing on:\n"
                    f"1. How code changes may have impacted the model: {code_diff}\n"
                    f"2. Recent KPIs:\n{metrics_lines}\n"
                    f"3. Whether these changes align with business goals.\n"
                    f"Output a concise textual analysis.\n"
                )

                llm_response = call_anthropic_llm(
                    api_key=cfg.anthropic_api_key,
                    prompt=prompt,
                    model=cfg.anthropic_model
                )

                redis_client.set(analysis_key, llm_response)
                metadata_hash_key = f"{analysis_key}.metadata"
                redis_client.hset(metadata_hash_key, mapping={
                    "type": "business_analysis",
                    "domain": "business"
                })

                logger.info(f"Stored business analysis for key '{analysis_key}'.")
            except Exception as e:
                logger.error(f"Failed to process business task: {e}", exc_info=True)
        else:
            time.sleep(check_interval_sec)

def main():
    """Main entry point for the Business Analysis Service."""
    cfg = load_business_config()
    redis_client = create_redis_client(cfg)
    perform_business_analysis(redis_client, cfg)

if __name__ == "__main__":
    main()
