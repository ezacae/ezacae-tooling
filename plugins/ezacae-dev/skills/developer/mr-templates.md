# Templates Merge Request — Agent Developer

## GitLab

```bash
glab mr create \
  --title "<type>(<scope>): <titre de la fonctionnalité>" \
  --description "$(cat <<'EOF'
## Résumé

<Description concise de la fonctionnalité implémentée, basée sur le document de conception>

## Document de conception

<Chemin ou référence au document de conception>

## Changements

<Liste des fichiers modifiés/créés, groupés par phase>

### Phase 1 — <nom>
- `chemin/fichier.tsx` — <description>

### Phase 2 — <nom>
- `chemin/fichier.tsx` — <description>

## Tests

- [x] TDD appliqué (red-green-refactor par phase)
- [x] Tests unitaires ajoutés
- [x] Test d'intégration ajouté
- [x] Suite de tests verte (`npm test`) — preuve vérifiée
- [x] TypeCheck OK (`npm run typecheck`) — preuve vérifiée
- [x] Lint OK (`npm run lint`) — preuve vérifiée

Implementé par Agent Developer
EOF
)" \
  --target-branch <branche-par-défaut>
```

## GitHub

```bash
gh pr create \
  --title "<type>(<scope>): <titre de la fonctionnalité>" \
  --body "$(cat <<'EOF'
## Résumé

<Description concise>

## Document de conception

<Chemin ou référence>

## Changements

<Liste des fichiers par phase>

## Tests

- [x] TDD appliqué (red-green-refactor par phase)
- [x] Tests unitaires + intégration
- [x] Suite verte — preuve vérifiée

Implementé par Agent Developer
EOF
)" \
  --base <branche-par-défaut>
```

## Détection de la plateforme

```bash
git remote get-url origin
```

- URL contient `gitlab` → utiliser le template GitLab
- URL contient `github` → utiliser le template GitHub
