"""Fabriques partagées pour les tests du watcher.

Évite la duplication du helper `make_config` entre les modules de tests.
"""
from __future__ import annotations

from jira_watcher.config import WatcherConfig, load_config

_CONFIG_DEFAULTS = {
    "jira_base_url": "https://ezacae.atlassian.net",
    "projects": ["CRM"],
    "trigger_label": "claude",
    "claim_label": "claude-traite",
    "watched_statuses": ["NOUVEAU"],
    "slash_command": "/mike {key}",
    "claude_timeout_seconds": 3600,
    "max_issues_per_run": 10,
}


def make_config(**overrides) -> WatcherConfig:
    """Construit un WatcherConfig valide, surchargé par les `overrides`."""
    return load_config({**_CONFIG_DEFAULTS, **overrides})
