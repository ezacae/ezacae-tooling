# Référence — Régénération de mkdocs.yml (mécanique)

> Procédure partagée par les commandes `/mike-cto`, `/mike-po`, `/vision-produit`, `/personas-projet`, `/processus-projet`. Source unique — ne pas recopier cette explication dans les commandes.

Régénérer `mkdocs.yml` en exécutant le générateur du plugin ezacae-doc — **jamais** en écrivant le YAML à la main.

`${CLAUDE_PLUGIN_ROOT}` est substitué par Claude Code au moment de l'exécution ; l'utiliser tel quel. Passer la racine du projet documentaire :

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/gen-mkdocs.sh" "<racine>"
```

- `<racine>` = `$DOC_REPO_PATH` s'il a été résolu (commandes Mike / Mike-CTO / Mike-PO), sinon le répertoire courant du projet (commandes vision-produit / personas-projet / processus-projet).
- Si `${CLAUDE_PLUGIN_ROOT}` apparaît non substitué (chemin littéral), **signaler** au lieu d'écrire le YAML à la main.

Le script scanne `docs/`, (re)crée `mkdocs.yml` à la racine et **garantit sa présence** — sans ce fichier, la conversion Markdown → HTML ne se fait pas. Il porte la table de correspondance dossier → section / fichier → label (source unique de vérité) et couvre l'ajout **comme** la suppression de `.md` par régénération complète idempotente. En cas d'échec (pas de `docs/`, aucun `.md`), le signaler au lieu de contourner.
