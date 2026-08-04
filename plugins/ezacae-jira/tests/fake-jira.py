#!/usr/bin/env python3
"""Faux Jira hors-ligne pour les tests de remontée d'erreur des helpers (RD-29).

Écoute sur 127.0.0.1, port éphémère, imprimé sur stdout au démarrage. Aucun
appel sortant : le test ne touche jamais le vrai Jira.

Routes couvertes (cf. conception docs/conception/rd-29-remontee-erreurs-helpers-jira.md) :
  GET  /rest/api/3/issue/RD-404                     -> 404, errorMessages
  GET  /rest/api/3/issue/RD-400ERRORS                -> 400, errors seul (assignee)
  GET  /rest/api/3/issue/RD-401HTML                  -> 401, corps HTML (non-JSON)
  GET  /rest/api/3/issue/RD-OK                       -> 200, fixture d'or (lecture réussie)
  GET  /rest/api/3/issue/RD-WORKLOG?fields=status    -> 200, statut CONCEPTION
  GET  /rest/api/3/issue/RD-ANNULE?fields=status     -> 200, statut EN COURS
  GET  /rest/api/3/issue/RD-ATTACH?fields=attachment -> 200, 2 homonymes + 1 nom avec '..'
  GET  /rest/api/3/issue/RD-DLFAIL?fields=attachment -> 200, 1 PJ dont le contenu échoue (404)
  GET  /rest/api/3/issue/RD-BINARY?fields=attachment -> 200, 1 PJ binaire (octet nul)
  GET  /rest/api/3/issue/<KEY>/transitions?expand=… -> 200, transitions (+ champs requis si expand)
  POST /rest/api/3/issue/<KEY>/transitions           -> 204 si succès, 400 sinon ; compte les POST
  PUT  /rest/api/3/issue/<KEY>                       -> 204 (succès) ou 400 errors-only pour RD-400ERRORS
  GET  /rest/api/3/user/assignable/search?query=...  -> 0, 1 ou plusieurs correspondances
  GET  /attachment/content/<id>                      -> contenu (texte ou binaire), 404 si id inconnu
  GET  /204                                          -> 204 sans corps (test générique)
  GET  /post-count                                   -> {"count": N} POST reçus sur /transitions
"""
import json
import urllib.parse
from http.server import BaseHTTPRequestHandler, HTTPServer

POST_COUNT = {"n": 0}

# --- Corps d'erreur mesurés sur le vrai Jira (cf. conception, table de reproduction) ---
ERR_404 = {
    "errorMessages": ["Le ticket n'existe pas ou vous n'êtes pas autorisé à la voir."],
    "errors": {},
}
ERR_400_ERRORS_ONLY = {
    "errorMessages": [],
    "errors": {"assignee": "Spécifiez une valeur valide pour assignee"},
}
HTML_401 = ("<html><body><h1>401 Unauthorized</h1><p>" + ("Proxy interne - accès refusé. " * 20) + "</p></body></html>").encode("utf-8")

# --- Pièces jointes ---------------------------------------------------------------
# Deux homonymes (id distincts) + un nom contenant '..' (tentative de traversée de
# chemin) : le helper doit réduire ce nom à son basename avant tout usage.
# Le vrai Jira renvoie une URL ABSOLUE dans `content` : construite dynamiquement
# (build_attach_issue) à partir du Host de la requête, jamais figée en dur.
def _attach(aid, filename, host):
    return {"id": aid, "filename": filename, "content": "http://{}/attachment/content/{}".format(host, aid)}


def build_attach_issue(host):
    return {
        "fields": {
            "attachment": [
                _attach("1001", "conception.md", host),
                _attach("1002", "conception.md", host),
                _attach("1003", "../evil-hors-dest.txt", host),
            ]
        }
    }


def build_dlfail_issue(host):
    return {"fields": {"attachment": [_attach("404", "disparue.md", host)]}}


def build_binary_issue(host):
    return {"fields": {"attachment": [_attach("2001", "binaire.dat", host)]}}
ATTACH_CONTENT = {
    "1001": b"Contenu de conception.md (premiere piece jointe).",
    "1002": b"Contenu de conception.md (seconde piece jointe, differente).",
    "1003": b"Contenu du fichier au nom traitre (tentative de traversee).",
    "2001": b"\x00\x01BINAIRE\x00AVEC-OCTET-NUL\x00\xffFIN",
}

# --- Transitions -------------------------------------------------------------------
# RD-WORKLOG : une seule transition, champ requis worklog seul (cas d'origine RD-21).
# RD-ANNULE  : cible accentuée « Annulé », champs requis worklog+resolution, mais le
#              POST réussit avec worklog seul (résolution par défaut serveur, mesuré).
TRANSITIONS = {
    "RD-WORKLOG": [
        {
            "id": "31",
            "name": "Conception terminée",
            "to": {"name": "CONCEPTION VALIDATION"},
            "fields": {"worklog": {"required": True}},
        }
    ],
    "RD-ANNULE": [
        {
            "id": "41",
            "name": "Annuler",
            "to": {"name": "Annulé"},
            "fields": {"worklog": {"required": True}, "resolution": {"required": True}},
        }
    ],
}

STATUS = {
    "RD-WORKLOG": "CONCEPTION",
    "RD-ANNULE": "EN COURS",
}

# --- Recherche d'utilisateur assignable --------------------------------------------
ASSIGNABLE = {
    "": [
        {"accountId": "user{:02d}00000000000000000".format(i), "displayName": "Utilisateur {}".format(i)}
        for i in range(10)
    ],
    "Alexandre": [{"accountId": "6256cf820630bd0070761e65", "displayName": "Alexandre Husset"}],
    "Homonyme": [
        {"accountId": "aaaa111100000000000000aa", "displayName": "Jean Dupont"},
        {"accountId": "bbbb222200000000000000bb", "displayName": "Jean Dupont"},
    ],
    "Personne": [],
}


class Handler(BaseHTTPRequestHandler):
    # --- Réponses --------------------------------------------------------------
    def _json(self, code, payload):
        body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _raw(self, code, body, content_type="application/octet-stream"):
        self.send_response(code)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _no_content(self):
        self.send_response(204)
        self.send_header("Content-Length", "0")
        self.end_headers()

    # --- GET ---------------------------------------------------------------------
    def do_GET(self):
        parsed = urllib.parse.urlsplit(self.path)
        path = parsed.path
        qs = urllib.parse.parse_qs(parsed.query)

        if path == "/204":
            return self._no_content()

        if path == "/post-count":
            return self._json(200, {"count": POST_COUNT["n"]})

        if path.startswith("/attachment/content/"):
            aid = path.rsplit("/", 1)[-1]
            if aid == "404":
                return self._json(404, ERR_404)
            data = ATTACH_CONTENT.get(aid)
            if data is None:
                return self._json(404, ERR_404)
            return self._raw(200, data)

        if path.startswith("/rest/api/3/user/assignable/search"):
            query = qs.get("query", [""])[0]
            return self._json(200, ASSIGNABLE.get(query, []))

        if path.startswith("/rest/api/3/issue/"):
            rest = path[len("/rest/api/3/issue/"):]

            if rest.endswith("/transitions"):
                key = rest[: -len("/transitions")]
                transitions = TRANSITIONS.get(key, [])
                expand = qs.get("expand", [""])[0]
                if "transitions.fields" in expand:
                    out = transitions
                else:
                    out = [{"id": t["id"], "name": t["name"], "to": t["to"]} for t in transitions]
                return self._json(200, {"transitions": out})

            key = rest
            if key == "RD-404":
                return self._json(404, ERR_404)
            if key == "RD-400ERRORS":
                return self._json(400, ERR_400_ERRORS_ONLY)
            if key == "RD-401HTML":
                self.send_response(401)
                self.send_header("Content-Type", "text/html")
                self.send_header("Content-Length", str(len(HTML_401)))
                self.end_headers()
                self.wfile.write(HTML_401)
                return
            host = self.headers.get("Host", "")
            if key == "RD-ATTACH":
                return self._json(200, build_attach_issue(host))
            if key == "RD-DLFAIL":
                return self._json(200, build_dlfail_issue(host))
            if key == "RD-BINARY":
                return self._json(200, build_binary_issue(host))
            if key in STATUS:
                return self._json(200, {"fields": {"status": {"name": STATUS[key]}}})
            if key == "RD-OK":
                return self._json(
                    200,
                    {
                        "key": "RD-OK",
                        "fields": {
                            "status": {"name": "EN COURS"},
                            "summary": "Ticket de référence pour la fixture d'or (RD-29)",
                        },
                    },
                )
            return self._json(404, ERR_404)

        return self._json(404, ERR_404)

    # --- POST : transitions --------------------------------------------------------
    def do_POST(self):
        parsed = urllib.parse.urlsplit(self.path)
        path = parsed.path
        length = int(self.headers.get("Content-Length", 0) or 0)
        raw = self.rfile.read(length) if length else b""
        try:
            body = json.loads(raw) if raw else {}
        except ValueError:
            body = {}

        if path.startswith("/rest/api/3/issue/") and path.endswith("/transitions"):
            POST_COUNT["n"] += 1
            trid = str(body.get("transition", {}).get("id", ""))
            worklog = bool(body.get("update", {}).get("worklog"))

            if trid == "31":
                if worklog:
                    return self._no_content()
                return self._json(400, {"errorMessages": ["Le temps consacré est obligatoire"], "errors": {}})

            if trid == "41":
                if worklog:
                    # Résolution par défaut côté serveur : le POST réussit même
                    # sans le champ `resolution`, pourtant marqué requis.
                    return self._no_content()
                return self._json(
                    400,
                    {
                        "errorMessages": [],
                        "errors": {
                            "resolution": "La résolution est obligatoire",
                            "worklog": "Le temps consacré est obligatoire",
                        },
                    },
                )

            return self._json(400, {"errorMessages": ["Transition id '{}' is not valid for this issue.".format(trid)], "errors": {}})

        return self._json(404, ERR_404)

    # --- PUT : édition de ticket -----------------------------------------------------
    def do_PUT(self):
        parsed = urllib.parse.urlsplit(self.path)
        path = parsed.path
        length = int(self.headers.get("Content-Length", 0) or 0)
        if length:
            self.rfile.read(length)

        if path.startswith("/rest/api/3/issue/"):
            key = path[len("/rest/api/3/issue/"):]
            if key == "RD-400ERRORS":
                return self._json(400, ERR_400_ERRORS_ONLY)
            return self._no_content()

        return self._json(404, ERR_404)

    def log_message(self, *args):  # silence les logs d'accès sur stderr
        pass


def main():
    server = HTTPServer(("127.0.0.1", 0), Handler)
    print(server.server_port, flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
