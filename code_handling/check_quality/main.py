import os
import time
import json
import logging
import requests
import redis
from dataclasses import dataclass, field
from typing import Dict, List, Any, Optional

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s"
)
logger = logging.getLogger("multi_agent_quality")

# -------------------------------------------------------------------
# 1. CONFIGURATION & REDIS SETUP
# -------------------------------------------------------------------

@dataclass
class QualityServiceConfig:
    """
    Purpose-driven config for the entire multi-agent quality pipeline.
    We won't do horizontal 'azure_logs' or 'code_retriever' modules—
    everything is orchestrated together here for synergy.
    """
    redis_host: str = field(default="localhost")
    redis_port: int = field(default=6379)
    redis_password: Optional[str] = field(default=None)
    redis_ssl: bool = field(default=True)

    # LLM settings
    anthropic_api_key: Optional[str] = field(default=None)
    anthropic_model: str = field(default="sonnet-3.5")

    # Optional Azure logs
    azure_logs_enabled: bool = field(default=False)
    azure_logs_stub: bool = field(default=True)  # to simulate logs if real calls are not set up

    # Dot-delimited keys
    task_queue_key: str = field(default="woa.quality.pipeline.tasks")
    polling_interval_sec: int = field(default=10)

def load_config_from_env() -> QualityServiceConfig:
    """
    Loads environment variables in a single function.
    """
    return QualityServiceConfig(
        redis_host=os.getenv("REDIS_HOST", "localhost"),
        redis_port=int(os.getenv("REDIS_PORT", "6379")),
        redis_password=os.getenv("REDIS_PASSWORD"),
        redis_ssl=os.getenv("REDIS_SSL", "true").lower() == "true",
        anthropic_api_key=os.getenv("ANTHROPIC_API_KEY"),
        anthropic_model=os.getenv("ANTHROPIC_MODEL", "sonnet-3.5"),
        azure_logs_enabled=os.getenv("AZURE_LOGS_ENABLED", "false").lower() == "true",
        azure_logs_stub=os.getenv("AZURE_LOGS_STUB", "true").lower() == "true",
        task_queue_key=os.getenv("QUALITY_TASK_QUEUE", "woa.quality.pipeline.tasks"),
        polling_interval_sec=int(os.getenv("POLLING_INTERVAL", "10")),
    )

def create_redis_client(cfg: QualityServiceConfig) -> redis.Redis:
    """
    Single place to create and test a Redis connection, without
    arbitrary horizontal splits.
    """
    kwargs = {
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
    if cfg.redis_ssl:
        kwargs.update({"ssl": True, "ssl_cert_reqs": None})

    client = redis.Redis(**kwargs)

    for attempt in range(3):
        try:
            client.ping()
            logger.info("✅ Connected to Redis.")
            break
        except redis.ConnectionError as e:
            if attempt == 2:
                raise
            delay = 2 ** attempt
            logger.warning(f"Redis ping failed. Retrying in {delay}s...")
            time.sleep(delay)

    return client

# -------------------------------------------------------------------
# 2. MULTI-AGENT LOGIC (Single-File, Purpose-Focused)
# -------------------------------------------------------------------

def fetch_code_from_redis(rclient: redis.Redis, service_name: str) -> Dict[str, str]:
    """
    Agent #1: Fetch code files from Redis for a given service.
    We rely on a consistent prefix, e.g., file-sync:woa:deployer:<service_name>:<rel_path>
    Then we decode the base64 content into actual code text.

    This is a single function that does the job—no separate 'code_retriever.py' file.
    """
    code_map = {}
    prefix = f"file-sync:woa:deployer:{service_name}:*"
    logger.info(f"🔎 Scanning Redis for code under '{prefix}' ...")

    cursor = 0
    while True:
        cursor, keys = rclient.scan(cursor=cursor, match=prefix, count=100)
        for key in keys:
            key_str = key if isinstance(key, str) else key.decode("utf-8")
            content_b64 = rclient.get(key_str)
            if content_b64:
                try:
                    decoded = requests.utils.b64decode(content_b64).decode("utf-8", errors="ignore")
                    # Infer relative path from the tail of the key
                    # (The format might differ, adjust as needed)
                    splitted = key_str.split(":")
                    rel_path = splitted[-1] if len(splitted) > 0 else "unknown_file.py"
                    code_map[rel_path] = decoded
                except Exception as ex:
                    logger.warning(f"Failed to decode code from key={key_str}: {ex}")
        if cursor == 0:
            break

    logger.info(f"🗂 Fetched {len(code_map)} files for service '{service_name}'.")
    return code_map

def fetch_logs_from_azure(cfg: QualityServiceConfig) -> List[str]:
    """
    Agent #2: Grab logs from Azure (or a stub). If we want to do an LLM-based
    log interpretation, we do so in the 'analyze_logs_with_llm()' function below.
    """
    if not cfg.azure_logs_enabled:
        logger.info("Azure logs not enabled. Skipping logs fetch.")
        return []

    if cfg.azure_logs_stub:
        # Stub some logs
        sample = [
            "ERROR: x.py:112 -> IndexError in production",
            "WARNING: suspicious memory usage in main_loop()",
            "INFO: minor user complaint about feature toggles"
        ]
        logger.info("Returning stubbed logs for demonstration.")
        return sample

    # Real code might call the Azure Monitor or Log Analytics client.
    # We'll skip implementing that for brevity.
    logger.info("Azure logs enabled, but no real implementation here. Returning empty list.")
    return []

def analyze_logs_with_llm(cfg: QualityServiceConfig, logs: List[str]) -> str:
    """
    Agent #3: Use the LLM to interpret the logs.
    Instead of a separate 'azure_logs.py' or purely local approach,
    we feed logs to the LLM and ask for correlation or summarization.
    """
    if not logs or not cfg.anthropic_api_key:
        return "No logs or no API key. Log analysis skipped."

    prompt = (
        "You are a code-quality & error-correlation assistant.\n"
        "Given these logs, identify any potential root causes or relevant error patterns.\n\n"
        f"Logs:\n{json.dumps(logs, indent=2)}\n\n"
        "Output a concise analysis in Markdown, referencing code errors if possible.\n"
        "End with 'END_OF_LOG_ANALYSIS'"
    )
    return call_anthropic_llm(cfg, prompt)

def analyze_code_with_llm(cfg: QualityServiceConfig, code_map: Dict[str, str]) -> str:
    """
    Agent #4: A single LLM call that tries to interpret architecture, cohesion,
    coupling, file size issues, etc. We do *not* rely on a purely local approach
    of line counting or radon-like checks. We let the LLM do it. Then we can refine
    in a subsequent agent if the analysis is incomplete.
    """
    if not code_map or not cfg.anthropic_api_key:
        return "No code to analyze or missing API key."

    # We might need to chunk large code sets, but for demonstration let's dump summary
    file_summaries = []
    for fname, content in code_map.items():
        lines = content.count("\n") + 1
        snippet = content[:500]  # just show partial code snippet
        file_summaries.append(f"File: {fname}, ~{lines} lines\nSnippet:\n{snippet}\n---\n")

    combined_text = "\n".join(file_summaries)
    prompt = (
        "You are a code-quality LLM agent. Evaluate the following code in terms of:\n"
        "1. Architecture and clarity\n"
        "2. Cohesion vs. coupling\n"
        "3. Potential large-file or structural issues\n\n"
        "Provide a thorough analysis in Markdown. End with 'END_OF_CODE_ANALYSIS'.\n\n"
        f"{combined_text}"
    )

    return call_anthropic_llm(cfg, prompt)

def refine_analysis_with_llm(cfg: QualityServiceConfig, partial_code_analysis: str, partial_log_analysis: str) -> str:
    """
    Agent #5: Coordinator agent that merges partial code analysis and log analysis,
    then re-prompts the LLM to unify them into a final multi-aspect assessment.
    We can do multiple iterations if needed.
    """
    if not cfg.anthropic_api_key:
        return "Missing API key; cannot refine analysis."

    initial_merge = (
        "We have two partial analyses:\n\n"
        "### Code Analysis\n"
        f"{partial_code_analysis}\n\n"
        "### Log Analysis\n"
        f"{partial_log_analysis}\n\n"
        "Now unify these findings. Identify if any errors in logs correlate to code structure.\n"
        "Ensure we address architecture, cohesion, and code issues thoroughly.\n"
        "End with 'END_OF_FINAL_ANALYSIS'."
    )

    # Possibly an iterative approach: we look for missing keywords or topics, similar
    # to the previous example. For demonstration, let's just do one pass:
    final_output = call_anthropic_llm(cfg, initial_merge)
    if "architecture" not in final_output.lower():
        # re-prompt
        refine_prompt = (
            f"{final_output}\n\n"
            "Please add more detail on architecture or design aspects. "
            "End with 'END_OF_FINAL_ANALYSIS'."
        )
        final_output = call_anthropic_llm(cfg, refine_prompt)

    if "END_OF_FINAL_ANALYSIS" not in final_output:
        final_output += "\n\nEND_OF_FINAL_ANALYSIS"

    return final_output

# -------------------------------------------------------------------
# 3. LLM UTILS (ONE-FILE, PURPOSE-FOCUSED)
# -------------------------------------------------------------------

def call_anthropic_llm(cfg: QualityServiceConfig, prompt: str, temperature: float = 0.2) -> str:
    """
    A single utility function for LLM calls, no separate 'llm_agent.py' file.
    Purpose: quickly invoke Anthropics Sonnet 3.5 with a textual prompt.
    """
    if not cfg.anthropic_api_key:
        return "Error: No ANTHROPIC_API_KEY configured."

    url = "https://api.anthropic.com/v1/sonnet"  # example endpoint
    headers = {
        "x-api-key": cfg.anthropic_api_key,
        "Content-Type": "application/json"
    }
    payload = {
        "model": cfg.anthropic_model,
        "prompt": prompt,
        "max_tokens_to_sample": 2048,
        "temperature": temperature
    }
    try:
        resp = requests.post(url, headers=headers, json=payload, timeout=20)
        resp.raise_for_status()
        data = resp.json()
        return data.get("completion", "No 'completion' found in LLM response.")
    except Exception as ex:
        logger.error(f"Anthropic LLM call failed: {ex}", exc_info=True)
        return f"LLM error: {ex}"

# -------------------------------------------------------------------
# 4. MAIN PIPELINE
# -------------------------------------------------------------------

def run_quality_pipeline(cfg: QualityServiceConfig, rclient: redis.Redis):
    """
    The main pipeline: multi-agent approach in one function.
      1. Repeatedly get tasks from a queue (e.g. 'woa.quality.pipeline.tasks').
      2. For each service, gather code and logs.
      3. Code analysis agent -> partial analysis.
      4. Logs analysis agent -> partial analysis.
      5. Coordinator agent -> merges partial results, refines with LLM.
      6. Store final result back in Redis.
    """
    logger.info("🟢 Starting Multi-Agent Quality Service. Polling for tasks...")

    while True:
        raw_task = rclient.lpop(cfg.task_queue_key)
        if not raw_task:
            time.sleep(cfg.polling_interval_sec)
            continue

        try:
            task = json.loads(raw_task)
            service_name = task.get("service_name", "unknown_service")
            analysis_key = task.get("analysis_key", f"woa.quality.{service_name}.analysis.py")

            logger.info(f"📌 New quality task for service: {service_name}")

            # Agent #1: code fetch
            code_map = fetch_code_from_redis(rclient, service_name)

            # Agent #2: logs fetch
            logs_list = fetch_logs_from_azure(cfg)

            # Agent #3: logs LLM interpret
            log_analysis_text = analyze_logs_with_llm(cfg, logs_list)

            # Agent #4: code LLM interpret
            code_analysis_text = analyze_code_with_llm(cfg, code_map)

            # Agent #5: coordinator merges partial results
            final_analysis = refine_analysis_with_llm(cfg, code_analysis_text, log_analysis_text)

            # Save in Redis
            rclient.set(analysis_key, final_analysis)
            rclient.hset(f"{analysis_key}.metadata", mapping={
                "type": "quality_analysis",
                "service_name": service_name
            })

            logger.info(f"✅ Final analysis stored at '{analysis_key}'.")
        except Exception as e:
            logger.error(f"Failed to process task: {e}", exc_info=True)

def main():
    """Entry point."""
    cfg = load_config_from_env()
    rclient = create_redis_client(cfg)
    run_quality_pipeline(cfg, rclient)

if __name__ == "__main__":
    main()