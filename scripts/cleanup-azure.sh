#!/usr/bin/env bash
# Smaže vše, co demo v Azure vytvořilo (celou resource group).
# Použití: ./scripts/cleanup-azure.sh [resource-group]
set -euo pipefail
export MSYS_NO_PATHCONV=1   # Git Bash na Windows: nepřepisovat argumenty na cesty
RESOURCE_GROUP="${1:-rg-javadays-cicd}"
az group delete --name "${RESOURCE_GROUP}" --yes --no-wait
echo "Mazání resource group ${RESOURCE_GROUP} běží na pozadí."
