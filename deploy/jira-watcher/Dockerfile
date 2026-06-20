# Image jira-watcher : Claude Code headless + watcher Python
#
# Couches :
# 1. Base Node.js + Python (Claude Code CLI nécessite Node)
# 2. Installation globale de @anthropic-ai/claude-code
# 3. Copie des plugins ezacae dans /opt/ezacae-tooling
# 4. Installation du paquet Python jira_watcher
# 5. Utilisateur non-root claude (HOME=/home/claude)
# 6. Montage des credentials at runtime (Secret k8s → ~/.claude/.credentials.json)

FROM node:22-bookworm-slim AS base

# --- Dépendances système ---
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 \
    python3-pip \
    python3-venv \
    ca-certificates \
    curl \
    && rm -rf /var/lib/apt/lists/*

# --- Claude Code CLI ---
RUN npm install -g @anthropic-ai/claude-code

# --- Utilisateur non-root ---
# L'image node:bookworm fournit déjà un utilisateur `node` à l'UID/GID 1000 ;
# on le supprime pour libérer 1000 et créer `claude` (HOME=/home/claude).
# Le CronJob k8s impose runAsUser/runAsGroup 1000.
RUN userdel --remove node \
    && useradd --create-home --shell /bin/bash --uid 1000 --user-group claude
ENV HOME=/home/claude

# --- Plugins ezacae (marketplace local bakés dans l'image) ---
# Les plugins sont copiés depuis la racine du repo (contexte de build = racine)
COPY plugins/ /opt/ezacae-tooling/plugins/

# --- Configuration Claude Code ---
# Positionner la config marketplace + plugins activés + MCP Atlassian distant
RUN mkdir -p /home/claude/.claude
COPY deploy/jira-watcher/image/claude-config.json /home/claude/.claude/claude-config.json
RUN chown -R claude:claude /home/claude/.claude && chmod 700 /home/claude/.claude

# --- Paquet Python ---
# Utiliser un venv pour éviter les conflits avec les paquets système
RUN python3 -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

COPY deploy/jira-watcher/pyproject.toml /build/pyproject.toml
COPY deploy/jira-watcher/jira_watcher/ /build/jira_watcher/
RUN pip install --no-cache-dir /build

# --- Droits finaux ---
RUN chown -R claude:claude /home/claude

USER claude
WORKDIR /home/claude

# Les credentials (~/.claude/.credentials.json) sont montés en runtime par le
# Secret k8s. Le répertoire ~/.claude existe déjà (créé plus haut). Si le Secret
# est absent, le pré-contrôle du watcher échoue proprement avec un log d'erreur.

ENTRYPOINT ["python", "-m", "jira_watcher"]
CMD []
