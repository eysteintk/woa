from dataclasses import dataclass
from typing import Dict, List, Tuple, Optional, Set
from pathlib import Path
import hashlib
from datetime import datetime
import json
import os
from functools import partial
import typer
from rich.console import Console
from rich.progress import Progress, SpinnerColumn, TextColumn
from rich.prompt import Confirm
from rich.table import Table
import redis
import getpass
import base64

app = typer.Typer(help="File synchronization tool using Azure Redis Cache")
console = Console()


@dataclass(frozen=True)
class FileMetadata:
    """Immutable file metadata"""
    timestamp: datetime
    user: str
    file_hash: str
    last_modified: datetime


@dataclass(frozen=True)
class RedisConfig:
    """Redis connection details"""
    host: str
    port: int
    password: str
    ssl: bool = True


@dataclass(frozen=True)
class RemoteFile:
    """Remote file state from Redis"""
    hash: str
    timestamp: datetime
    user: str
    content: bytes


def read_redis_config() -> RedisConfig:
    """Read Redis configuration from Azure CLI or environment variables"""
    # First try environment variables
    host = os.getenv('REDIS_HOST')
    password = os.getenv('REDIS_PASSWORD')

    if not (host and password):
        try:
            # Try to get from Azure CLI
            import subprocess
            result = subprocess.run(
                ['az', 'redis', 'show', '--name', os.getenv('REDIS_NAME', ''), '--resource-group',
                 os.getenv('REDIS_RG', '')],
                capture_output=True,
                text=True
            )
            if result.returncode == 0:
                data = json.loads(result.stdout)
                host = data['hostName']
                # Note: Password needs to be set via REDIS_PASSWORD env var for security
                if not password:
                    console.print("[red]Please set REDIS_PASSWORD environment variable[/red]")
                    raise typer.Exit(1)
            else:
                console.print("[red]Error getting Redis details from Azure CLI[/red]")
                console.print("Please set REDIS_HOST and REDIS_PASSWORD environment variables")
                raise typer.Exit(1)
        except FileNotFoundError:
            console.print("[red]Azure CLI not found[/red]")
            console.print("Please set REDIS_HOST and REDIS_PASSWORD environment variables")
            raise typer.Exit(1)

    return RedisConfig(
        host=host,
        port=6380,  # Azure Redis Cache default SSL port
        password=password,
        ssl=True
    )


def get_redis_key(folder: Path, filepath: str) -> str:
    """Create Redis key for a file"""
    prefix = str(folder).lower().replace(os.path.sep, ':')
    return f"file-sync:{prefix}:{filepath}"


def calculate_file_hash(file_path: Path) -> str:
    """Calculate SHA-256 hash of file contents"""
    sha256_hash = hashlib.sha256()
    with open(file_path, "rb") as f:
        for byte_block in iter(lambda: f.read(4096), b""):
            sha256_hash.update(byte_block)
    return sha256_hash.hexdigest()


def get_remote_files(folder: Path, redis_client: redis.Redis) -> Dict[str, RemoteFile]:
    """Get the current state of files from Redis"""
    prefix = get_redis_key(folder, '')
    remote_files = {}

    # Get all keys with our prefix
    for key in redis_client.scan_iter(f"{prefix}*"):
        key_str = key.decode('utf-8')
        rel_path = key_str.split(':', 2)[2]  # Get filepath part

        # Get metadata and content
        metadata = redis_client.hgetall(f"{key_str}:metadata")
        if not metadata:
            continue

        content = redis_client.get(key_str)
        if not content:
            continue

        # Convert from Redis format
        remote_files[rel_path] = RemoteFile(
            hash=metadata[b'hash'].decode('utf-8'),
            timestamp=datetime.fromisoformat(metadata[b'timestamp'].decode('utf-8')),
            user=metadata[b'user'].decode('utf-8'),
            content=base64.b64decode(content)
        )

    return remote_files


def find_changes(
        folder: Path,
        remote_files: Dict[str, RemoteFile]
) -> Tuple[Dict[str, Path], Dict[str, RemoteFile]]:
    """Find files that need to be pushed or pulled"""
    to_push: Dict[str, Path] = {}
    to_pull: Dict[str, RemoteFile] = {}

    # Check local files against remote
    for file_path in folder.rglob('*'):
        if not file_path.is_file():
            continue

        rel_path = str(file_path.relative_to(folder))
        local_hash = calculate_file_hash(file_path)

        remote = remote_files.get(rel_path)
        if remote is None:
            # New file, needs push
            to_push[rel_path] = file_path
        elif remote.hash != local_hash:
            # File changed, compare timestamps
            local_time = datetime.fromtimestamp(file_path.stat().st_mtime)
            if local_time > remote.timestamp:
                to_push[rel_path] = file_path
            else:
                to_pull[rel_path] = remote

    # Check remote files against local
    for rel_path, remote in remote_files.items():
        local_path = folder / rel_path
        if not local_path.exists():
            to_pull[rel_path] = remote

    return to_push, to_pull


def display_changes(
        to_push: Dict[str, Path],
        to_pull: Dict[str, RemoteFile]
) -> None:
    """Display pending changes in a table"""
    if not to_push and not to_pull:
        console.print("[green]Everything is up to date[/green]")
        return

    table = Table(title="Pending Changes")
    table.add_column("File")
    table.add_column("Action")
    table.add_column("Details")

    for rel_path in sorted(to_push.keys()):
        table.add_row(rel_path, "Push", "Local changes")

    for rel_path, remote in sorted(to_pull.items()):
        table.add_row(
            rel_path,
            "Pull",
            f"Changed by {remote.user} at {remote.timestamp.isoformat()}"
        )

    console.print(table)


@app.command()
def status(folder: Path):
    """Show sync status of files in a folder"""
    if not folder.is_dir():
        console.print(f"[red]Error: {folder} is not a directory[/red]")
        raise typer.Exit(1)

    # Get Redis connection
    redis_config = read_redis_config()
    redis_client = redis.Redis(
        host=redis_config.host,
        port=redis_config.port,
        password=redis_config.password,
        ssl=redis_config.ssl,
        decode_responses=False  # We handle binary data
    )

    try:
        # Get remote state
        with Progress(SpinnerColumn(), TextColumn("Checking remote state...")) as progress:
            remote_files = get_remote_files(folder, redis_client)

        # Find changes
        to_push, to_pull = find_changes(folder, remote_files)

        # Display changes
        display_changes(to_push, to_pull)

    finally:
        redis_client.close()


@app.command()
def push(folder: Path):
    """Push changed files from a folder to Redis"""
    if not folder.is_dir():
        console.print(f"[red]Error: {folder} is not a directory[/red]")
        raise typer.Exit(1)

    # Get Redis connection
    redis_config = read_redis_config()
    redis_client = redis.Redis(
        host=redis_config.host,
        port=redis_config.port,
        password=redis_config.password,
        ssl=redis_config.ssl,
        decode_responses=False
    )

    try:
        # Get remote state and find changes
        with Progress(SpinnerColumn(), TextColumn("Checking remote state...")) as progress:
            remote_files = get_remote_files(folder, redis_client)

        to_push, _ = find_changes(folder, remote_files)

        if not to_push:
            console.print("[green]Everything is up to date[/green]")
            return

        # Show changes and confirm
        table = Table(title="Files to Push")
        table.add_column("File")
        for rel_path in sorted(to_push.keys()):
            table.add_row(rel_path)

        console.print(table)

        if not Confirm.ask("Continue with push?"):
            return

        # Push changes
        with Progress(SpinnerColumn(), TextColumn("[progress.description]{task.description}")) as progress:
            for rel_path, file_path in to_push.items():
                try:
                    # Read file
                    with open(file_path, 'rb') as f:
                        content = f.read()

                    # Create metadata
                    file_hash = calculate_file_hash(file_path)
                    now = datetime.utcnow()

                    # Store in Redis
                    key = get_redis_key(folder, rel_path)
                    pipe = redis_client.pipeline()

                    # Store metadata
                    pipe.hmset(f"{key}:metadata", {
                        'timestamp': now.isoformat(),
                        'user': getpass.getuser(),
                        'hash': file_hash,
                        'last_modified': str(file_path.stat().st_mtime)
                    })

                    # Store content (base64 encoded for safety)
                    pipe.set(key, base64.b64encode(content))

                    pipe.execute()
                    progress.update(0, description=f"Pushed: {rel_path}")

                except Exception as e:
                    console.print(f"[red]Error pushing {rel_path}: {str(e)}[/red]")

    finally:
        redis_client.close()


@app.command()
def pull(folder: Path):
    """Pull files from Redis"""
    if not folder.is_dir():
        console.print(f"[red]Error: {folder} is not a directory[/red]")
        raise typer.Exit(1)

    # Get Redis connection
    redis_config = read_redis_config()
    redis_client = redis.Redis(
        host=redis_config.host,
        port=redis_config.port,
        password=redis_config.password,
        ssl=redis_config.ssl,
        decode_responses=False
    )

    try:
        # Get remote state and find changes
        with Progress(SpinnerColumn(), TextColumn("Checking remote state...")) as progress:
            remote_files = get_remote_files(folder, redis_client)

        _, to_pull = find_changes(folder, remote_files)

        if not to_pull:
            console.print("[green]Everything is up to date[/green]")
            return

        # Show changes and confirm
        table = Table(title="Files to Pull")
        table.add_column("File")
        table.add_column("Last Modified By")
        table.add_column("When")

        for rel_path, remote in sorted(to_pull.items()):
            table.add_row(
                rel_path,
                remote.user,
                remote.timestamp.isoformat()
            )

        console.print(table)

        if not Confirm.ask("Continue with pull?"):
            return

        # Pull changes
        with Progress(SpinnerColumn(), TextColumn("[progress.description]{task.description}")) as progress:
            for rel_path, remote in to_pull.items():
                try:
                    file_path = folder / rel_path
                    file_path.parent.mkdir(parents=True, exist_ok=True)

                    with open(file_path, 'wb') as f:
                        f.write(remote.content)

                    progress.update(0, description=f"Pulled: {rel_path}")

                except Exception as e:
                    console.print(f"[red]Error pulling {rel_path}: {str(e)}[/red]")

    finally:
        redis_client.close()


if __name__ == "__main__":
    app()