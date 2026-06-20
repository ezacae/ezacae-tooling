"""Tests pour jira_watcher.mike_runner — lanceur /mike headless.

subprocess est injecté via un runner fake pour éviter toute exécution réelle de claude.
"""
from __future__ import annotations

import subprocess
from unittest.mock import MagicMock

from jira_watcher.mike_runner import MikeResult, build_invocation, run
from tests.factories import make_config


class TestBuildInvocation:
    def test_argv_contient_claude(self):
        config = make_config()
        argv, prompt, env = build_invocation("CRM-1", config)
        assert argv[0] == "claude"

    def test_argv_contient_flag_p(self):
        config = make_config()
        argv, prompt, env = build_invocation("CRM-1", config)
        assert "-p" in argv

    def test_argv_contient_dangerously_skip_permissions(self):
        config = make_config()
        argv, prompt, env = build_invocation("CRM-1", config)
        assert "--dangerously-skip-permissions" in argv

    def test_prompt_contient_slash_command_template(self):
        config = make_config(slash_command="/mike {key}")
        argv, prompt, env = build_invocation("CRM-1", config)
        assert prompt == "/mike CRM-1"

    def test_prompt_substitue_key(self):
        config = make_config(slash_command="/mike {key}")
        argv, prompt, env = build_invocation("ACME-42", config)
        assert "ACME-42" in prompt
        assert "{key}" not in prompt

    def test_retourne_tuple_trois_elements(self):
        config = make_config()
        result = build_invocation("CRM-1", config)
        assert len(result) == 3


class TestMikeResult:
    def test_status_ok(self):
        result = MikeResult(status="OK", exit_code=0, log_tail="")
        assert result.status == "OK"

    def test_status_failed(self):
        result = MikeResult(status="FAILED", exit_code=1, log_tail="error")
        assert result.status == "FAILED"
        assert result.exit_code == 1

    def test_status_timeout(self):
        result = MikeResult(status="TIMEOUT", exit_code=-1, log_tail="timed out")
        assert result.status == "TIMEOUT"


class TestRun:
    def test_runner_exit_0_retourne_ok(self):
        config = make_config()

        def fake_runner(argv: list[str], prompt: str, env: dict, timeout: int):
            return MagicMock(returncode=0, stdout="cadrage effectué", stderr="")

        result = run("CRM-1", config, runner=fake_runner)
        assert result.status == "OK"
        assert result.exit_code == 0

    def test_runner_exit_non_zero_retourne_failed(self):
        config = make_config()

        def fake_runner(argv, prompt, env, timeout):
            return MagicMock(returncode=1, stdout="", stderr="erreur claude")

        result = run("CRM-1", config, runner=fake_runner)
        assert result.status == "FAILED"
        assert result.exit_code == 1

    def test_runner_timeout_retourne_timeout(self):
        config = make_config()

        def fake_runner(argv, prompt, env, timeout):
            raise subprocess.TimeoutExpired(cmd=argv, timeout=timeout)

        result = run("CRM-1", config, runner=fake_runner)
        assert result.status == "TIMEOUT"
        assert result.exit_code == -1

    def test_log_tail_rempli_depuis_stderr(self):
        config = make_config()
        long_stderr = "\n".join(f"ligne {i}" for i in range(100))

        def fake_runner(argv, prompt, env, timeout):
            return MagicMock(returncode=1, stdout="", stderr=long_stderr)

        result = run("CRM-1", config, runner=fake_runner)
        assert result.log_tail
        # log_tail ne doit pas dépasser les 20 dernières lignes
        lines = result.log_tail.strip().splitlines()
        assert len(lines) <= 20

    def test_log_tail_rempli_depuis_stdout_si_stderr_vide(self):
        config = make_config()

        def fake_runner(argv, prompt, env, timeout):
            return MagicMock(returncode=1, stdout="sortie stdout", stderr="")

        result = run("CRM-1", config, runner=fake_runner)
        assert "sortie stdout" in result.log_tail

    def test_timeout_passe_depuis_config(self):
        config = make_config(claude_timeout_seconds=120)
        captured = {}

        def fake_runner(argv, prompt, env, timeout):
            captured["timeout"] = timeout
            return MagicMock(returncode=0, stdout="ok", stderr="")

        run("CRM-1", config, runner=fake_runner)
        assert captured["timeout"] == 120
