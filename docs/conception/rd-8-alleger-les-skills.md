# Conception — Alléger les skills en s'appuyant sur Superpowers (RD-8)

Statut : Brouillon — pilote livré (MR !11), suite à cadrer.

## Le problème

Nos skills de développement (chuck, morgan, john…) recopient dans leur texte une façon de travailler générale : comment explorer un besoin, comment tester, comment écrire un plan. Cette façon de travailler existe déjà, tenue à jour, dans un outil qu'on utilise au quotidien : **Superpowers**.

Le souci des copies : quand Superpowers se corrige, nos copies, elles, restent fausses. Cas vécu — notre copie de « grill-me » a raté une correction pendant des semaines sans que personne le voie.

## Ce qu'on veut

Que nos skills **arrêtent de recopier** la méthode et aillent la **chercher en direct** dans Superpowers. Nos skills ne gardent que ce qui est propre à ezacae : nos conventions de code, notre circuit de livraison, notre façon de nommer et de cadrer les projets. La méthode générale, on la branche — on ne la duplique plus.

## Ce qu'on a vérifié avant de commencer

On craignait qu'un « sous-agent » (un assistant lancé en second par l'assistant principal) ne puisse pas aller chercher un skill tout seul. C'était vrai avant, et c'est ce qui justifiait les copies. On a testé pour de bon : **c'est corrigé, ça marche maintenant**. Donc les copies ne servent plus à rien — on peut les retirer sans perdre la méthode.

## Ce qu'on fait

1. **Pilote sur un seul skill (chuck)** — on valide la méthode proprement sur un cas sans risque avant de l'étendre.
2. **Un garde-fou au démarrage** — si Superpowers n'est pas installé, un message prévient avec la commande pour l'installer ; si sa version a changé, un avertissement le signale. Ça ne bloque jamais la session.
3. **Ensuite seulement**, on étend aux gros skills (morgan, john) — c'est là qu'il y a le plus de copies à supprimer, mais aussi le plus de risque, donc après validation du pilote.

## Ce qu'on garde intact

Tout ce qui fait ezacae : détection de la techno du projet, nos conventions de code, la façon d'écrire la conception, le passage de relais entre les rôles. Vérifié : rien de tout ça n'a été perdu dans le pilote.

## Ce qu'on vérifie

Chaque bout de code est testé (test écrit avant le code). Pour les skills eux-mêmes, on compare le résultat avant / après sur de vrais tickets, pour être sûr qu'on n'a rien cassé.

## Une réserve honnête

Ce chantier fait partie du grand sujet « socle harnais », pas encore tranché en réunion. On avance en avance, sur demande, en le sachant. Si la réunion décide autrement, on ajuste — la cible finale reste celle du socle.

## Ce qui reste à décider

L'installation **automatique** de Superpowers en même temps que nos plugins touche un réglage commun à toute l'équipe (les deux outils viennent de « magasins » différents). C'est à Simon, qui gère ce réglage, de le poser. En attendant, le garde-fou du point 2 prévient si Superpowers manque.
