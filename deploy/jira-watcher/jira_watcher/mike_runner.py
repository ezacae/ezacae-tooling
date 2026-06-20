"""Lanceur /mike en mode headless via la CLI claude.

Deux fonctions exportées :
- build_invocation : pure, construit argv / prompt / env sans effet de bord.
- run              : exécute via un runner injecté (testable sans subprocess réel).
"""
from __future__ import annotations

import os
import subprocess
from dataclasses import dataclass
from typing import Any, Callable

from jira_watcher.config import WatcherConfig


@dataclass
class MikeResult:
    """Résultat d'un run /mike."""

    status: str  # "OK" | "FAILED" | "TIMEOUT"
    exit_code: int
    log_tail: str


# Type du runner injecté
RunnerCallable = Callable[
    [list[str], str, dict[str, str], int],
    Any,  # retourne un objet avec .returncode, .stdout, .stderr
]

# Nombre maximum de lignes conservées dans log_tail
_LOG_TAIL_LINES = 20


def build_invocation(
    key: str, config: WatcherConfig
) -> tuple[list[str], str, dict[str, str]]:
    """Construit l'invocation claude headless (pure, pas d'effet de bord).

    Args:
        key: clé du ticket JIRA (ex. "CRM-1").
        config: configuration validée du watcher.

    Returns:
        Tuple (argv, prompt, env) :
        - argv  : liste d'arguments pour subprocess (["claude", "-p", ...])
        - prompt: texte du prompt passé à claude (slash command substituée)
        - env   : variables d'environnement à transmettre au process
    """
    prompt = config.slash_command.replace("{key}", key)

    argv = [
        "claude",
        "-p",
        prompt,
        "--dangerously-skip-permissions",
        "--output-format",
        "json",
    ]

    # Hériter de l'environnement courant (credentials montés dans HOME)
    env = dict(os.environ)

    return argv, prompt, env


def _default_runner(
    argv: list[str], prompt: str, env: dict[str, str], timeout: int
) -> Any:
    """Runner de production : appelle subprocess.run.

    `prompt` est déjà inclus dans `argv` (option `-p`) ; il n'est conservé
    dans la signature que pour le logging et les tests (paramètre non utilisé ici).
    """
    return subprocess.run(
        argv,
        capture_output=True,
        text=True,
        timeout=timeout,
        env=env,
    )


def run(
    key: str,
    config: WatcherConfig,
    runner: RunnerCallable = _default_runner,
) -> MikeResult:
    """Exécute /mike pour la clé donnée via le runner injecté.

    Le runner est appelé avec (argv, prompt, env, timeout).

    Args:
        key: clé du ticket JIRA.
        config: configuration validée du watcher.
        runner: callable à appeler (injectez un fake pour les tests).

    Returns:
        MikeResult avec status "OK", "FAILED" ou "TIMEOUT".
    """
    argv, prompt, env = build_invocation(key, config)

    try:
        proc = runner(argv, prompt, env, config.claude_timeout_seconds)
    except subprocess.TimeoutExpired:
        return MikeResult(status="TIMEOUT", exit_code=-1, log_tail="Process timed out")

    # Construire le log_tail depuis stderr (priorité) ou stdout
    raw_output = proc.stderr if proc.stderr else proc.stdout
    lines = raw_output.strip().splitlines() if raw_output else []
    log_tail = "\n".join(lines[-_LOG_TAIL_LINES:])

    if proc.returncode == 0:
        return MikeResult(status="OK", exit_code=0, log_tail=log_tail)
    else:
        return MikeResult(status="FAILED", exit_code=proc.returncode, log_tail=log_tail)
