#!/usr/bin/env python3
import os
import json
import logging
import requests
import time
import argparse
from typing import Dict, List, Any, Optional

###############################################################################
#                              LOGGING SETUP
###############################################################################
def setup_logging(log_file: Optional[str] = None, level=logging.INFO) -> logging.Logger:
    """
    Configure logging with both console and file output at the given level (default: INFO).
    """
    logger = logging.getLogger("conversation_processor")
    logger.setLevel(level)

    # Remove any existing handlers
    logger.handlers = []

    # Console handler
    console_handler = logging.StreamHandler()
    console_handler.setLevel(level)
    console_formatter = logging.Formatter(
        "%(asctime)s - %(levelname)s - [%(name)s] %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S"
    )
    console_handler.setFormatter(console_formatter)
    logger.addHandler(console_handler)

    # File handler
    if log_file:
        file_handler = logging.FileHandler(log_file, encoding='utf-8')
        file_handler.setLevel(level)
        file_formatter = logging.Formatter(
            "%(asctime)s - %(levelname)s - [%(name)s:%(filename)s:%(lineno)d] - %(message)s"
        )
        file_handler.setFormatter(file_formatter)
        logger.addHandler(file_handler)

    return logger

logger = setup_logging("conversation_processing.log", level=logging.INFO)

###############################################################################
#                      CHECKPOINT LOAD/SAVE
###############################################################################
def load_checkpoint(checkpoint_path: Optional[str]) -> Dict[str, Any]:
    """
    Load the checkpoint file if it exists, or return a default structure.
    Example structure:
    {
      "file_index": 0,
      "files": {
         "filename.json": {
            "done": false,
            "conv_index": 0,
            "arcs_processed": {
              "0": 2,
              "1": 10
            }
         }
      }
    }
    """
    if not checkpoint_path or not os.path.exists(checkpoint_path):
        return {
            "file_index": 0,
            "files": {}
        }
    try:
        with open(checkpoint_path, "r", encoding="utf-8") as f:
            data = json.load(f)
        return data
    except Exception as e:
        logger.warning(f"Failed to load checkpoint {checkpoint_path}: {e}")
        return {
            "file_index": 0,
            "files": {}
        }

def save_checkpoint(checkpoint_path: Optional[str], checkpoint_data: Dict[str, Any]) -> None:
    """
    Save the checkpoint data to disk so we can resume later.
    """
    if not checkpoint_path:
        return
    try:
        with open(checkpoint_path, "w", encoding="utf-8") as f:
            json.dump(checkpoint_data, f, ensure_ascii=False, indent=2)
        logger.info(f"Checkpoint saved to {checkpoint_path}")
    except Exception as e:
        logger.warning(f"Failed to save checkpoint: {e}")

###############################################################################
#                           HELPER FUNCTIONS
###############################################################################
def safe_join_parts(parts: Any) -> str:
    """
    Convert 'parts' to a text string, preserving all data.
      - If 'parts' is a list (strings/dicts), we JSON-encode non-string items.
      - Otherwise, we JSON-encode the entire thing.
    """
    if isinstance(parts, list):
        lines = []
        for p in parts:
            if isinstance(p, str):
                lines.append(p)
            else:
                # JSON-encode non-string items
                lines.append(json.dumps(p, ensure_ascii=False))
        return "\n".join(lines)
    else:
        return json.dumps(parts, ensure_ascii=False)

def traverse_conversation(mapping: Dict[str, Any], node_id: str, conversation_lines: List[Dict[str, str]]) -> None:
    """
    Recursively traverse a single conversation's 'mapping', collecting *all* role messages.
    Instead of storing raw text lines, store dicts: {"role": "...", "content": "..."}.
    """
    node = mapping[node_id]
    message = node.get("message")
    if message:
        role = message.get("author", {}).get("role", "unknown_role")
        content_dict = message.get("content", {})
        parts = content_dict.get("parts", [])
        text = safe_join_parts(parts).strip()
        if text:
            conversation_lines.append({
                "role": role,
                "content": text
            })

    for child_id in node.get("children", []):
        traverse_conversation(mapping, child_id, conversation_lines)

def remove_surrounding_backticks_and_parse(raw: str) -> Dict[str, Any]:
    """
    1. Remove all triple backticks.
    2. Extract from the first '{' to the last '}' to isolate a JSON block.
    3. Parse that substring as JSON. Return {} on failure.
    """
    content = raw.strip()
    # Remove all triple backticks or code fences
    content = content.replace('```', '')

    # Attempt to isolate the JSON portion
    start_idx = content.find('{')
    end_idx = content.rfind('}')
    if start_idx == -1 or end_idx == -1 or start_idx > end_idx:
        # no valid brace substring
        logger.warning(f"Could not find JSON braces in response: {raw[:200]}")
        return {}

    content = content[start_idx:end_idx+1].strip()
    try:
        return json.loads(content)
    except json.JSONDecodeError as e:
        logger.warning(f"Could not parse JSON: {e} | raw content: {raw[:200]}")
        return {}

###############################################################################
#                     MULTI-PROVIDER LLM CALL
###############################################################################
def call_llm(
    api_key: str,
    provider: str,
    model_name: str,
    system_prompt: str,
    user_prompt: str,
    temperature: float = 0.0,
    max_tokens: int = 12000,
    request_timeout: int = 600
) -> str:
    """
    Unified LLM caller for (minimax, openai, anthropic).
    Returns raw text from the LLM.
    Logs minimal info at INFO level, more detailed logs at DEBUG level.

    :param request_timeout: Max seconds to wait for each LLM response.
    """
    start_time = time.time()
    logger.info(f"call_llm => provider={provider}, model={model_name}")

    if logger.isEnabledFor(logging.DEBUG):
        preview = (user_prompt[:500] + "...") if len(user_prompt) > 500 else user_prompt
        logger.debug(f"User prompt (up to 500 chars): {preview!r}")

    if provider == "minimax":
        url = "https://api.minimaxi.chat/v1/text/chatcompletion_v2"
        headers = {
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json"
        }
        payload = {
            "model": model_name,
            "messages": [
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": user_prompt}
            ],
            "temperature": temperature,
            "top_p": 0.95,
            "mask_sensitive_info": False,
            "max_tokens": max_tokens
        }

        logger.debug("MiniMax API Request:")
        safe_headers = {k: v for k, v in headers.items() if k.lower() != 'authorization'}
        logger.debug(f"Headers: {json.dumps(safe_headers)}")
        logger.debug(f"Payload: {json.dumps(payload, ensure_ascii=False, indent=2)}")

        resp = requests.post(url, headers=headers, json=payload, timeout=request_timeout)
        logger.debug(f"MiniMax API Response Status: {resp.status_code}")
        logger.debug(f"Raw Response: {resp.text}")
        resp.raise_for_status()
        response_data = resp.json()

        if "choices" not in response_data or not response_data["choices"]:
            logger.error("MiniMax response missing or empty 'choices'")
            return ""
        content = response_data["choices"][0]["message"].get("content", "")

    elif provider == "openai":
        import openai
        openai.api_key = api_key

        messages = [
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": user_prompt}
        ]
        logger.debug("OpenAI API Request:")
        logger.debug(f"Model: {model_name}")
        logger.debug(f"Params: temperature={temperature}, max_tokens={max_tokens}")
        logger.debug(f"Messages: {json.dumps(messages, ensure_ascii=False, indent=2)}")

        try:
            response = openai.ChatCompletion.create(
                model=model_name,
                messages=messages,
                temperature=temperature,
                max_tokens=max_tokens,
                request_timeout=request_timeout
            )
            logger.debug(f"OpenAI Raw Response: {json.dumps(response, ensure_ascii=False)}")
            content = response.choices[0].message.content
        except Exception as e:
            logger.error(f"OpenAI API Error: {e}")
            return ""

    elif provider == "anthropic":
        from anthropic import Anthropic
        anthropic_client = Anthropic(api_key=api_key, timeout=request_timeout)

        logger.debug("Anthropic API Request:")
        logger.debug(f"Model: {model_name}")
        logger.debug(f"Params: max_tokens={max_tokens}")

        try:
            response = anthropic_client.messages.create(
                model=model_name,
                max_tokens=max_tokens,
                temperature=temperature,
                system=system_prompt,
                messages=[
                    {"role": "user", "content": user_prompt}
                ]
            )
            content = response.content[0].text.strip()
            # Validate JSON
            try:
                json.loads(content)
                return content
            except json.JSONDecodeError as e:
                logger.error(f"LLM returned invalid JSON: {e}")
                return ""
        except Exception as e:
            logger.error(f"Anthropic API Error: {e}")
            return ""
    else:
        raise ValueError(f"Unsupported provider: {provider}")

    elapsed = time.time() - start_time
    logger.info(f"call_llm completed in {elapsed:.2f}s => content length: {len(content)}")
    return content

###############################################################################
#                          ARC DETECTION
###############################################################################
def detect_arcs_in_conversation(
    conversation_text: str,
    api_key: str,
    provider: str,
    model_name: str,
    request_timeout: int
) -> List[Dict[str, Any]]:
    """
    Ask the LLM to detect arcs in the conversation. Return a list of arcs with
    'start', 'end', 'topic', 'outcome'.
    """
    # Updated system prompt: forbid triple backticks
    system_prompt = (
        "You are a JSON-only conversation analyst. Follow these rules:\n"
        "1. Return ONLY valid JSON\n"
        "2. No explanations or comments\n"
        "3. No code blocks\n"
        "4. Use proper JSON quoting\n"
        "5. No triple backticks or partial text. Only a single JSON object.\n\n"
        "Task: Analyze conversations to identify solution arcs where problems/topics are discussed and resolved.\n"
        "Required JSON format: {\"arcs\":[{\"start\":int,\"end\":int,\"topic\":string,\"outcome\":string}]}"
    )
    user_prompt = f"Analyze this conversation and output ONLY JSON:\n\n{conversation_text}"

    raw_response = call_llm(
        api_key=api_key,
        provider=provider,
        model_name=model_name,
        system_prompt=system_prompt,
        user_prompt=user_prompt,
        temperature=0.0,
        max_tokens=12000,
        request_timeout=request_timeout
    )

    parsed = remove_surrounding_backticks_and_parse(raw_response)
    arcs = parsed.get("arcs", [])
    final_arcs = []
    for arc in arcs:
        if all(k in arc for k in ("start", "end", "topic")):
            final_arcs.append(arc)
        else:
            logger.warning(f"Invalid arc structure: {arc}")
    return final_arcs

###############################################################################
#                     DOMAIN CLASSIFICATION
###############################################################################
def classify_domain(
    arc_text: str,
    api_key: str,
    provider: str,
    model_name: str,
    request_timeout: int
) -> str:
    """
    Use LLM to classify domain. Return e.g. 'frontend', 'backend', 'devops', 'business', 'unknown'...
    """
    system_prompt = (
        "You are a JSON-only domain classifier. Follow these rules:\n"
        "1. Return ONLY valid JSON\n"
        "2. No explanations or comments\n"
        "3. No code blocks\n"
        "4. Use proper JSON quoting\n"
        "5. No triple backticks or partial text. Only a single JSON object.\n\n"
        "Task: Classify text into domain: frontend, backend, devops, business, or unknown.\n"
        "Required JSON format: {\"domain\":string}"
    )
    user_prompt = f"Classify this text into a domain and output ONLY JSON:\n\n{arc_text}"

    raw_response = call_llm(
        api_key=api_key,
        provider=provider,
        model_name=model_name,
        system_prompt=system_prompt,
        user_prompt=user_prompt,
        temperature=0.0,
        max_tokens=2000,
        request_timeout=request_timeout
    )
    parsed = remove_surrounding_backticks_and_parse(raw_response)
    return parsed.get("domain", "unknown")

###############################################################################
#                   ARC OUTCOME / LEARNINGS
###############################################################################
def refine_arc_outcome(
    arc_text: str,
    initial_outcome: str,
    api_key: str,
    provider: str,
    model_name: str,
    request_timeout: int
) -> Dict[str, Any]:
    """
    Possibly refine or confirm the arc outcome, and produce key_corrections, etc.
    Return: {
      "outcome": "...",
      "key_corrections": [...],
      "type": "problem_solving"
    }
    """
    system_prompt = (
        "You are a JSON-only conversation analyzer. Follow these rules:\n"
        "1. Return ONLY valid JSON\n"
        "2. No explanations or comments\n"
        "3. No code blocks\n"
        "4. Use proper JSON quoting\n"
        "5. No triple backticks or partial text. Only a single JSON object.\n\n"
        "Task: Analyze conversation arc and refine outcome.\n"
        "Required JSON format: {\"outcome\":string,\"key_corrections\":[strings],\"type\":string}"
    )
    user_prompt = (
        f"Analyze this arc and output ONLY JSON:\n\n"
        f"Initial outcome: {initial_outcome}\nText:\n{arc_text}"
    )

    raw_response = call_llm(
        api_key=api_key,
        provider=provider,
        model_name=model_name,
        system_prompt=system_prompt,
        user_prompt=user_prompt,
        temperature=0.0,
        max_tokens=2000,
        request_timeout=request_timeout
    )
    parsed = remove_surrounding_backticks_and_parse(raw_response)

    outcome = parsed.get("outcome", initial_outcome)
    key_corr = parsed.get("key_corrections", [])
    if not isinstance(key_corr, list):
        key_corr = []
    arc_type = parsed.get("type", "problem_solving")

    return {
        "outcome": outcome,
        "key_corrections": key_corr,
        "type": arc_type
    }

###############################################################################
#                   UNHELPFUL ASSISTANT CHECK
###############################################################################
def is_unhelpful_assistant_message(
    role: str,
    content: str,
    api_key: str,
    provider: str,
    model_name: str,
    request_timeout: int
) -> bool:
    """
    Returns True if an assistant message is unhelpful/outdated.
    We'll remove it entirely in that case.
    """
    if role != "assistant":
        return False

    system_prompt = (
        "You are a JSON-only message evaluator. Follow these rules:\n"
        "1. Return ONLY valid JSON\n"
        "2. No explanations or comments\n"
        "3. No code blocks\n"
        "4. Use proper JSON quoting\n"
        "5. No triple backticks or partial text. Only a single JSON object.\n\n"
        "Task: Evaluate if message is unhelpful/outdated/incorrect.\n"
        "Required JSON format: {\"unhelpful\":boolean}"
    )
    user_prompt = f"Evaluate this message and output ONLY JSON:\n\n{content}"

    raw_response = call_llm(
        api_key=api_key,
        provider=provider,
        model_name=model_name,
        system_prompt=system_prompt,
        user_prompt=user_prompt,
        temperature=0.0,
        max_tokens=2000,
        request_timeout=request_timeout
    )
    parsed = remove_surrounding_backticks_and_parse(raw_response)
    return parsed.get("unhelpful", False)

###############################################################################
#                   DUPLICATE CODE CHECK
###############################################################################
def detect_code_blocks(content: str) -> bool:
    """
    Naive check for triple-backticks => likely code block.
    """
    return "```" in content

def is_exact_code_duplicate(content: str, seen_snippets: List[str]) -> bool:
    c_stripped = content.strip()
    return c_stripped in (s.strip() for s in seen_snippets)

###############################################################################
#        PROCESS ONE CONVERSATION => MULTI ARCS (with arc-level checkpoint)
###############################################################################
def process_conversation_arcs(
    conversation_data: Dict[str, Any],
    api_key: str,
    provider: str,
    model_name: str,
    output_file: str,
    request_timeout: int,
    file_path: str,
    conv_index: int,
    checkpoint_data: Dict[str, Any],
    checkpoint_path: Optional[str]
) -> int:
    """
    Process a single conversation, detect arcs, and write them out.
    We store arc-level progress in checkpoint_data["files"][file_path]["arcs_processed"][str(conv_index)].
    """
    mapping = conversation_data.get("mapping")
    if not mapping:
        logger.warning("Conversation data missing 'mapping'. Skipping.")
        return 0

    # Identify root node
    root_node = None
    for k, v in mapping.items():
        if v.get("parent") is None:
            root_node = k
            break
    if not root_node:
        logger.warning("No root node found. Skipping.")
        return 0

    # Gather messages
    all_messages: List[Dict[str, str]] = []
    traverse_conversation(mapping, root_node, all_messages)
    if not all_messages:
        logger.warning("Conversation is empty after traversing. Skipping.")
        return 0

    logger.info(f"Collected {len(all_messages)} messages for conversation index={conv_index}")

    # Build text for arc detection
    lines_for_detection = []
    for i, msg in enumerate(all_messages):
        role = msg["role"].upper()
        lines_for_detection.append(f"[{i}][{role}]\n{msg['content']}\n")
    conversation_text = "\n".join(lines_for_detection)

    # Detect arcs
    arcs_data = detect_arcs_in_conversation(
        conversation_text=conversation_text,
        api_key=api_key,
        provider=provider,
        model_name=model_name,
        request_timeout=request_timeout
    )
    if not arcs_data:
        arcs_data = [{"start": 0, "end": len(all_messages)-1, "topic": "general", "outcome": "none"}]

    # Where we left off with arcs
    file_info = checkpoint_data["files"][file_path]
    arcs_processed_map = file_info.setdefault("arcs_processed", {})
    arcs_done = arcs_processed_map.setdefault(str(conv_index), 0)

    arcs_written = 0
    with open(output_file, "a", encoding="utf-8") as out_f:
        for arc_idx, arc_info in enumerate(arcs_data):
            if arc_idx < arcs_done:
                # skip arcs we've processed
                continue

            start_i = arc_info["start"]
            end_i = arc_info["end"]
            topic = arc_info.get("topic", "unknown")
            outcome = arc_info.get("outcome", "")

            # slice messages
            if start_i < 0:
                start_i = 0
            if end_i >= len(all_messages):
                end_i = len(all_messages) - 1
            if start_i > end_i:
                start_i, end_i = end_i, start_i

            arc_msgs_in = all_messages[start_i:end_i+1]

            # filter out unhelpful + remove duplicates
            seen_snippets = []
            arc_msgs_out = []
            for m in arc_msgs_in:
                role = m["role"]
                content = m["content"]
                if role == "assistant":
                    if is_unhelpful_assistant_message(
                        role, content, api_key, provider, model_name, request_timeout
                    ):
                        continue
                    if detect_code_blocks(content):
                        if is_exact_code_duplicate(content, seen_snippets):
                            continue
                        else:
                            seen_snippets.append(content)
                arc_msgs_out.append({"role": role, "content": content})

            if not arc_msgs_out:
                continue

            # domain classification
            arc_text = "\n".join(f"{m['role']}:\n{m['content']}" for m in arc_msgs_out)
            domain_label = classify_domain(
                arc_text, api_key, provider, model_name, request_timeout
            )

            # refine outcome
            arc_learn = refine_arc_outcome(
                arc_text, outcome, api_key, provider, model_name, request_timeout
            )

            # final output
            final_messages = []
            system_content = f"Topic: {topic}, Domain: {domain_label}, Outcome: {arc_learn['outcome']}"
            final_messages.append({"role": "system", "content": system_content})

            for msg in arc_msgs_out:
                if msg["role"] == "assistant":
                    final_messages.append({
                        "role": "assistant",
                        "content": msg["content"],
                        "weight": 1
                    })
                elif msg["role"] == "user":
                    final_messages.append({
                        "role": "user",
                        "content": msg["content"]
                    })
                else:
                    final_messages.append({
                        "role": "user",
                        "content": msg["content"]
                    })

            final_object = {"messages": final_messages}
            out_f.write(json.dumps(final_object, ensure_ascii=False) + "\n")
            arcs_written += 1

            # update arcs_done after each arc
            arcs_done = arc_idx + 1
            arcs_processed_map[str(conv_index)] = arcs_done
            save_checkpoint(checkpoint_path, checkpoint_data)

    return arcs_written

###############################################################################
#               PROCESS SINGLE ITEM => (One conversation, perhaps)
###############################################################################
def process_single_item(
    item_data: Any,
    api_key: str,
    provider: str,
    model_name: str,
    output_file: str,
    request_timeout: int,
    file_path: str,
    conv_index: int,
    checkpoint_data: Dict[str, Any],
    checkpoint_path: Optional[str]
) -> int:
    """
    Process a single conversation dictionary or skip if invalid.
    Uses process_conversation_arcs for partial arc checkpointing.
    """
    if not isinstance(item_data, dict):
        logger.warning(f"Item data at conv_index={conv_index} is not a dict. Skipping.")
        return 0

    arcs = process_conversation_arcs(
        conversation_data=item_data,
        api_key=api_key,
        provider=provider,
        model_name=model_name,
        output_file=output_file,
        request_timeout=request_timeout,
        file_path=file_path,
        conv_index=conv_index,
        checkpoint_data=checkpoint_data,
        checkpoint_path=checkpoint_path
    )
    return arcs

###############################################################################
#                  PROCESS FILES (WITH PROGRESS + CHECKPOINTING)
###############################################################################
def process_file(
    file_path: str,
    output_path: str,
    api_key: str,
    provider: str,
    model_name: str,
    request_timeout: int,
    checkpoint_data: Dict[str, Any],
    checkpoint_path: Optional[str]
) -> int:
    """
    Process a single JSON file. It can have:
      - a single conversation dict
      - a list of conversation dicts
    Uses checkpoint_data to skip processed convs/arcs.
    """
    logger.info(f"Processing file: {file_path}")

    file_info = checkpoint_data["files"].setdefault(file_path, {
        "done": False,
        "conv_index": 0,
        "arcs_processed": {}
    })
    if file_info["done"]:
        logger.info(f"File {file_path} is marked done. Skipping.")
        return 0

    conv_index = file_info["conv_index"]

    try:
        with open(file_path, "r", encoding="utf-8") as f:
            data = json.load(f)
    except Exception as e:
        logger.error(f"Failed to read {file_path}: {e}")
        return 0

    total_arcs = 0

    if isinstance(data, dict):
        # Single conversation => treat conv_index=0
        if conv_index > 0:
            logger.info(f"Single conversation in {file_path} - already processed. Skipping.")
            return 0

        arcs = process_single_item(
            item_data=data,
            api_key=api_key,
            provider=provider,
            model_name=model_name,
            output_file=output_path,
            request_timeout=request_timeout,
            file_path=file_path,
            conv_index=0,
            checkpoint_data=checkpoint_data,
            checkpoint_path=checkpoint_path
        )
        total_arcs += arcs

        # mark file done
        file_info["done"] = True
        file_info["conv_index"] = 1
        save_checkpoint(checkpoint_path, checkpoint_data)

    elif isinstance(data, list):
        for i, item in enumerate(data):
            if i < conv_index:
                logger.info(f"Skipping conversation {i} (already processed).")
                continue

            logger.info(f"Processing conversation {i} in file {file_path}")
            arcs = process_single_item(
                item_data=item,
                api_key=api_key,
                provider=provider,
                model_name=model_name,
                output_file=output_path,
                request_timeout=request_timeout,
                file_path=file_path,
                conv_index=i,
                checkpoint_data=checkpoint_data,
                checkpoint_path=checkpoint_path
            )
            total_arcs += arcs

            # update conv_index
            file_info["conv_index"] = i + 1
            save_checkpoint(checkpoint_path, checkpoint_data)

        file_info["done"] = True
        save_checkpoint(checkpoint_path, checkpoint_data)
    else:
        logger.warning(f"Unexpected data type in {file_path}: {type(data)}")

    return total_arcs

def main():
    parser = argparse.ArgumentParser(description="Prepare ChatGPT export data for multi-arc fine-tuning.")
    parser.add_argument("--input", required=True, help="Path to input JSON file or directory.")
    parser.add_argument("--output", required=True, help="Path to output .jsonl file.")
    parser.add_argument("--api_key", required=True, help="API key for the LLM provider.")
    parser.add_argument("--provider", default="minimax", help="Which LLM provider: openai, anthropic, minimax.")
    parser.add_argument("--model_name", default="gpt-3.5-turbo", help="Model name.")
    parser.add_argument("--multiple_files", action="store_true", help="Process all .json in input directory.")
    parser.add_argument("--debug", action="store_true", help="Enable DEBUG logging for more detail.")
    parser.add_argument("--api_timeout", type=int, default=600, help="Timeout (in seconds) for LLM calls.")
    parser.add_argument("--checkpoint", help="Path to checkpoint file (JSON).")

    args = parser.parse_args()

    if args.debug:
        logger.setLevel(logging.DEBUG)
        for h in logger.handlers:
            h.setLevel(logging.DEBUG)

    # Load checkpoint
    checkpoint_data = load_checkpoint(args.checkpoint)

    # Clear output if starting fresh
    if checkpoint_data["file_index"] == 0 and not checkpoint_data["files"]:
        with open(args.output, "w", encoding="utf-8") as f:
            pass

    start_time = time.time()
    logger.info(
        f"Start => provider={args.provider}, model={args.model_name}, multiple_files={args.multiple_files}"
    )

    total_arcs = 0
    if args.multiple_files:
        if not os.path.isdir(args.input):
            raise ValueError(f"Expected a directory, got {args.input}")

        json_files = [f for f in os.listdir(args.input) if f.endswith(".json")]
        json_files.sort()
        logger.info(f"Found {len(json_files)} .json files in {args.input}...")

        for file_idx, jf in enumerate(json_files):
            if file_idx < checkpoint_data["file_index"]:
                logger.info(f"Skipping file {jf} (already processed).")
                continue

            full_path = os.path.join(args.input, jf)
            arcs = process_file(
                file_path=full_path,
                output_path=args.output,
                api_key=args.api_key,
                provider=args.provider,
                model_name=args.model_name,
                request_timeout=args.api_timeout,
                checkpoint_data=checkpoint_data,
                checkpoint_path=args.checkpoint
            )
            total_arcs += arcs

            # update file_index
            checkpoint_data["file_index"] = file_idx + 1
            save_checkpoint(args.checkpoint, checkpoint_data)

            elapsed = time.time() - start_time
            avg_time = elapsed / (file_idx + 1) if (file_idx + 1) > 0 else 0
            remaining = (len(json_files) - (file_idx + 1)) * avg_time
            logger.info(f"Progress: {file_idx + 1}/{len(json_files)} files, {total_arcs} arcs total.")
            logger.info(f"Average time/file: {avg_time:.2f}s, ETA: {remaining:.2f}s")

    else:
        # single file mode
        if not os.path.isfile(args.input):
            raise ValueError(f"Expected a single file, got {args.input}")

        arcs = process_file(
            file_path=args.input,
            output_path=args.output,
            api_key=args.api_key,
            provider=args.provider,
            model_name=args.model_name,
            request_timeout=args.api_timeout,
            checkpoint_data=checkpoint_data,
            checkpoint_path=args.checkpoint
        )
        total_arcs += arcs

    elapsed = time.time() - start_time
    logger.info(f"Processing completed in {elapsed:.2f}s. Total arcs written: {total_arcs}")

if __name__ == "__main__":
    main()
