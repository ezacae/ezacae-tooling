"""Tests pour jira_watcher.jql — construction de la requête JQL."""
from jira_watcher.jql import build_jql
from tests.factories import make_config


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

    def test_valeur_avec_guillemet_echappee(self):
        """Un guillemet dans une valeur doit être échappé (anti-casse de requête)."""
        config = make_config(watched_statuses=['EN "ATTENTE"'])
        jql = build_jql(config)
        # Le guillemet interne est précédé d'un backslash, les guillemets
        # délimiteurs restent présents.
        assert r'"EN \"ATTENTE\""' in jql

    def test_valeur_avec_backslash_echappee(self):
        """Un backslash dans une valeur doit être doublé."""
        config = make_config(projects=[r"A\B"])
        jql = build_jql(config)
        assert r'"A\\B"' in jql

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
