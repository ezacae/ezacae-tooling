"""Tests pour jira_watcher.jql — construction de la requête JQL."""
import pytest
from jira_watcher.config import WatcherConfig
from jira_watcher.jql import build_jql


def make_config(**overrides) -> WatcherConfig:
    defaults = {
        "jira_base_url": "https://ezacae.atlassian.net",
        "projects": ["CRM"],
        "trigger_label": "claude",
        "claim_label": "claude-traite",
        "watched_statuses": ["NOUVEAU"],
        "slash_command": "/mike {key}",
        "claude_timeout_seconds": 3600,
        "max_issues_per_run": 10,
    }
    from jira_watcher.config import load_config

    defaults.update(overrides)
    return load_config(defaults)


class TestBuildJql:
    def test_un_projet(self):
        config = make_config(projects=["CRM"])
        jql = build_jql(config)
        assert 'project IN ("CRM")' in jql

    def test_plusieurs_projets(self):
        config = make_config(projects=["CRM", "ACME", "DEMO"])
        jql = build_jql(config)
        assert 'project IN ("CRM","ACME","DEMO")' in jql

    def test_contient_clause_trigger_label(self):
        config = make_config(trigger_label="claude")
        jql = build_jql(config)
        assert 'labels = "claude"' in jql

    def test_contient_clause_claim_label_exclusion(self):
        config = make_config(claim_label="claude-traite")
        jql = build_jql(config)
        assert 'labels NOT IN ("claude-traite")' in jql

    def test_un_statut(self):
        config = make_config(watched_statuses=["NOUVEAU"])
        jql = build_jql(config)
        assert 'status IN ("NOUVEAU")' in jql

    def test_plusieurs_statuts(self):
        config = make_config(watched_statuses=["NOUVEAU", "OUVERT"])
        jql = build_jql(config)
        assert 'status IN ("NOUVEAU","OUVERT")' in jql

    def test_tri_created_asc(self):
        config = make_config()
        jql = build_jql(config)
        assert "ORDER BY created ASC" in jql

    def test_resultat_est_une_chaine(self):
        config = make_config()
        assert isinstance(build_jql(config), str)

    def test_valeur_avec_espace_echappee(self):
        """Les valeurs contenant des espaces doivent être entre guillemets."""
        config = make_config(watched_statuses=["EN COURS"])
        jql = build_jql(config)
        assert '"EN COURS"' in jql

    def test_structure_complete(self):
        """Vérifie l'ordre des clauses dans la requête complète."""
        config = make_config(projects=["CRM", "ACME"])
        jql = build_jql(config)
        # Toutes les clauses présentes
        assert "project IN" in jql
        assert "labels =" in jql
        assert "status IN" in jql
        assert "labels NOT IN" in jql
        assert "ORDER BY created ASC" in jql
        # Ordre : project → labels = → status → labels NOT IN → ORDER BY
        idx_project = jql.index("project IN")
        idx_trigger = jql.index("labels =")
        idx_status = jql.index("status IN")
        idx_claim = jql.index("labels NOT IN")
        idx_order = jql.index("ORDER BY")
        assert idx_project < idx_trigger < idx_status < idx_claim < idx_order
