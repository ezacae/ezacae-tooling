"""Tests pour jira_watcher.orchestrator — séquenceur du cycle complet.

Tout est injecté (client, runner) : aucun réseau ni subprocess réel.
"""
from __future__ import annotations

from unittest.mock import MagicMock, call

import pytest

from jira_watcher.config import WatcherConfig, load_config
from jira_watcher.mike_runner import MikeResult
from jira_watcher.orchestrator import RunReport, process


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
    defaults.update(overrides)
    return load_config(defaults)


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
        from jira_watcher.__main__ import run_dry_run

        config = make_config()
        client = make_client(["CRM-1", "CRM-2"])

        keys = run_dry_run(client, config)

        client.add_label.assert_not_called()
        assert keys == ["CRM-1", "CRM-2"]
