#!/usr/bin/env bash
# Jednorázové propojení GitHubu a Azure – bez hesel (OIDC).
#
# Co skript udělá:
#   1) vytvoří resource group a user-assigned managed identity
#   2) dá identitě roli Contributor jen na tuto resource group
#   3) přidá federované přihlášení pro GitHub (prostředí "dev" a pull requesty)
#      – ve starém i novém (neměnném) formátu subject claimu
#   4) uloží do GitHubu proměnné AZURE_* a založí prostředí "dev"
#   5) pushne kód do větve main – tím spustí workflow CD (vynecháte: NO_PUSH=1)
#      Když složka ještě není git repozitář, založí ho a vytvoří první commit.
#
# Potřebujete: az CLI (přihlášené: az login), gh CLI (přihlášené: gh auth login),
#              roli Owner nebo User Access Administrator v subskripci.
# Funguje v Linuxu, macOS, WSL, Azure Cloud Shell i v Git Bash na Windows.
#
# Použití: ./scripts/setup-azure.sh <owner/repo> [region] [resource-group]
#   např.: ./scripts/setup-azure.sh bechynsky/javadays-2026-cicd westeurope rg-javadays-cicd
#   neexistující repozitář založí: CREATE_REPO=1 bash scripts/setup-azure.sh bechynsky/javadays-2026-cicd
#   bez pushe na konci:             NO_PUSH=1 bash scripts/setup-azure.sh bechynsky/javadays-2026-cicd

set -euo pipefail

# Git Bash na Windows by jinak přepsal ID prostředků začínající lomítkem
# (/subscriptions/...) na cestu k souboru. Na Linuxu a macOS proměnná nic nedělá.
export MSYS_NO_PATHCONV=1

# Odstraní znak \r, který může přidat Windows verze az/gh do výstupu.
trim() { tr -d '\r'; }

REPO="${1:?Zadejte GitHub repozitář ve tvaru owner/repo}"
LOCATION="${2:-westeurope}"
RESOURCE_GROUP="${3:-rg-javadays-cicd}"
IDENTITY_NAME="id-github-javadays-cicd"
ENVIRONMENT="dev"

OWNER="${REPO%%/*}"
NAME="${REPO##*/}"

echo "▶ Kontrola nástrojů a přihlášení"
for tool in az gh git; do
  command -v "${tool}" >/dev/null || { echo "✖ Nenašel jsem příkaz ${tool}." >&2; exit 1; }
done
az account show -o none 2>/dev/null || { echo "✖ Azure CLI není přihlášené. Spusťte: az login" >&2; exit 1; }
gh auth status >/dev/null 2>&1 || { echo "✖ GitHub CLI není přihlášené. Spusťte: gh auth login" >&2; exit 1; }
if [[ "${NO_PUSH:-0}" != "1" ]]; then
  # Předpoklady pro push ověříme hned, ať se skript nezastaví až po vytvoření všeho v Azure.
  if [[ -z "$(git config user.name || true)" || -z "$(git config user.email || true)" ]]; then
    echo "✖ Git nezná vaše jméno a e-mail. Nastavte:" >&2
    echo '  git config --global user.name "Jméno Příjmení"' >&2
    echo '  git config --global user.email "vas@email.cz"' >&2
    exit 1
  fi
  # Push souborů v .github/workflows vyžaduje u přihlášení gh oprávnění "workflow".
  SCOPES=$(gh api user --include 2>/dev/null | trim | grep -i '^x-oauth-scopes:' || true)
  if [[ -n "${SCOPES}" && "${SCOPES}" != *workflow* ]]; then
    echo "✖ Přihlášení gh nemá oprávnění \"workflow\", bez kterého GitHub odmítne push pipeline." >&2
    echo "  Spusťte: gh auth refresh -h github.com -s workflow  a pak skript znovu." >&2
    exit 1
  fi
fi

echo "▶ Azure kontext"
SUBSCRIPTION_ID=$(az account show --query id -o tsv | trim)
TENANT_ID=$(az account show --query tenantId -o tsv | trim)
echo "  subskripce: ${SUBSCRIPTION_ID}"

echo "▶ GitHub repozitář ${REPO}"
GH_USER=$(gh api user --jq '.login' | trim)
echo "  přihlášený účet GitHub: ${GH_USER}"
if ! gh api "repos/${REPO}" --jq '.id' >/dev/null 2>&1; then
  if [[ "${CREATE_REPO:-0}" != "1" ]]; then
    echo "✖ Repozitář ${REPO} na GitHubu nevidím: buď ještě neexistuje, nebo k němu účet ${GH_USER} nemá přístup." >&2
    echo "  Založte ho:  gh repo create ${REPO} --public" >&2
    echo "  nebo spusťte skript s CREATE_REPO=1, který ho založí sám." >&2
    exit 1
  fi
  echo "  repozitář neexistuje, zakládám ho (veřejný, prázdný)"
  gh repo create "${REPO}" --public --description "JavaDays 2026 - CI/CD demo" >/dev/null
fi
OWNER_ID=$(gh api "repos/${REPO}" --jq '.owner.id' | trim)
REPO_ID=$(gh api "repos/${REPO}" --jq '.id' | trim)

echo "▶ Resource group ${RESOURCE_GROUP} (${LOCATION})"
# Po smazání běží mazání resource group ještě několik minut na pozadí – počkáme na jeho konec.
rg_state() { az group show --name "${RESOURCE_GROUP}" --query properties.provisioningState -o tsv 2>/dev/null | trim || true; }
WAITED=0
while [[ "$(rg_state)" == "Deleting" ]]; do
  if (( WAITED >= 900 )); then
    echo "✖ Resource group ${RESOURCE_GROUP} se pořád maže. Zkuste skript spustit znovu za pár minut." >&2
    exit 1
  fi
  echo "  resource group se ještě maže, čekám… (${WAITED} s)"
  sleep 15
  WAITED=$((WAITED + 15))
done
az group create --name "${RESOURCE_GROUP}" --location "${LOCATION}" \
  --tags project=javadays-2026-cicd -o none
RG_ID=$(az group show --name "${RESOURCE_GROUP}" --query id -o tsv | trim)

echo "▶ Managed identity ${IDENTITY_NAME}"
az identity create --resource-group "${RESOURCE_GROUP}" --name "${IDENTITY_NAME}" -o none
CLIENT_ID=$(az identity show -g "${RESOURCE_GROUP}" -n "${IDENTITY_NAME}" --query clientId -o tsv | trim)
PRINCIPAL_ID=$(az identity show -g "${RESOURCE_GROUP}" -n "${IDENTITY_NAME}" --query principalId -o tsv | trim)

echo "▶ Role Contributor na resource group"
# Při opakovaném spuštění už role existuje – az by na ni hlásil chybu.
EXISTING=$(az role assignment list --scope "${RG_ID}" --role Contributor \
  --query "[?principalId=='${PRINCIPAL_ID}'].id" -o tsv | trim)
ASSIGNED=0
if [[ -n "${EXISTING}" ]]; then
  ASSIGNED=1
  echo "  role už je přiřazená"
fi
for attempt in 1 2 3 4 5 6; do
  [[ "${ASSIGNED}" == "1" ]] && break
  if az role assignment create \
      --assignee-object-id "${PRINCIPAL_ID}" \
      --assignee-principal-type ServicePrincipal \
      --role Contributor \
      --scope "${RG_ID}" -o none 2>/dev/null; then
    ASSIGNED=1
    break
  fi
  echo "  identita se ještě propisuje, zkusím znovu za 10 s (${attempt}/6)"
  sleep 10
done
if [[ "${ASSIGNED}" != "1" ]]; then
  echo "✖ Roli se nepodařilo přiřadit. Máte v subskripci roli Owner nebo User Access Administrator?" >&2
  exit 1
fi

echo "▶ Federované přihlášení pro GitHub Actions"
# Repozitáře založené po 15. 7. 2026 posílají neměnný subject s ID vlastníka a repozitáře.
# Starší repozitáře posílají původní formát. Zakládáme oba, ať to funguje vždy.
SUBJECTS=(
  "repo:${REPO}:environment:${ENVIRONMENT}"
  "repo:${REPO}:pull_request"
  "repo:${OWNER}@${OWNER_ID}/${NAME}@${REPO_ID}:environment:${ENVIRONMENT}"
  "repo:${OWNER}@${OWNER_ID}/${NAME}@${REPO_ID}:pull_request"
)
i=0
for subject in "${SUBJECTS[@]}"; do
  i=$((i + 1))
  echo "  ${subject}"
  az identity federated-credential create \
    --resource-group "${RESOURCE_GROUP}" \
    --identity-name "${IDENTITY_NAME}" \
    --name "github-${i}" \
    --issuer "https://token.actions.githubusercontent.com" \
    --subject "${subject}" \
    --audiences "api://AzureADTokenExchange" -o none
done

echo "▶ Proměnné v GitHubu (nejsou tajné – žádná hesla)"
gh variable set AZURE_CLIENT_ID       --body "${CLIENT_ID}"       --repo "${REPO}"
gh variable set AZURE_TENANT_ID       --body "${TENANT_ID}"       --repo "${REPO}"
gh variable set AZURE_SUBSCRIPTION_ID --body "${SUBSCRIPTION_ID}" --repo "${REPO}"
gh variable set AZURE_RESOURCE_GROUP  --body "${RESOURCE_GROUP}"  --repo "${REPO}"

echo "▶ GitHub prostředí ${ENVIRONMENT}"
gh api --method PUT "repos/${REPO}/environments/${ENVIRONMENT}" --silent 2>/dev/null \
  || echo "  ⚠ prostředí se teď nepodařilo založit – GitHub ho vytvoří sám při prvním běhu CD"

if [[ "${NO_PUSH:-0}" == "1" ]]; then
  echo
  echo "✅ Hotovo. Pushněte kód do větve main (nebo spusťte workflow CD ručně)."
  exit 0
fi

echo "▶ Push kódu do GitHubu (spustí workflow CD)"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REMOTE_URL="https://github.com/${REPO}.git"
cd "${REPO_ROOT}"

if [[ ! -d .git ]]; then
  echo "  zakládám lokální git repozitář v ${REPO_ROOT}"
  git init -b main >/dev/null
fi

if ! git rev-parse --verify --quiet HEAD >/dev/null; then
  git add --all 2>/dev/null   # skryje upozornění o koncích řádků LF/CRLF
  git commit -q -m "Initial commit"
  echo "  vytvořen první commit"
elif [[ -n "$(git status --porcelain)" ]]; then
  echo "  ⚠ máte necommitnuté změny – pushnu jen to, co už je v commitech"
fi

ORIGIN=$(git remote get-url origin 2>/dev/null || true)
BRANCH=$(git branch --show-current)
if [[ "${BRANCH}" != "main" ]]; then
  if [[ -z "${ORIGIN}" ]]; then
    git branch -M main
    echo "  větev '${BRANCH}' přejmenována na main"
  else
    echo "✖ Jste ve větvi '${BRANCH}'. Workflow CD se spouští z větve main: git switch main a spusťte skript znovu." >&2
    exit 1
  fi
fi

ORIGIN_PATTERN="[:/]${REPO}(\.git)?/?$"
if [[ -z "${ORIGIN}" ]]; then
  git remote add origin "${REMOTE_URL}"
  echo "  remote origin: ${REMOTE_URL}"
elif [[ ! "${ORIGIN}" =~ ${ORIGIN_PATTERN} ]]; then
  echo "✖ Remote origin ukazuje na ${ORIGIN}, ne na ${REPO}. Opravte: git remote set-url origin ${REMOTE_URL}" >&2
  exit 1
fi

# Git použije stejný účet jako gh (ne třeba jiný uložený účet).
gh auth setup-git

# Když je kód na GitHubu už aktuální, push nic nespustí – workflow CD pak spustíme ručně.
LOCAL_SHA=$(git rev-parse HEAD)
REMOTE_SHA=$(git ls-remote origin refs/heads/main | trim | cut -f1)
if [[ -n "${REMOTE_SHA}" && "${REMOTE_SHA}" == "${LOCAL_SHA}" ]]; then
  echo "  kód na GitHubu už je aktuální – spouštím workflow CD ručně"
  gh workflow run cd.yml --ref main --repo "${REPO}"
else
  git push -u origin main
fi

echo
echo "✅ Hotovo. Workflow CD právě běží: https://github.com/${REPO}/actions"
echo "   sledování v terminálu: gh run watch"
echo "   Kdyby první běh spadl na přihlášení do Azure, oprávnění se ještě propisují –"
echo "   za pár minut dejte v GitHubu \"Re-run failed jobs\"."
