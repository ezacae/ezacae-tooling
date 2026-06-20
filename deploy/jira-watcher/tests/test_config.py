"""Tests pour jira_watcher.config — validation de la configuration."""
import pytest
from jira_watcher.config import ConfigError, WatcherConfig, load_config

# Mapping de référence valide
VALID_MAPPING = {
    "jira_base_url": "https://ezacae.atlassian.net",
    "projects": ["CRM", "ACME"],
    "trigger_label": "claude",
    "claim_label": "claude-traite",
    "watched_statuses": ["NOUVEAU"],
    "slash_command": "/mike {key}",
    "claude_timeout_seconds": 3600,
    "max_issues_per_run": 10,
}


class TestLoadConfigValid:
    def test_mapping_valide_retourne_watcher_config(self):
        config = load_config(VALID_MAPPING)
        assert isinstance(config, WatcherConfig)

    def test_valeurs_preservees(self):
        config = load_config(VALID_MAPPING)
        assert config.jira_base_url == "https://ezacae.atlassian.net"
        assert config.projects == ["CRM", "ACME"]
        assert config.trigger_label == "claude"
        assert config.claim_label == "claude-traite"
        assert config.watched_statuses == ["NOUVEAU"]
        assert config.slash_command == "/mike {key}"
        assert config.claude_timeout_seconds == 3600
        assert config.max_issues_per_run == 10

    def test_watcher_config_est_frozen(self):
        config = load_config(VALID_MAPPING)
        with pytest.raises((AttributeError, TypeError)):
            config.projects = ["OTHER"]  # type: ignore[misc]


class TestLoadConfigValidation:
    def _mapping(self, **overrides):
        m = dict(VALID_MAPPING)
        m.update(overrides)
        return m

    def test_projects_vide_leve_config_error(self):
        with pytest.raises(ConfigError, match="projects"):
            load_config(self._mapping(projects=[]))

    def test_watched_statuses_vide_leve_config_error(self):
        with pytest.raises(ConfigError, match="watched_statuses"):
            load_config(self._mapping(watched_statuses=[]))

    def test_slash_command_sans_key_leve_config_error(self):
        with pytest.raises(ConfigError, match="slash_command"):
            load_config(self._mapping(slash_command="/mike"))

    def test_claude_timeout_zero_leve_config_error(self):
        with pytest.raises(ConfigError, match="claude_timeout_seconds"):
            load_config(self._mapping(claude_timeout_seconds=0))

    def test_claude_timeout_negatif_leve_config_error(self):
        with pytest.raises(ConfigError, match="claude_timeout_seconds"):
            load_config(self._mapping(claude_timeout_seconds=-1))

    def test_max_issues_zero_leve_config_error(self):
        with pytest.raises(ConfigError, match="max_issues_per_run"):
            load_config(self._mapping(max_issues_per_run=0))

    def test_jira_base_url_non_http_leve_config_error(self):
        with pytest.raises(ConfigError, match="jira_base_url"):
            load_config(self._mapping(jira_base_url="ftp://invalid"))

    def test_jira_base_url_vide_leve_config_error(self):
        with pytest.raises(ConfigError, match="jira_base_url"):
            load_config(self._mapping(jira_base_url=""))

    def test_trigger_label_vide_leve_config_error(self):
        with pytest.raises(ConfigError, match="trigger_label"):
            load_config(self._mapping(trigger_label=""))

    def test_trigger_label_absent_leve_config_error(self):
        m = self._mapping()
        del m["trigger_label"]
        with pytest.raises(ConfigError, match="trigger_label"):
            load_config(m)

    def test_claim_label_vide_leve_config_error(self):
        with pytest.raises(ConfigError, match="claim_label"):
            load_config(self._mapping(claim_label=""))

    def test_claim_label_absent_leve_config_error(self):
        m = self._mapping()
        del m["claim_label"]
        with pytest.raises(ConfigError, match="claim_label"):
            load_config(m)
