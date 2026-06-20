"""Client REST JIRA v3 pour le watcher.

Le paramètre `http` est injecté (requests.Session ou compatible) pour permettre
les tests unitaires sans appel réseau réel.
"""
from __future__ import annotations

from typing import Any, Protocol


class HttpProtocol(Protocol):
    """Interface minimale compatible requests.Session."""

    def get(self, url: str, **kwargs: Any) -> Any: ...

    def put(self, url: str, **kwargs: Any) -> Any: ...


class JiraHttpError(Exception):
    """Erreur HTTP retournée par l'API JIRA REST."""

    def __init__(self, message: str, response: Any = None) -> None:
        super().__init__(message)
        self.response = response


class JiraClient:
    """Client REST JIRA v3.

    Encapsule les appels REST nécessaires au watcher :
    - recherche par JQL
    - ajout / retrait d'une étiquette

    Le transport HTTP est injecté pour la testabilité.
    """

    def __init__(
        self,
        base_url: str,
        email: str,
        token: str,
        http: HttpProtocol,
    ) -> None:
        self._base = base_url.rstrip("/")
        self._auth = (email, token)
        self._http = http

    def search_keys(self, jql: str, max_results: int) -> list[str]:
        """Recherche les clés de tickets correspondant à la requête JQL.

        Args:
            jql: requête JQL (produite par jql.build_jql).
            max_results: nombre maximum de tickets retournés.

        Returns:
            Liste ordonnée des clés de tickets (ex. ["CRM-1", "CRM-2"]).

        Raises:
            JiraHttpError: si l'API retourne un code d'erreur HTTP.
        """
        url = f"{self._base}/rest/api/3/search"
        response = self._http.get(
            url,
            auth=self._auth,
            params={
                "jql": jql,
                "maxResults": max_results,
                "fields": "key",
            },
        )
        response.raise_for_status()
        data: dict[str, Any] = response.json()
        return [issue["key"] for issue in data.get("issues", [])]

    def add_label(self, key: str, label: str) -> None:
        """Ajoute une étiquette à un ticket JIRA.

        Utilise l'opération `add` de l'API update pour ne pas écraser
        les étiquettes existantes.

        Args:
            key: clé du ticket (ex. "CRM-1").
            label: étiquette à ajouter.

        Raises:
            JiraHttpError: si l'API retourne un code d'erreur HTTP.
        """
        self._update_label(key, "add", label)

    def remove_label(self, key: str, label: str) -> None:
        """Retire une étiquette d'un ticket JIRA.

        Args:
            key: clé du ticket.
            label: étiquette à retirer.

        Raises:
            JiraHttpError: si l'API retourne un code d'erreur HTTP.
        """
        self._update_label(key, "remove", label)

    def _update_label(self, key: str, operation: str, label: str) -> None:
        url = f"{self._base}/rest/api/3/issue/{key}"
        response = self._http.put(
            url,
            auth=self._auth,
            json={"update": {"labels": [{operation: label}]}},
        )
        response.raise_for_status()
