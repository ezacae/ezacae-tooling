"""Orchestrateur du watcher JIRA → /mike.

Séquence pour chaque cycle :
1. Construire le JQL depuis la config
2. Rechercher les clés éligibles via le client JIRA
3. Pour chaque clé (dans la limite de max_issues_per_run) :
   a. Poser le label de claim (déduplication)
   b. Lancer /mike via le runner injecté
   c. Comptabiliser le résultat (OK / FAILED / TIMEOUT)
4. Retourner le RunReport

Tout est injecté (client, runner) pour la testabilité.
"""
from __future__ import annotations

import logging
from dataclasses import dataclass, field
from typing import Any, Callable

from jira_watcher.config import WatcherConfig
from jira_watcher.jira_client import JiraClient, JiraHttpError
from jira_watcher.jql import build_jql
from jira_watcher.mike_runner import MikeResult

logger = logging.getLogger(__name__)

# Marge demandée au-delà de max_issues_per_run pour détecter les tickets ignorés.
_LOOKAHEAD = 50


@dataclass
class RunReport:
    """Rapport de fin de cycle du watcher."""

    seen: int          # nombre de tickets éligibles trouvés
    processed: int     # nombre de tickets effectivement traités (≤ max_issues_per_run)
    ok: int            # runs /mike ayant réussi
    failed: int        # runs /mike ayant échoué ou timeout (échec fonctionnel)
    skipped: int       # tickets non traités car plafond atteint
    infra_failed: int = 0  # échecs d'infrastructure (claim JIRA / auth / réseau)
    errors: list[str] = field(default_factory=list)  # messages d'erreur détaillés

    def to_dict(self) -> dict[str, Any]:
        return {
            "seen": self.seen,
            "processed": self.processed,
            "ok": self.ok,
            "failed": self.failed,
            "skipped": self.skipped,
            "infra_failed": self.infra_failed,
            "errors": self.errors,
        }


def process(
    client: JiraClient,
    config: WatcherConfig,
    runner: Callable,
) -> RunReport:
    """Exécute un cycle complet du watcher.

    Args:
        client: client JIRA injecté (JiraClient ou fake).
        config: configuration validée du watcher.
        runner: callable de type RunnerCallable (ou fake).

    Returns:
        RunReport résumant le cycle.
    """
    jql = build_jql(config)
    # On demande un peu plus que le plafond pour pouvoir calculer skipped.
    keys = client.search_keys(jql, max_results=config.max_issues_per_run + _LOOKAHEAD)

    seen = len(keys)
    to_process = keys[: config.max_issues_per_run]
    skipped = seen - len(to_process)

    if skipped > 0:
        logger.warning(
            "Plafond atteint : %d ticket(s) ignoré(s) ce cycle (max_issues_per_run=%d)",
            skipped,
            config.max_issues_per_run,
        )

    ok = 0
    failed = 0
    infra_failed = 0
    errors: list[str] = []

    for key in to_process:
        # 1. Poser le claim AVANT le run (déduplication).
        #    Un échec ici est une erreur d'INFRASTRUCTURE (auth/permission/réseau
        #    JIRA), distincte d'un échec fonctionnel de /mike : on ne lance pas
        #    le run et on le comptabilise comme infra_failed (→ code de sortie ≠ 0).
        try:
            client.add_label(key, config.claim_label)
        except JiraHttpError as exc:
            msg = f"[{key}] Impossible de poser le label de claim : {exc}"
            logger.error(msg)
            errors.append(msg)
            infra_failed += 1
            continue

        # 2. Lancer /mike via le runner injecté
        result: MikeResult = runner(key, config)

        if result.status == "OK":
            ok += 1
            logger.info("[%s] /mike terminé avec succès.", key)
        else:
            failed += 1
            msg = (
                f"[{key}] /mike a échoué (status={result.status}, "
                f"exit_code={result.exit_code}) — log: {result.log_tail[-200:]}"
            )
            logger.error(msg)
            errors.append(msg)
            # On conserve intentionnellement le label de claim (pas de rollback).
            # Reprise manuelle = retrait du label claude-traite.

    return RunReport(
        seen=seen,
        processed=len(to_process),
        ok=ok,
        failed=failed,
        skipped=skipped,
        infra_failed=infra_failed,
        errors=errors,
    )
