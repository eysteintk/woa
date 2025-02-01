from dataclasses import dataclass
from typing import Dict, List, Optional, Any
import json
import tiktoken
from pathlib import Path
import numpy as np
from collections import defaultdict
from openai import OpenAI, OpenAIError
from functools import partial
import logging
import os

# Set up logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)


@dataclass
class FormatError:
    error_type: str
    count: int


@dataclass
class DatasetStats:
    total_examples: int
    total_tokens: int
    mean_tokens: float
    median_tokens: float
    max_tokens: int
    n_missing_system: int
    n_missing_user: int


def load_dataset(file_path: str) -> List[Dict]:
    """Load and parse JSONL dataset."""
    try:
        with open(file_path, 'r', encoding='utf-8') as f:
            return [json.loads(line) for line in f]
    except Exception as e:
        logger.error(f"Error loading dataset: {str(e)}")
        raise


def validate_message(message: Dict) -> List[str]:
    """Validate a single message for required fields and formats."""
    errors = []

    if not isinstance(message, dict):
        return ["message_not_dict"]

    if "role" not in message or "content" not in message:
        errors.append("message_missing_key")

    if message.get("role") not in ("system", "user", "assistant", "function"):
        errors.append("unrecognized_role")

    content = message.get("content")
    if not content or not isinstance(content, str):
        errors.append("missing_content")

    if any(k not in ("role", "content", "name", "function_call", "weight") for k in message):
        errors.append("message_unrecognized_key")

    return errors


def validate_dataset(dataset: List[Dict]) -> Dict[str, int]:
    """Validate entire dataset for fine-tuning requirements."""
    format_errors = defaultdict(int)

    if not dataset:
        format_errors["empty_dataset"] = 1
        return dict(format_errors)

    for idx, example in enumerate(dataset):
        if not isinstance(example, dict):
            format_errors["data_type"] += 1
            logger.warning(f"Example {idx} is not a dictionary")
            continue

        messages = example.get("messages", [])
        if not messages:
            format_errors["missing_messages_list"] += 1
            logger.warning(f"Example {idx} has no messages")
            continue

        for message in messages:
            for error in validate_message(message):
                format_errors[error] += 1
                if error == "message_missing_key":
                    logger.warning(f"Example {idx} has message missing required keys (role or content)")
                elif error == "unrecognized_role":
                    logger.warning(f"Example {idx} has message with invalid role: {message.get('role', 'NO_ROLE')}")
                elif error == "missing_content":
                    logger.warning(f"Example {idx} has message with missing or invalid content")

        if not any(msg.get("role") == "assistant" for msg in messages):
            format_errors["example_missing_assistant_message"] += 1
            logger.warning(f"Example {idx} has no assistant message")

    return dict(format_errors)


def count_tokens(messages: List[Dict], encoding: tiktoken.Encoding) -> int:
    """Count tokens in a message list using tiktoken."""
    tokens_per_message = 3
    tokens_per_name = 1
    num_tokens = 0

    for message in messages:
        num_tokens += tokens_per_message
        for key, value in message.items():
            num_tokens += len(encoding.encode(str(value)))
            if key == "name":
                num_tokens += tokens_per_name

    return num_tokens + 3


def calculate_dataset_statistics(dataset: List[Dict]) -> DatasetStats:
    """Calculate comprehensive dataset statistics."""
    encoding = tiktoken.get_encoding("cl100k_base")
    token_counts = []
    n_missing_system = 0
    n_missing_user = 0

    for example in dataset:
        messages = example["messages"]
        token_counts.append(count_tokens(messages, encoding))

        if not any(msg["role"] == "system" for msg in messages):
            n_missing_system += 1
        if not any(msg["role"] == "user" for msg in messages):
            n_missing_user += 1

    return DatasetStats(
        total_examples=len(dataset),
        total_tokens=sum(token_counts),
        mean_tokens=np.mean(token_counts),
        median_tokens=np.median(token_counts),
        max_tokens=max(token_counts),
        n_missing_system=n_missing_system,
        n_missing_user=n_missing_user
    )


def initialize_openai_client(api_key: str) -> OpenAI:
    """Initialize and verify OpenAI client with authentication."""
    try:
        client = OpenAI(api_key=api_key)
        # Verify authentication with a simple API call
        client.models.list()
        logger.info("OpenAI client initialized successfully")
        return client
    except OpenAIError as e:
        if hasattr(e, 'status_code') and e.status_code == 401:
            raise ValueError("Invalid API key provided")
        else:
            raise ValueError(f"OpenAI API Error: {str(e)}")
    except Exception as e:
        raise ValueError(f"Error initializing OpenAI client: {str(e)}")


def create_fine_tuning_job(
        client: OpenAI,
        training_file_id: str,
        model: str = "gpt-4o-2024-08-06",
        hyperparameters: Optional[Dict[str, Any]] = None
) -> str:
    """Create a fine-tuning job with specified parameters."""
    try:
        job = client.fine_tuning.jobs.create(
            training_file=training_file_id,
            model=model,
            method={
                "type": "supervised",
                "supervised": {
                    "hyperparameters": hyperparameters or {"n_epochs": 3}
                }
            }
        )
        logger.info(f"Created fine-tuning job: {job.id}")
        return job.id
    except Exception as e:
        logger.error(f"Error creating fine-tuning job: {str(e)}")
        raise


def monitor_fine_tuning_job(client: OpenAI, job_id: str) -> None:
    """Monitor the status of a fine-tuning job."""
    try:
        job = client.fine_tuning.jobs.retrieve(job_id)
        logger.info(f"Job status: {job.status}")

        events = client.fine_tuning.jobs.list_events(fine_tuning_job_id=job_id, limit=10)
        for event in events:
            logger.info(f"Event: {event.message}")
    except Exception as e:
        logger.error(f"Error monitoring job: {str(e)}")
        raise


def main(file_path: str, api_key: str, model: str = "gpt-4o-2024-08-06") -> None:
    """Main function to orchestrate the fine-tuning process."""
    try:
        # Initialize authenticated client
        client = initialize_openai_client(api_key)

        # Load and validate dataset
        dataset = load_dataset(file_path)
        format_errors = validate_dataset(dataset)
        logger.info(f"Validation errors: {format_errors}")

        # Calculate and log statistics
        stats = calculate_dataset_statistics(dataset)
        logger.info(f"Dataset statistics: {stats}")

        # Upload file
        with open(file_path, 'rb') as f:
            file_response = client.files.create(
                file=f,
                purpose="fine-tune"
            )
        logger.info(f"File uploaded: {file_response.id}")

        # Create and monitor fine-tuning job
        job_id = create_fine_tuning_job(client, file_response.id, model)
        monitor_fine_tuning_job(client, job_id)

    except Exception as e:
        logger.error(f"Error in fine-tuning process: {str(e)}")
        raise


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(description="Fine-tune GPT-4o model")
    parser.add_argument("file_path", type=str, help="Path to JSONL training data")
    parser.add_argument("--api-key", type=str, required=True, help="OpenAI API key")
    parser.add_argument("--model", type=str, default="gpt-4o-2024-08-06", help="Model version to fine-tune")

    args = parser.parse_args()
    main(args.file_path, args.api_key, args.model)
