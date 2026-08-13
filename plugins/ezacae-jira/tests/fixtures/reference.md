## Périmètre retenu

Écriture — uniquement les constructions ancrées en début de ligne.

- titres
- listes à puces
- listes numérotées
- blocs de code

Étapes :

1. figer les références
2. corriger la lecture
3. corriger l'écriture

Vérification :

```bash
bash plugins/ezacae-jira/tests/test_adf_write.sh
```

### Hors périmètre

Gras, italique et liens. Un chemin comme plugins/**/* doit rester intact.
