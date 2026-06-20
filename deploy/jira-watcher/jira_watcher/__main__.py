"""Point d'entrée du watcher JIRA → /mike.

Usage :
    python -m jira_watcher [--dry-run] [--config /chemin/config.yaml]

Options :
    --dry-run   Lister les tickets éligibles sans poser de label ni lancer /mike.
    --config    Chemin vers config.yaml (défaut : /etc/jira-watcher/config.yaml).
"""
from __future__ import annotations

import argparse
import json
import logging
import os
import sys
from pathlib import Path

import yaml
import requests

from jira_watcher.config import ConfigError, load_config
from jira_watcher.jira_client import JiraClient, JiraHttpError
from jira_watcher.jql import build_jql
from jira_watcher.mike_runner import run as mike_run
from jira_watcher.orchestrator import RunReport, process

# ---------------------------------------------------------------------------
# Configuration du logging structuré (JSON-friendly en prod, lisible en dev)
# ---------------------------------------------------------------------------

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(name)s %(message)s",
    stream=sys.stdout,
)
logger = logging.getLogger("jira_watcher")

_DEFAULT_CONFIG_PATH = "/etc/jira-watcher/config.yaml"


# ---------------------------------------------------------------------------
# Fonctions pures testables
# ---------------------------------------------------------------------------


def run_dry_run(client: JiraClient, config) -> list[str]:
    """Mode dry-run : retourne les clés éligibles sans aucun effet de bord.

    Args:
        client: client JIRA.
        config: configuration du watcher.

    Returns:
        Liste des clés de tickets éligibles.
    """
    jql = build_jql(config)
    keys = client.search_keys(jql, max_results=config.max_issues_per_run)
    logger.info("[dry-run] %d ticket(s) éligible(s) : %s", len(keys), keys)
    return keys


# ---------------------------------------------------------------------------
# Runner de production (wrapper autour de mike_run)
# ---------------------------------------------------------------------------


def _production_runner(key: str, config) -> object:
    """Runner de production : appelle mike_run avec subprocess réel."""
    return mike_run(key, config)


# ---------------------------------------------------------------------------
# Point d'entrée principal
# ---------------------------------------------------------------------------


def main(argv: list[str] | None = None) -> int:
    """Point d'entrée principal du watcher.

    Returns:
        Code de sortie : 0 si tout s'est bien passé (y compris échecs /mike
        non bloquants), ≠ 0 en cas d'erreur d'infrastructure (auth, réseau,
        config invalide).
    """
    parser = argparse.ArgumentParser(
        prog="jira_watcher",
        description="Watcher JIRA → déclencheur /mike headless",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Lister les tickets éligibles sans action",
    )
    parser.add_argument(
        "--config",
        default=_DEFAULT_CONFIG_PATH,
        help=f"Chemin vers config.yaml (défaut : {_DEFAULT_CONFIG_PATH})",
    )
    args = parser.parse_args(argv)

    # 1. Charger la configuration
    config_path = Path(args.config)
    if not config_path.exists():
        logger.error("Fichier de configuration introuvable : %s", config_path)
        return 1

    try:
        with config_path.open() as f:
            raw = yaml.safe_load(f)
        config = load_config(raw)
    except ConfigError as exc:
        logger.error("Configuration invalide : %s", exc)
        return 1

    # 2. Récupérer les credentials JIRA depuis l'environnement
    jira_email = os.environ.get("JIRA_EMAIL", "")
    jira_token = os.environ.get("JIRA_API_TOKEN", "")

    if not jira_email or not jira_token:
        logger.error(
            "Variables d'environnement JIRA_EMAIL et JIRA_API_TOKEN requises"
        )
        return 1

    # 3. Instancier le client JIRA
    http_session = requests.Session()
    client = JiraClient(
        base_url=config.jira_base_url,
        email=jira_email,
        token=jira_token,
        http=http_session,
    )

    # 4. Mode dry-run : lister les tickets et sortir
    if args.dry_run:
        try:
            keys = run_dry_run(client, config)
            print(json.dumps({"dry_run": True, "eligible_keys": keys}, ensure_ascii=False))
        except JiraHttpError as exc:
            logger.error("Erreur JIRA (dry-run) : %s", exc)
            return 1
        return 0

    # 5. Cycle complet
    try:
        report = process(client, config, _production_runner)
    except JiraHttpError as exc:
        logger.error("Erreur d'infrastructure JIRA : %s", exc)
        return 1

    # 6. Logguer le rapport JSON
    report_json = json.dumps(report.to_dict(), ensure_ascii=False)
    logger.info("RunReport : %s", report_json)
    print(report_json)

    # Code de sortie ≠ 0 seulement si tous les tickets ont échoué
    # (un seul succès = cycle viable)
    if report.processed > 0 and report.ok == 0 and report.failed == report.processed:
        logger.warning("Tous les runs /mike ont échoué ce cycle.")
        return 1

    return 0


if __name__ == "__main__":
    sys.exit(main())
