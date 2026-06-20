"""Construction de la requête JQL pour le watcher JIRA.

Fonction pure : aucun effet de bord, pas d'accès réseau.
"""
from __future__ import annotations

from jira_watcher.config import WatcherConfig


def _quote(value: str) -> str:
    """Échappe puis entoure une valeur de guillemets pour la JQL.

    On échappe `\\` puis `"` afin qu'une valeur contenant un guillemet
    (ex. un libellé de statut) ne casse pas la requête ni n'en altère le sens.
    """
    escaped = value.replace("\\", "\\\\").replace('"', '\\"')
    return f'"{escaped}"'


def build_jql(config: WatcherConfig) -> str:
    """Construit la requête JQL à partir de la configuration.

    La requête sélectionne les tickets :
    - appartenant aux projets surveillés
    - portant l'étiquette trigger_label
    - ayant un statut dans watched_statuses
    - ne portant PAS encore l'étiquette claim_label (déduplication)

    Résultats triés par date de création croissante (les plus anciens d'abord).

    Args:
        config: configuration validée du watcher.

    Returns:
        Chaîne JQL prête à être envoyée à l'API REST JIRA.
    """
    # Liste des projets : project IN ("CRM","ACME")
    projects_list = ",".join(_quote(p) for p in config.projects)
    clause_projects = f"project IN ({projects_list})"

    # Étiquette déclencheuse : labels = "claude"
    clause_trigger = f"labels = {_quote(config.trigger_label)}"

    # Statuts déclencheurs : status IN ("NOUVEAU")
    statuses_list = ",".join(_quote(s) for s in config.watched_statuses)
    clause_status = f"status IN ({statuses_list})"

    # Exclusion du claim (déduplication) : labels NOT IN ("claude-traite")
    clause_claim = f"labels NOT IN ({_quote(config.claim_label)})"

    # Tri
    order = "ORDER BY created ASC"

    return " AND ".join(
        [clause_projects, clause_trigger, clause_status, clause_claim]
    ) + " " + order
