import json
import logging
import re
from typing import Optional

from config import APIConfig
from types import LLMAnalysis, MissingDocument, References, DocumentType

logger = logging.getLogger(__name__)

# Attempt Anthropic import
try:
    from anthropic import Anthropic
except ImportError:
    Anthropic = None

# Attempt OpenAI import
try:
    from openai import OpenAI
    # The new v1 SDK for openai
except ImportError:
    OpenAI = None

def call_llm_api(config: APIConfig, prompt: str) -> Optional[str]:
    """
    Main entry point to call either Anthropic or OpenAI (v1).
    """
    logger.info(f"LLM Provider: {config.provider}, model={config.model}")
    provider_lower = config.provider.lower()

    if provider_lower == "anthropic":
        return call_anthropic_api(config, prompt)
    elif provider_lower == "openai":
        return call_openai_api(config, prompt)
    else:
        logger.error(f"Unsupported provider: {config.provider}")
        return None

def call_anthropic_api(config: APIConfig, prompt: str) -> Optional[str]:
    if Anthropic is None:
        logger.error("Anthropic library not installed or not found.")
        return None
    try:
        client = Anthropic(api_key=config.api_key)
        logger.info(f"Sending API request to Anthropic, prompt length={len(prompt)}")
        msg = client.messages.create(
            model=config.model,
            max_tokens=config.max_tokens,
            messages=[{"role": "user", "content": prompt}],
            system="You are generating code docs in {RESULT, RESULT_STRUCTURE, COMPILED, COMPILED_STRUCTURE}."
        )
        return msg.content[0].text
    except Exception as e:
        logger.error(f"Anthropic call failed: {e}")
        return None

def call_openai_api(config: APIConfig, prompt: str) -> Optional[str]:
    """
    Using new openai v1 client usage:
      from openai import OpenAI
      client = OpenAI(api_key=..., model=...)
      completion = client.completions.create(model="...", prompt="...")
    """
    if OpenAI is None:
        logger.error("OpenAI library not installed or not found.")
        return None

    try:
        logger.info(f"Sending API request to OpenAI, prompt length={len(prompt)}")

        # Instantiate the new v1 client
        client = OpenAI(
            api_key=config.api_key,  # optional if env var is set
            # We can also set base_url, default_headers, etc.
        )

        # We'll do a simple completions call
        response = client.completions.create(
            model=config.model,
            prompt=prompt,
            max_tokens=config.max_tokens,
            temperature=config.temperature
        )
        # Convert to string
        # response is a pydantic model
        # we can do response.model_dump_json() if needed
        # For now, let's just parse out .choices[0].text if it exists
        if response.choices and len(response.choices) > 0:
            # We'll re-inject into parse_llm_response in a hacky way
            # because parse_llm_response expects a JSON structure with "fileAnalysis" ...
            # So let's just build a fake JSON
            # We'll store the entire text in "fileAnalysis"
            # The user can adjust if they'd prefer Chat or another approach
            text = response.choices[0].text
            fake_json = f"""{{
  "fileAnalysis": "OpenAI completion response",
  "missingDocuments": [
    {{
      "docType": "RESULT",
      "fileName": "RESULT_unknown.ai-generated.md",
      "suggestedContent": "{text.replace('"','\\"')}"
    }}
  ],
  "references": {{
    "microservices": [],
    "infrastructure": [],
    "domainKnowledge": []
  }}
}}"""
            return fake_json
        else:
            return None
    except Exception as e:
        logger.error(f"OpenAI call failed: {e}")
        return None

def clean_json_response(response: str) -> str:
    """
    Extract just the JSON from a possibly verbose LLM response.
    """
    response = re.sub(r'```(json)?', '', response)
    start = response.find('{')
    end = response.rfind('}')
    if start >= 0 and end >= 0:
        response = response[start:end+1]

    # remove control chars
    response = ''.join(ch for ch in response if ord(ch) >= 32 or ch in '\n\r\t')
    # fix trailing commas
    response = re.sub(r',\s*}', '}', response)
    response = re.sub(r',\s*]', ']', response)

    return response.strip()

def parse_llm_response(response: str) -> Optional[LLMAnalysis]:
    if not response:
        return None
    try:
        cleaned = clean_json_response(response)
        data = json.loads(cleaned)
        if not isinstance(data, dict):
            logger.error("LLM response not a dict.")
            return None

        if 'fileAnalysis' not in data:
            logger.error("Missing 'fileAnalysis' in LLM response.")
            return None

        refs_data = data.get("references", {})
        references = References(
            microservices=refs_data.get("microservices", []),
            infrastructure=refs_data.get("infrastructure", []),
            domain_knowledge=refs_data.get("domainKnowledge", [])
        )

        missing_docs = []
        for doc_data in data.get("missingDocuments", []):
            dt_str = doc_data.get("docType", "")
            if dt_str not in DocumentType.__members__:
                logger.warning(f"Ignoring invalid docType: {dt_str}")
                continue
            doc = MissingDocument(
                doc_type=DocumentType(dt_str),
                file_name=doc_data.get("fileName", ""),
                suggested_content=doc_data.get("suggestedContent", "")
            )
            missing_docs.append(doc)

        return LLMAnalysis(
            file_analysis=data["fileAnalysis"],
            missing_documents=missing_docs,
            references=references
        )
    except Exception as e:
        logger.error(f"parse_llm_response error: {e}")
        return None
