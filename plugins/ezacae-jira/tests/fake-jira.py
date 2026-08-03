#!/usr/bin/env python3
"""Faux Jira minimal pour les tests hors-ligne des helpers.

Deux routes seulement :
  GET /rest/api/3/issue/RD-1?fields=attachment  -> 200, une pièce jointe
  tout le reste                                 -> 404, corps d'erreur Jira réel

Écoute sur 127.0.0.1, port éphémère, imprimé sur stdout au démarrage.
Aucun appel sortant : le test ne touche jamais le vrai Jira.
"""
import json
from http.server import BaseHTTPRequestHandler, HTTPServer

ERREUR_404 = {
    "errorMessages": ["Le ticket n'existe pas ou vous n'êtes pas autorisé à la voir."],
    "errors": {},
}


class Handler(BaseHTTPRequestHandler):
    port = 0

    def _envoyer(self, code, payload):
        corps = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(corps)))
        self.end_headers()
        self.wfile.write(corps)

    def do_GET(self):
        if self.path.startswith("/rest/api/3/issue/RD-1"):
            self._envoyer(200, {"fields": {"attachment": [{
                "filename": "conception.md",
                "content": f"http://127.0.0.1:{Handler.port}/attachment/content/1",
            }]}})
        else:
            self._envoyer(404, ERREUR_404)

    def log_message(self, *args):
        pass


serveur = HTTPServer(("127.0.0.1", 0), Handler)
Handler.port = serveur.server_port
print(serveur.server_port, flush=True)
serveur.serve_forever()
