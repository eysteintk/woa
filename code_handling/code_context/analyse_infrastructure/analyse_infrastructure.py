#!/usr/bin/env python3
"""
infra_mapper.py

Generates one Markdown file per discovered infrastructure script (.sh with 'infra' in its name).
Focuses on:
- Azure usage (if any)
- Resource group, location, monitoring info (if the script mentions them)
- Services and their "Flow" (how they connect or communicate)
- A "Network Graph" section showing nodes, edges with relationship types

No central "overview" markdown is created.
"""

from dataclasses import dataclass
from typing import List, Set, Tuple
import logging
import argparse
import time
import os
import json
from pathlib import Path
from datetime import datetime


###############################################################################
#                              DATA CLASSES
###############################################################################
@dataclass
class ServiceNode:
    """
    A 'service' or 'component' discovered in the script.
    name: 'Skills Service', 'Static Web App', etc.
    purpose: short text describing what it does in the app
    flow: each item describing some direction of communication or usage
    """
    name: str
    purpose: str
    flow: List[str]


@dataclass
class GraphNode:
    """
    A single node for the infrastructure network graph.
    E.g. name='woa-prod-spa', type='frontend'.
    """
    name: str
    type: str


@dataclass
class GraphEdge:
    """
    A single edge with a relationship type.
    e.g. from='woa-prod-spa', to='skill-service', relationship='calls'.
    """
    from_node: str
    to_node: str
    relationship: str


@dataclass
class ScriptAnalysis:
    """
    The final results from LLM for one script:
      - Whether it uses Azure (azure_usage)
      - Resource group name, location (if found)
      - Some mention of monitoring (if found)
      - A list of ServiceNodes
      - A list of GraphNodes + GraphEdges
    """
    script_abs_path: str
    azure_usage: bool
    resource_group: str
    location: str
    monitoring_info: str
    services: List[ServiceNode]
    graph_nodes: List[GraphNode]
    graph_edges: List[GraphEdge]


###############################################################################
#                              LOGGING
###############################################################################
def create_console_logger(level=logging.INFO) -> logging.Logger:
    logger = logging.getLogger("infra_mapper")
    logger.setLevel(level)
    logger.handlers.clear()

    formatter = logging.Formatter(
        "%(asctime)s - %(levelname)s - [%(name)s] %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S"
    )
    console_handler = logging.StreamHandler()
    console_handler.setLevel(level)
    console_handler.setFormatter(formatter)
    logger.addHandler(console_handler)
    return logger


logger = create_console_logger(logging.INFO)


###############################################################################
#                              LLM CALL
###############################################################################
def call_llm(
        api_key: str,
        provider: str,
        model_name: str,
        system_prompt: str,
        user_prompt: str,
        temperature: float = 0.0,
        max_tokens: int = 8192,
        request_timeout: int = 60
) -> str:
    """
    Calls either OpenAI or Anthropic. Returns text or "" on error.
    """
    try:
        if provider == "openai":
            import openai
            openai.api_key = api_key

            messages = [
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": user_prompt}
            ]
            response = openai.ChatCompletion.create(
                model=model_name,
                messages=messages,
                temperature=temperature,
                max_tokens=max_tokens,
                request_timeout=request_timeout
            )
            content = response.choices[0].message.content
        elif provider == "anthropic":
            from anthropic import Anthropic
            anthropic = Anthropic(api_key=api_key)
            response = anthropic.messages.create(
                model=model_name,
                max_tokens=max_tokens,
                temperature=temperature,
                system=system_prompt,
                messages=[{"role": "user", "content": user_prompt}]
            )
            content = response.content[0].text
        else:
            raise ValueError(f"Unsupported provider: {provider}")

        return content.strip()
    except Exception as e:
        logger.error(f"LLM API error: {e}")
        return ""


###############################################################################
#                   LLM-BASED ANALYSIS PER SCRIPT
###############################################################################
def build_system_prompt() -> str:
    """
    We instruct the LLM to parse the script for Azure usage, resource info,
    monitoring references, plus the important services and their flow,
    and a separate graph with nodes and edges.

    Output JSON ONLY shaped:

    {
      "azure_usage": true|false,
      "resource_group": "string or empty",
      "location": "string or empty",
      "monitoring_info": "string or empty",
      "services": [
        {
          "name": "...",
          "purpose": "...",
          "flow": ["..."]
        }
      ],
      "graph_nodes": [
        {"name": "...", "type": "..."}
      ],
      "graph_edges": [
        {"from": "...", "to": "...", "relationship": "..."}
      ]
    }

    No environment variables.
    """
    return """You are an infrastructure expert. 
Analyze the given bash script. 
We want to know:

1) Whether it clearly uses Azure (azure_usage: true or false).
2) The 'resource_group' if you see it mentioned, else empty.
3) The 'location' if you see it, else empty.
4) 'monitoring_info' if it sets up logs or diagnostics, else empty.

Then we want a high-level mention of actual services from the script 
that matter for app-level context (ignore environment variables or other minor details).
For each service:
   - name: short descriptive name, like "Skills Service" or "Static Web App".
   - purpose: 1-2 lines about what it does
   - flow: a list describing how it communicates or depends on other services or external pieces.

Finally, produce a simple 'graph_nodes' array, with each node having { "name", "type" } 
and a 'graph_edges' array, with each edge { "from", "to", "relationship" } 
representing connections or dependencies. 
(For example: "from=Static Web App, to=Skill Service, relationship=calls API".)

Output valid JSON ONLY in this structure:

{
  "azure_usage": true or false,
  "resource_group": "",
  "location": "",
  "monitoring_info": "",
  "services": [
    {
      "name": "...",
      "purpose": "...",
      "flow": ["..."]
    }
  ],
  "graph_nodes": [
    {"name": "...", "type": "..."}
  ],
  "graph_edges": [
    {"from": "...", "to": "...", "relationship": "..."}
  ]
}

No environment variables, no private IP subnets, no big details about subnets or code logic. 
Focus only on the above structure.
"""


def analyze_script(
        abs_path: str,
        content: str,
        api_key: str,
        provider: str,
        model_name: str,
        request_timeout: int
) -> ScriptAnalysis:
    """
    Calls the LLM with a fixed system prompt that yields JSON
    describing azure usage, resource group, location, monitoring,
    list of services with flow, plus graph nodes/edges.
    """
    system_prompt = build_system_prompt()
    user_prompt = f"Analyze this script:\n\n{content}"

    llm_response = call_llm(
        api_key=api_key,
        provider=provider,
        model_name=model_name,
        system_prompt=system_prompt,
        user_prompt=user_prompt,
        temperature=0.0,
        max_tokens=8192,
        request_timeout=request_timeout
    )

    # Attempt to parse JSON
    try:
        start = llm_response.find("{")
        end = llm_response.rfind("}") + 1
        if start == -1 or end == -1:
            logger.warning(f"Could not parse JSON for {abs_path}. Using defaults.")
            return ScriptAnalysis(
                script_abs_path=abs_path,
                azure_usage=False,
                resource_group="",
                location="",
                monitoring_info="",
                services=[],
                graph_nodes=[],
                graph_edges=[]
            )
        json_str = llm_response[start:end]
        data = json.loads(json_str)
    except Exception as e:
        logger.error(f"Error parsing JSON from script {abs_path}: {e}")
        data = {
            "azure_usage": False,
            "resource_group": "",
            "location": "",
            "monitoring_info": "",
            "services": [],
            "graph_nodes": [],
            "graph_edges": []
        }

    # Build final
    azure_usage = bool(data.get("azure_usage", False))
    resource_group = data.get("resource_group") or ""
    location = data.get("location") or ""
    monitoring_info = data.get("monitoring_info") or ""

    services_data = data.get("services", [])
    services_list: List[ServiceNode] = []
    for sd in services_data:
        name = sd.get("name", "Unknown Service")
        purpose = sd.get("purpose", "")
        flow = sd.get("flow", [])
        if not isinstance(flow, list):
            flow = []
        services_list.append(ServiceNode(name, purpose, flow))

    nodes_data = data.get("graph_nodes", [])
    nodes_list: List[GraphNode] = []
    for nd in nodes_data:
        nname = nd.get("name", "")
        ntype = nd.get("type", "")
        nodes_list.append(GraphNode(nname, ntype))

    edges_data = data.get("graph_edges", [])
    edges_list: List[GraphEdge] = []
    for ed in edges_data:
        f = ed.get("from", "")
        t = ed.get("to", "")
        rel = ed.get("relationship", "")
        edges_list.append(GraphEdge(f, t, rel))

    return ScriptAnalysis(
        script_abs_path=abs_path,
        azure_usage=azure_usage,
        resource_group=resource_group,
        location=location,
        monitoring_info=monitoring_info,
        services=services_list,
        graph_nodes=nodes_list,
        graph_edges=edges_list
    )


###############################################################################
#                      MARKDOWN GENERATION PER SCRIPT
###############################################################################
def get_service_name_from_path(script_path: Path, repo_root: Path) -> str:
    """
    Extract the top-level folder name from the script path relative to repo root.
    This represents the service that owns the infrastructure.
    """
    try:
        rel_path = script_path.relative_to(repo_root)
        parts = rel_path.parts
        if len(parts) > 1:  # At least one folder plus filename
            return parts[0]
        return "unknown"
    except Exception:
        return "unknown"


def generate_markdown_for_script(
        analysis: ScriptAnalysis,
        repo_root: Path
) -> str:
    """
    Creates the single .md for a given script.
    Sections:
    1. Title
    2. Overview (main Azure services)
    3. Cloud Information
    4. Resource info
    5. Monitoring
    6. Services with integrated flow info
    7. Infrastructure Network Graph (Redis-compatible format)
    """
    rel_path = os.path.relpath(analysis.script_abs_path, repo_root)
    lines = []
    lines.append(f"# Infra Analysis for Script: {rel_path}\n\n")

    # Overview section listing main Azure services
    lines.append("## Overview\n\n")
    main_services = [svc for svc in analysis.services
                     if not any(x in svc.name.lower()
                                for x in ['network', 'monitor', 'log', 'diagnostic'])]
    if main_services:
        lines.append("Main cloud services used:\n\n")
        for svc in main_services:
            lines.append(f"- {svc.name}\n")
    else:
        lines.append("No main cloud services identified.\n")
    lines.append("\n")

    # Cloud Information
    lines.append("## Cloud Information\n\n")
    if analysis.azure_usage:
        lines.append("Services run on Azure cloud infrastructure.\n\n")
    else:
        lines.append("No clear cloud provider usage identified.\n\n")

    # Resource info
    if analysis.resource_group or analysis.location:
        lines.append("## Resource Info\n\n")
        if analysis.resource_group:
            lines.append(f"- **Resource Group**: {analysis.resource_group}\n")
        if analysis.location:
            lines.append(f"- **Location**: {analysis.location}\n")
        lines.append("\n")

    # Monitoring
    if analysis.monitoring_info:
        lines.append("## Monitoring Info\n\n")
        lines.append(f"{analysis.monitoring_info}\n\n")

    # Services with integrated flow
    if analysis.services:
        lines.append("## Services\n\n")
        for svc in analysis.services:
            lines.append(f"### {svc.name}\n")
            lines.append(f"**Purpose**: {svc.purpose}\n\n")
            if svc.flow:
                lines.append("**Service Flow**:\n")
                for f_item in svc.flow:
                    lines.append(f"- {f_item}\n")
                lines.append("\n")
    else:
        lines.append("No services found in this script.\n\n")

    # Infrastructure network graph (Redis-compatible format)
    lines.append("## Infrastructure Network Graph\n\n")

    # Get service name from script path for Redis key prefix
    service_name = get_service_name_from_path(Path(analysis.script_abs_path), repo_root)

    # Nodes (using hash)
    if analysis.graph_nodes:
        lines.append("**Redis Node Storage Format**:\n")
        lines.append("```\n")
        lines.append("# Using Redis HASH for nodes\n")
        for i, node in enumerate(analysis.graph_nodes):
            hash_key = f"{service_name}.node.{node.name}"
            lines.append(f"HSET {hash_key} name {node.name} type {node.type}\n")
        lines.append("```\n\n")
    else:
        lines.append("_No graph nodes found._\n\n")

    # Edges (using hash)
    if analysis.graph_edges:
        lines.append("**Redis Edge Storage Format**:\n")
        lines.append("```\n")
        lines.append("# Using Redis HASH for edges\n")
        for i, edge in enumerate(analysis.graph_edges):
            hash_key = f"{service_name}.edge.{i}"
            lines.append(
                f"HSET {hash_key} from_node {edge.from_node} to_node {edge.to_node} relationship {edge.relationship}\n")
        lines.append("```\n\n")

        # Store unique relationship types (using set)
        relationships = {edge.relationship for edge in analysis.graph_edges}
        if relationships:
            lines.append("**Redis Relationship Types Storage Format**:\n")
            lines.append("```\n")
            lines.append("# Using Redis SET for relationship types\n")
            lines.append(
                f"SADD {service_name}.relationship.types " + " ".join(f'"{rel}"' for rel in relationships) + "\n")
            lines.append("```\n")
    else:
        lines.append("_No graph edges found._\n\n")

    return "".join(lines)


###############################################################################
#                         MAIN: GENERATE ONE DOC PER SCRIPT
###############################################################################
def read_script_content(script_path: str) -> str:
    """Read script content with fallback for encoding."""
    try:
        with open(script_path, 'r', encoding='utf-8', errors='replace') as f:
            return f.read()
    except UnicodeError:
        try:
            with open(script_path, 'rb') as f:
                content = f.read()
                return content.decode('utf-8', errors='replace')
        except Exception as e:
            logger.error(f"Failed to read {script_path}: {e}")
            return ""


def find_infra_scripts(root_dir: str) -> List[Tuple[str, str]]:
    """
    Find *.sh files with 'infra' in the name, excluding 'orchestrate'.
    Return (absolute_path, relative_path).
    """
    root_path = Path(root_dir).resolve()
    scripts = []
    for script_path in root_path.rglob('*.sh'):
        if 'infra' in script_path.name.lower() and 'orchestrate' not in script_path.name.lower():
            abs_path = script_path.resolve()
            rel_path = abs_path.relative_to(root_path)
            scripts.append((str(abs_path), str(rel_path)))
    return scripts


def main():
    parser = argparse.ArgumentParser(
        description="Parse infra scripts to produce a per-script doc with Azure usage, resource info, services flow, and network graph."
    )
    parser.add_argument(
        "--input",
        required=True,
        help="Root directory with shell scripts."
    )
    parser.add_argument(
        "--api-key",
        required=True,
        help="LLM API key (OpenAI or Anthropic)."
    )
    parser.add_argument(
        "--provider",
        default="openai",
        choices=["openai", "anthropic"],
        help="Which LLM provider to use."
    )
    parser.add_argument(
        "--model-name",
        default="gpt-4",
        help="Model name or version to use."
    )
    parser.add_argument(
        "--debug",
        action="store_true",
        help="Enable debug logging."
    )
    parser.add_argument(
        "--api-timeout",
        type=int,
        default=60,
        help="Timeout for LLM calls in seconds."
    )
    args = parser.parse_args()

    # Configure logging
    level = logging.DEBUG if args.debug else logging.INFO
    logger = create_console_logger(level=level)

    start_time = time.time()
    logger.info(f"Searching for infra scripts in: {args.input}")

    # 1) Discover scripts
    scripts = find_infra_scripts(args.input)
    logger.info(f"Found {len(scripts)} infrastructure scripts.")
    if not scripts:
        logger.info("No infra scripts found, exiting.")
        return

    # 2) For each script, parse content, call LLM, produce doc
    root_path = Path(args.input).resolve()
    for abs_path, rel_path in scripts:
        content = read_script_content(abs_path)
        if not content:
            logger.warning(f"Skipping empty/unreadable script: {abs_path}")
            continue

        analysis = analyze_script(
            abs_path=abs_path,
            content=content,
            api_key=args.api_key,
            provider=args.provider,
            model_name=args.model_name,
            request_timeout=args.api_timeout
        )

        # 3) Generate and save .md next to the script
        md_out = generate_markdown_for_script(analysis, root_path)
        script_file = Path(abs_path)
        script_dir = script_file.parent
        md_name = "RESULT_infrastructure.ai-generated.md"
        md_path = script_dir / md_name
        with open(md_path, "w", encoding="utf-8") as f:
            f.write(md_out)
        logger.info(f"Wrote doc for {script_file.name} to {md_path}")

    elapsed = time.time() - start_time
    logger.info(f"Done. Process took {elapsed:.2f}s.")


if __name__ == "__main__":
    main()
