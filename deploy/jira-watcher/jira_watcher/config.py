"""Configuration du watcher JIRA.

Charge et valide la ConfigMap montée en /etc/jira-watcher/config.yaml.
Toute erreur de validation lève ConfigError avec un message explicite.
"""
from __future__ import annotations

from dataclasses import dataclass
from typing import Any


class ConfigError(ValueError):
    """Erreur de validation de la configuration du watcher."""


@dataclass(frozen=True)
class WatcherConfig:
    """Configuration validée du watcher (immuable)."""

    jira_base_url: str
    projects: list[str]
    trigger_label: str
    claim_label: str
    watched_statuses: list[str]
    slash_command: str
    claude_timeout_seconds: int
    max_issues_per_run: int


def load_config(mapping: dict[str, Any]) -> WatcherConfig:
    """Construit et valide un WatcherConfig depuis un mapping YAML.

    Args:
        mapping: dictionnaire issu du parsing de config.yaml.

    Returns:
        WatcherConfig validé et immuable.

    Raises:
        ConfigError: si une règle de validation est violée.
    """
    jira_base_url: str = mapping.get("jira_base_url", "")
    if not jira_base_url or not jira_base_url.startswith("http"):
        raise ConfigError(
            f"jira_base_url doit commencer par 'http', reçu : {jira_base_url!r}"
        )

    projects: list[str] = list(mapping.get("projects", []))
    if not projects:
        raise ConfigError("projects ne peut pas être vide")

    trigger_label: str = str(mapping.get("trigger_label", ""))
    if not trigger_label:
        raise ConfigError("trigger_label ne peut pas être vide")

    claim_label: str = str(mapping.get("claim_label", ""))
    if not claim_label:
        raise ConfigError("claim_label ne peut pas être vide")

    watched_statuses: list[str] = list(mapping.get("watched_statuses", []))
    if not watched_statuses:
        raise ConfigError("watched_statuses ne peut pas être vide")

    slash_command: str = mapping.get("slash_command", "")
    if "{key}" not in slash_command:
        raise ConfigError(
            f"slash_command doit contenir le placeholder {{key}}, reçu : {slash_command!r}"
        )

    claude_timeout_seconds: int = int(mapping.get("claude_timeout_seconds", 0))
    if claude_timeout_seconds <= 0:
        raise ConfigError(
            f"claude_timeout_seconds doit être > 0, reçu : {claude_timeout_seconds}"
        )

    max_issues_per_run: int = int(mapping.get("max_issues_per_run", 0))
    if max_issues_per_run <= 0:
        raise ConfigError(
            f"max_issues_per_run doit être > 0, reçu : {max_issues_per_run}"
        )

    return WatcherConfig(
        jira_base_url=jira_base_url,
        projects=projects,
        trigger_label=trigger_label,
        claim_label=claim_label,
        watched_statuses=watched_statuses,
        slash_command=slash_command,
        claude_timeout_seconds=claude_timeout_seconds,
        max_issues_per_run=max_issues_per_run,
    )
