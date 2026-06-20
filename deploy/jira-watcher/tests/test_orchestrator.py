"""Tests pour jira_watcher.orchestrator — séquenceur du cycle complet.

Tout est injecté (client, runner) : aucun réseau ni subprocess réel.
"""
from __future__ import annotations

from unittest.mock import MagicMock

from jira_watcher.jira_client import JiraHttpError
from jira_watcher.mike_runner import MikeResult
from jira_watcher.orchestrator import RunReport, process
from tests.factories import make_config


def make_client(keys: list[str], add_label_raises=None) -> MagicMock:
    """Crée un client fake retournant les clés données."""
    client = MagicMock()
    client.search_keys.return_value = keys
    if add_label_raises:
        client.add_label.side_effect = add_label_raises
    return client


def make_runner(status: str = "OK", exit_code: int = 0) -> MagicMock:
    """Crée un runner fake retournant un MikeResult."""
    runner = MagicMock()
    runner.return_value = MikeResult(status=status, exit_code=exit_code, log_tail="")
    return runner


class TestRunReport:
    def test_instanciation(self):
        report = RunReport(seen=2, processed=2, ok=2, failed=0, skipped=0)
        assert report.seen == 2
        assert report.ok == 2

    def test_to_dict(self):
        report = RunReport(seen=3, processed=2, ok=1, failed=1, skipped=1)
        d = report.to_dict()
        assert d["seen"] == 3
        assert d["ok"] == 1
        assert d["failed"] == 1
        assert d["skipped"] == 1
        assert d["infra_failed"] == 0


class TestProcessHappyPath:
    def test_deux_cles_traitees(self):
        config = make_config()
        client = make_client(["CRM-1", "CRM-2"])
        runner = make_runner("OK")

        report = process(client, config, runner)

        assert report.seen == 2
        assert report.processed == 2
        assert report.ok == 2
        assert report.failed == 0

    def test_claim_pose_avant_run(self):
        """Le label claim doit être posé AVANT l'appel au runner."""
        config = make_config()
        call_order: list[str] = []
        client = MagicMock()
        client.search_keys.return_value = ["CRM-1"]

        def track_add_label(key, label):
            call_order.append(f"claim:{key}")

        client.add_label.side_effect = track_add_label

        def fake_runner(key, cfg, runner=None):
            call_order.append(f"run:{key}")
            return MikeResult(status="OK", exit_code=0, log_tail="")

        process(client, config, fake_runner)
        assert call_order.index("claim:CRM-1") < call_order.index("run:CRM-1")

    def test_claim_label_correct(self):
        config = make_config(claim_label="claude-traite")
        client = make_client(["CRM-1"])
        runner = make_runner("OK")

        process(client, config, runner)

        client.add_label.assert_called_with("CRM-1", "claude-traite")

    def test_zero_ticket_run_report_vide(self):
        config = make_config()
        client = make_client([])
        runner = make_runner("OK")

        report = process(client, config, runner)

        assert report.seen == 0
        assert report.processed == 0
        runner.assert_not_called()


class TestProcessEchec:
    def test_run_echoue_conserve_claim_et_compte_failed(self):
        config = make_config()
        client = make_client(["CRM-1"])
        runner = make_runner("FAILED", exit_code=1)

        report = process(client, config, runner)

        # Le label de claim NE doit PAS être retiré
        client.remove_label.assert_not_called()
        assert report.failed == 1
        assert report.ok == 0

    def test_run_echoue_ne_leve_pas_exception(self):
        """Un échec /mike ne doit pas propager d'exception hors du process."""
        config = make_config()
        client = make_client(["CRM-1"])
        runner = make_runner("FAILED", exit_code=1)

        # Ne doit pas lever
        report = process(client, config, runner)
        assert report is not None

    def test_run_timeout_conserve_claim(self):
        config = make_config()
        client = make_client(["CRM-1"])
        runner = make_runner("TIMEOUT", exit_code=-1)

        report = process(client, config, runner)

        client.remove_label.assert_not_called()
        assert report.failed == 1


class TestProcessInfra:
    def test_claim_echoue_compte_infra_failed_et_ne_lance_pas_run(self):
        """Un échec de claim (JiraHttpError) = erreur d'infra, pas un échec /mike."""
        config = make_config()
        client = make_client(
            ["CRM-1"], add_label_raises=JiraHttpError("403 Forbidden")
        )
        runner = make_runner("OK")

        report = process(client, config, runner)

        assert report.infra_failed == 1
        assert report.failed == 0
        assert report.ok == 0
        runner.assert_not_called()  # le run /mike n'est pas tenté

    def test_claim_echoue_ne_leve_pas_exception(self):
        config = make_config()
        client = make_client(
            ["CRM-1"], add_label_raises=JiraHttpError("401 Unauthorized")
        )
        runner = make_runner("OK")

        report = process(client, config, runner)  # ne doit pas lever
        assert report is not None


class TestProcessPlafond:
    def test_plafond_max_issues_respecte(self):
        config = make_config(max_issues_per_run=2)
        # 5 tickets retournés par search_keys
        client = make_client(["CRM-1", "CRM-2", "CRM-3", "CRM-4", "CRM-5"])
        runner = make_runner("OK")

        report = process(client, config, runner)

        # Seulement 2 tickets traités
        assert report.processed == 2
        assert runner.call_count == 2

    def test_plafond_indique_skipped(self):
        config = make_config(max_issues_per_run=2)
        client = make_client(["CRM-1", "CRM-2", "CRM-3"])
        runner = make_runner("OK")

        report = process(client, config, runner)

        assert report.skipped == 1
        assert report.seen == 3


class TestMainDryRun:
    """Tests pour __main__ en mode --dry-run via import direct."""

    def test_dry_run_liste_cles_sans_claim(self):
        """En mode dry-run, aucun label ne doit être posé, aucun runner appelé."""
        from jira_watcher.__main__ import fetch_eligible_keys

        config = make_config()
        client = make_client(["CRM-1", "CRM-2"])

        keys = fetch_eligible_keys(client, config)

        client.add_label.assert_not_called()
        assert keys == ["CRM-1", "CRM-2"]


class TestClaudeCredentials:
    """Pré-contrôle des credentials Claude (#7)."""

    def test_fichier_absent_retourne_false(self, tmp_path):
        from jira_watcher.__main__ import claude_credentials_ok

        assert claude_credentials_ok(tmp_path / "absent.json") is False

    def test_fichier_vide_retourne_false(self, tmp_path):
        from jira_watcher.__main__ import claude_credentials_ok

        p = tmp_path / ".credentials.json"
        p.write_text("")
        assert claude_credentials_ok(p) is False

    def test_fichier_non_vide_retourne_true(self, tmp_path):
        from jira_watcher.__main__ import claude_credentials_ok

        p = tmp_path / ".credentials.json"
        p.write_text("{\"token\": \"x\"}")
        assert claude_credentials_ok(p) is True


class TestMainExitCode:
    """Code de sortie de main() (#7, #8)."""

    def _write_config(self, tmp_path):
        cfg = tmp_path / "config.yaml"
        cfg.write_text(
            "jira_base_url: https://ezacae.atlassian.net\n"
            "projects: [CRM]\n"
            "trigger_label: claude\n"
            "claim_label: claude-traite\n"
            "watched_statuses: [NOUVEAU]\n"
            'slash_command: "/mike {key}"\n'
            "claude_timeout_seconds: 3600\n"
            "max_issues_per_run: 4\n"
        )
        return cfg

    def test_credentials_absents_retourne_1(self, tmp_path, monkeypatch):
        import jira_watcher.__main__ as m

        cfg = self._write_config(tmp_path)
        monkeypatch.setenv("JIRA_EMAIL", "user@e.com")
        monkeypatch.setenv("JIRA_API_TOKEN", "tok")
        # credentials Claude réputés absents
        monkeypatch.setattr(m, "claude_credentials_ok", lambda path: False)

        assert m.main(["--config", str(cfg)]) == 1

    def test_infra_failed_retourne_1(self, tmp_path, monkeypatch):
        import jira_watcher.__main__ as m

        cfg = self._write_config(tmp_path)
        monkeypatch.setenv("JIRA_EMAIL", "user@e.com")
        monkeypatch.setenv("JIRA_API_TOKEN", "tok")
        monkeypatch.setattr(m, "claude_credentials_ok", lambda path: True)
        monkeypatch.setattr(
            m, "process",
            lambda client, config, runner: RunReport(
                seen=1, processed=1, ok=0, failed=0, skipped=0, infra_failed=1
            ),
        )

        assert m.main(["--config", str(cfg)]) == 1

    def test_cycle_ok_retourne_0(self, tmp_path, monkeypatch):
        import jira_watcher.__main__ as m

        cfg = self._write_config(tmp_path)
        monkeypatch.setenv("JIRA_EMAIL", "user@e.com")
        monkeypatch.setenv("JIRA_API_TOKEN", "tok")
        monkeypatch.setattr(m, "claude_credentials_ok", lambda path: True)
        monkeypatch.setattr(
            m, "process",
            lambda client, config, runner: RunReport(
                seen=1, processed=1, ok=1, failed=0, skipped=0, infra_failed=0
            ),
        )

        assert m.main(["--config", str(cfg)]) == 0
