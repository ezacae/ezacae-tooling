"""Tests pour jira_watcher.jira_client — client REST JIRA v3.

HTTP est injecté via un objet fake pour éviter tout appel réseau.
"""
from __future__ import annotations

import json
from typing import Any
from unittest.mock import MagicMock, call

import pytest

from jira_watcher.jira_client import JiraClient, JiraHttpError


# ---------------------------------------------------------------------------
# Helpers : fakes HTTP
# ---------------------------------------------------------------------------


def make_response(status_code: int = 200, json_body: Any = None) -> MagicMock:
    """Crée un faux objet Response requests."""
    resp = MagicMock()
    resp.status_code = status_code
    resp.json.return_value = json_body or {}
    resp.text = json.dumps(json_body or {})
    if status_code >= 400:
        resp.raise_for_status.side_effect = JiraHttpError(
            f"HTTP {status_code}", response=resp
        )
    else:
        resp.raise_for_status.return_value = None
    return resp


def make_http(responses: list) -> MagicMock:
    """Crée un faux objet HTTP (comme requests.Session) dont get/put retournent les réponses."""
    http = MagicMock()
    http.get.side_effect = responses
    http.put.side_effect = responses
    return http


# ---------------------------------------------------------------------------
# Réponse JIRA /search type
# ---------------------------------------------------------------------------

SEARCH_RESPONSE_2_ISSUES = {
    "total": 2,
    "issues": [
        {"key": "CRM-1"},
        {"key": "CRM-2"},
    ],
}

SEARCH_RESPONSE_EMPTY = {"total": 0, "issues": []}


class TestJiraClientInit:
    def test_instanciation(self):
        http = MagicMock()
        client = JiraClient(
            base_url="https://ezacae.atlassian.net",
            email="user@example.com",
            token="tok",
            http=http,
        )
        assert client is not None


class TestSearchKeys:
    def test_retourne_liste_de_cles(self):
        http = MagicMock()
        http.get.return_value = make_response(200, SEARCH_RESPONSE_2_ISSUES)
        client = JiraClient("https://ezacae.atlassian.net", "user@e.com", "tok", http)
        keys = client.search_keys("project IN (CRM)", max_results=10)
        assert keys == ["CRM-1", "CRM-2"]

    def test_liste_vide_si_aucun_ticket(self):
        http = MagicMock()
        http.get.return_value = make_response(200, SEARCH_RESPONSE_EMPTY)
        client = JiraClient("https://ezacae.atlassian.net", "user@e.com", "tok", http)
        keys = client.search_keys("project IN (CRM)", max_results=10)
        assert keys == []

    def test_appel_url_search_correcte(self):
        http = MagicMock()
        http.get.return_value = make_response(200, SEARCH_RESPONSE_EMPTY)
        client = JiraClient("https://ezacae.atlassian.net", "user@e.com", "tok", http)
        client.search_keys("project IN (CRM)", max_results=5)
        call_kwargs = http.get.call_args
        url = call_kwargs[0][0] if call_kwargs[0] else call_kwargs[1].get("url", "")
        assert "/rest/api/3/search" in url

    def test_max_results_passe_en_parametre(self):
        http = MagicMock()
        http.get.return_value = make_response(200, SEARCH_RESPONSE_EMPTY)
        client = JiraClient("https://ezacae.atlassian.net", "user@e.com", "tok", http)
        client.search_keys("project IN (CRM)", max_results=7)
        call_kwargs = http.get.call_args
        params = call_kwargs[1].get("params", {})
        assert params.get("maxResults") == 7

    def test_auth_basic_positionnee(self):
        http = MagicMock()
        http.get.return_value = make_response(200, SEARCH_RESPONSE_EMPTY)
        client = JiraClient("https://ezacae.atlassian.net", "user@e.com", "mytoken", http)
        client.search_keys("project IN (CRM)", max_results=10)
        call_kwargs = http.get.call_args
        auth = call_kwargs[1].get("auth")
        assert auth == ("user@e.com", "mytoken")

    def test_erreur_http_leve_exception(self):
        http = MagicMock()
        http.get.return_value = make_response(401, {"message": "Unauthorized"})
        client = JiraClient("https://ezacae.atlassian.net", "user@e.com", "badtok", http)
        with pytest.raises(JiraHttpError):
            client.search_keys("project IN (CRM)", max_results=10)


class TestAddLabel:
    def test_envoie_put_avec_corps_correct(self):
        http = MagicMock()
        http.put.return_value = make_response(204)
        client = JiraClient("https://ezacae.atlassian.net", "user@e.com", "tok", http)
        client.add_label("CRM-1", "claude-traite")
        call_kwargs = http.put.call_args
        url = call_kwargs[0][0] if call_kwargs[0] else call_kwargs[1].get("url", "")
        assert "/rest/api/3/issue/CRM-1" in url
        body = call_kwargs[1].get("json", {})
        assert body == {"update": {"labels": [{"add": "claude-traite"}]}}

    def test_auth_basic_positionnee(self):
        http = MagicMock()
        http.put.return_value = make_response(204)
        client = JiraClient("https://ezacae.atlassian.net", "user@e.com", "tok", http)
        client.add_label("CRM-1", "claude-traite")
        auth = http.put.call_args[1].get("auth")
        assert auth == ("user@e.com", "tok")

    def test_erreur_http_leve_exception(self):
        http = MagicMock()
        http.put.return_value = make_response(403, {"message": "Forbidden"})
        client = JiraClient("https://ezacae.atlassian.net", "user@e.com", "tok", http)
        with pytest.raises(JiraHttpError):
            client.add_label("CRM-1", "claude-traite")


class TestRemoveLabel:
    def test_envoie_put_avec_corps_remove(self):
        http = MagicMock()
        http.put.return_value = make_response(204)
        client = JiraClient("https://ezacae.atlassian.net", "user@e.com", "tok", http)
        client.remove_label("CRM-1", "claude-traite")
        call_kwargs = http.put.call_args
        url = call_kwargs[0][0] if call_kwargs[0] else call_kwargs[1].get("url", "")
        assert "/rest/api/3/issue/CRM-1" in url
        body = call_kwargs[1].get("json", {})
        assert body == {"update": {"labels": [{"remove": "claude-traite"}]}}

    def test_erreur_http_leve_exception(self):
        http = MagicMock()
        http.put.return_value = make_response(404, {"message": "Not Found"})
        client = JiraClient("https://ezacae.atlassian.net", "user@e.com", "tok", http)
        with pytest.raises(JiraHttpError):
            client.remove_label("CRM-1", "claude-traite")
