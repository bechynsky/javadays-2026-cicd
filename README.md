# JavaDays 2026 – CI/CD pro Java vývojáře

Ukázková aplikace k přednášce **Continuous Integration / Continuous Delivery** na JavaDays 2026.
Jednoduchá webová aplikace ve Spring Bootu, kterou GitHub Actions postaví, otestuje
a nasadí do **Azure App Service**. Prostředí v Azure je popsané kódem v **Bicepu**
a nasazuje se stejnou pipeline jako aplikace.

```
commit → pull request → CI (build, testy, Bicep what-if) → merge → CD (infra → aplikace → smoke test)
```

## Co je uvnitř

| Cesta | Obsah |
|---|---|
| `src/` | Spring Boot 4.1 aplikace (Java 25): stránka `/`, API `/api/info` a `/api/greeting` |
| `src/test/` | 6 JUnit testů – `mvn -B verify` |
| `infra/main.bicep` | App Service plán (Linux) + Web App s Javou 25 |
| `infra/modules/monitoring.bicep` | Log Analytics + Application Insights (volitelné) |
| `infra/main.bicepparam` | Parametry prostředí `dev` – mění se v demu |
| `.github/workflows/ci.yml` | CI na každý pull request: build, testy, Bicep lint, what-if |
| `.github/workflows/cd.yml` | CD po merge do `main`: build → infra → nasazení → smoke test |
| `.github/dependabot.yml` | Hlídání závislostí Mavenu a verzí akcí |
| `.vscode/extensions.json` | Doporučená rozšíření VS Code |
| `.gitattributes` | Konce řádků (LF pro `.sh`, CRLF pro `.ps1`) |
| `scripts/setup-azure.ps1` / `.sh` | Jednorázové propojení GitHubu a Azure přes OIDC (bez hesel) – PowerShell / bash |
| `scripts/cleanup-azure.ps1` / `.sh` | Smazání všeho v Azure – PowerShell / bash |
| `DEMO.md` | Scénář živého dema krok za krokem |

## Co potřebujete

- JDK 25 (např. Microsoft Build of OpenJDK) a Maven 3.9+
- Git, [GitHub CLI](https://cli.github.com/) (`gh`) a [Azure CLI](https://learn.microsoft.com/cli/azure/) (`az`)
- Předplatné Azure s rolí **Owner** nebo **User Access Administrator** (skript přiřazuje roli identitě)
- Pro nastavovací skript **PowerShell** na Windows (`scripts/*.ps1`), nebo **bash** – Linux, macOS, WSL,
  Git Bash, Azure Cloud Shell (`scripts/*.sh`; Cloud Shell má `az` i `gh` předinstalované)

Na Windows 11 postupujte podle sekce [Příprava na Windows 11 a VS Code](#příprava-na-windows-11-a-vs-code).

## Spuštění lokálně

```bash
mvn -B verify                 # build + testy, výsledek target/app.jar
java -jar target/app.jar      # nebo: mvn spring-boot:run
```

Otevřete <http://localhost:8080>, API <http://localhost:8080/api/info>.

## Příprava na Windows 11 a VS Code

### 1. Nástroje

V PowerShellu (jako běžný uživatel, instalátory si o oprávnění řeknou samy):

```powershell
winget install --id Git.Git -e
winget install --id Microsoft.OpenJDK.25 -e
winget install --id GitHub.cli -e
winget install --id Microsoft.AzureCLI -e
```

**Maven** nemá oficiální balíček pro winget – stáhněte ZIP z <https://maven.apache.org/download.cgi>,
rozbalte ho a přidejte složku `bin` do `PATH`. Například:

```powershell
$v = "3.10.1"   # aktuální verzi najdete na stránce ke stažení
$dir = "$env:USERPROFILE\tools"
New-Item -ItemType Directory -Force $dir | Out-Null
Invoke-WebRequest "https://dlcdn.apache.org/maven/maven-3/$v/binaries/apache-maven-$v-bin.zip" -OutFile "$env:TEMP\maven.zip"
Expand-Archive "$env:TEMP\maven.zip" -DestinationPath $dir -Force
$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
[Environment]::SetEnvironmentVariable("Path", "$userPath;$dir\apache-maven-$v\bin", "User")
```

**Zavřete a znovu otevřete VS Code i terminály** (načte se nový `PATH` a `JAVA_HOME`) a ověřte:

```powershell
java --version      # openjdk 25...
mvn -v              # Apache Maven 3.10.x ... Java version: 25
git --version
gh --version
az version
az bicep install    # Bicep CLI pro lokální kontrolu infrastruktury
```

### 2. Git a přihlášení

```powershell
git config --global user.name  "Jméno Příjmení"
git config --global user.email "vas@email.cz"

gh auth login       # GitHub.com → HTTPS → "Authenticate Git with your GitHub credentials": Yes
az login            # vyberte správnou subskripci
az account show     # ověření; případně: az account set --subscription "<název nebo ID>"
```

### 3. VS Code

Otevřete složku repozitáře (*File → Open Folder*). VS Code nabídne doporučená rozšíření
ze souboru `.vscode/extensions.json` – zvolte **Install**. Případně ručně:

```powershell
code --install-extension vscjava.vscode-java-pack
code --install-extension vmware.vscode-boot-dev-pack
code --install-extension ms-azuretools.vscode-bicep
code --install-extension github.vscode-github-actions
code --install-extension github.vscode-pull-request-github
code --install-extension ms-azuretools.vscode-azureappservice
```

| Rozšíření | K čemu je |
|---|---|
| Extension Pack for Java | Jazyk, ladění, testy, Maven |
| Spring Boot Extension Pack | Spring Boot Dashboard, nápověda v `application.properties` |
| Bicep | Zvýraznění, kontrola a doplňování v `infra/*.bicep` |
| GitHub Actions | Běhy workflow a logy přímo ve VS Code |
| GitHub Pull Requests | Pull requesty a jejich kontroly bez přepínání do prohlížeče |
| Azure App Service | Pohled na Web App, logy, restart (volitelné) |

### 4. Spuštění a testy

V terminálu VS Code (*Terminal → New Terminal*):

```powershell
mvn -B verify          # build + 6 testů, výsledek target\app.jar
mvn spring-boot:run    # aplikace na http://localhost:8080
```

Nebo v panelu **Spring Boot Dashboard** tlačítko *Run* (ladění: *Debug*), testy v panelu **Testing**.
Pokud se při prvním spuštění ozve Windows Firewall, můžete ho zrušit – `localhost` funguje i tak.

### 5. Skripty pro Azure na Windows

Nastavovací a úklidový skript jsou ve dvou variantách se stejným výsledkem:
`scripts/*.ps1` pro PowerShell a `scripts/*.sh` pro bash.

**PowerShell (doporučeno na Windows)** – v běžném terminálu VS Code:

```powershell
.\scripts\setup-azure.ps1 -Repo <váš-účet>/javadays-2026-cicd -Location westeurope -ResourceGroup rg-javadays-cicd
```

Funguje ve Windows PowerShell 5.1 (součást Windows 11) i v PowerShell 7.
Nápověda ke skriptu: `Get-Help .\scripts\setup-azure.ps1 -Detailed`.

Když Windows spuštění skriptu odmítne:

- *„running scripts is disabled on this system“* – povolte pro svůj účet místní skripty (jednorázově):
  `Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned`
- *„is not digitally signed“* – soubory z rozbaleného ZIPu staženého prohlížečem jsou označené
  jako stažené z internetu. Pokud jim důvěřujete, odblokujte je:
  `Get-ChildItem .\scripts\*.ps1 | Unblock-File`
  (po `git clone` tohle potřeba není).
- Pokud spouštění skriptů zakazuje politika vaší organizace, neobcházejte ji – použijte
  Azure Cloud Shell (má `az` i `gh`) a bash variantu níže.

**Bash (Git Bash, WSL, Azure Cloud Shell)** – ve VS Code šipka u **+** v panelu terminálu → *Git Bash*:

```bash
bash scripts/setup-azure.sh <váš-účet>/javadays-2026-cicd westeurope rg-javadays-cicd
```

Bash skripty si v Git Bash samy vypnou převod cest (`MSYS_NO_PATHCONV=1`), jinak by se ID prostředků
`/subscriptions/...` přepsala na `C:/Program Files/Git/subscriptions/...`.

Soubor `.gitattributes` drží u `*.sh` konce řádků LF a u `*.ps1` CRLF, takže obě varianty fungují
bez ohledu na to, kde repozitář naklonujete.

### 6. Lokální kontrola infrastruktury (volitelné)

```powershell
az bicep build --file infra/main.bicep        # syntaxe a lint
az deployment group what-if -g rg-javadays-cicd `
  --template-file infra/main.bicep --parameters infra/main.bicepparam
```

`what-if` funguje až po nastavovacím skriptu `setup-azure` (resource group musí existovat).

## Nasazení do Azure – krok za krokem

1. **Založte prázdný repozitář na GitHubu** (zatím nic nepushujte):

   ```bash
   gh repo create javadays-2026-cicd --public
   ```

   Krok můžete přeskočit – nastavovací skript repozitář založí sám s přepínačem `-CreateRepo`
   (PowerShell), případně s `CREATE_REPO=1` před příkazem (bash).

2. **Propojte GitHub a Azure a pushněte kód** – skript vytvoří resource group, managed identitu,
   federované přihlášení a proměnné `AZURE_*` v GitHubu (žádná hesla ani secrets). Nakonec kód
   pushne do větve `main`: když složka ještě není git repozitář, založí ho, vytvoří první commit
   a nastaví `origin`. Push spustí workflow **CD**. Skript lze spustit opakovaně: počká, až doběhne
   případné mazání resource group, a když je kód na GitHubu už aktuální, spustí CD ručně.
   Po smazání repozitáře na GitHubu přidejte `-CreateRepo` (PowerShell) nebo `CREATE_REPO=1` (bash).

   Windows (PowerShell):

   ```powershell
   az login
   gh auth login
   .\scripts\setup-azure.ps1 -Repo <váš-účet>/javadays-2026-cicd -Location westeurope -ResourceGroup rg-javadays-cicd
   ```

   Linux, macOS, WSL, Git Bash, Azure Cloud Shell:

   ```bash
   az login
   gh auth login
   bash scripts/setup-azure.sh <váš-účet>/javadays-2026-cicd westeurope rg-javadays-cicd
   ```

3. **Sledujte první běh CD** – vytvoří prostředí z Bicepu a nasadí aplikaci. Trvá pár minut;
   adresu aplikace najdete v běhu workflow u prostředí **dev** (v terminálu: `gh run watch`).

   Push si chcete udělat sami? Spusťte skript s `-NoPush` (PowerShell) nebo `NO_PUSH=1` (bash) a pak:

   ```bash
   git init -b main
   git add .
   git commit -m "Initial commit"
   git remote add origin https://github.com/<váš-účet>/javadays-2026-cicd.git
   git push -u origin main
   ```

4. **Zapněte bránu kvality na `main`** – *Settings → Rules → Rulesets → New branch ruleset*:
   - cíl: výchozí větev (`main`)
   - *Require a pull request before merging*
   - *Require status checks to pass*: `Build & test`, `Bicep lint`
   - do *Bypass list* přidejte roli **Repository admin** – v demu (krok 1) pak můžete pushnout přímo do `main`

## Jak to funguje

- **Build jednou, nasaď kamkoliv** – CD postaví `app.jar` jednou a stejný soubor nasadí.
  Číslo buildu a commit jsou zapsané v JARu (`build-info`), smoke test je ověří přes `/api/info`.
- **OIDC místo hesel** – workflow si vyžádá krátkodobý token (`id-token: write`),
  Azure ho ověří proti federovanému přihlášení managed identity. V GitHubu jsou jen ID, žádná tajemství.
- **Pořadí v CD**: infrastruktura → aplikace. Když jeden pull request mění Bicep i kód,
  aplikace se nasadí až do připraveného prostředí.
- **Pozor na nové repozitáře**: repozitáře založené po 15. 7. 2026 posílají v OIDC tokenu
  neměnný subject s ID vlastníka a repozitáře (`repo:owner@123/repo@456:environment:dev`).
  Skript zakládá federované přihlášení pro oba formáty.

## Náklady a úklid

Plán **B1** se účtuje po hodinách, Application Insights podle objemu dat. Po přednášce vše smažte:

```powershell
.\scripts\cleanup-azure.ps1 -ResourceGroup rg-javadays-cicd   # Windows; před smazáním se zeptá
```

```bash
bash scripts/cleanup-azure.sh rg-javadays-cicd                  # bash
```

Pro úplně bezplatný běh změňte v `infra/main.bicepparam` `skuName` na `'F1'` (bez Always On, pomalejší start).

## Řešení potíží

| Příznak | Co zkontrolovat |
|---|---|
| `azure/login` hlásí *AADSTS70021 / no matching federated identity* | Subject claim neodpovídá – spusťte znovu `setup-azure` (`.ps1` nebo `.sh`), ověřte název prostředí `dev` |
| Job *Infrastruktura* se přeskočil | Chybí proměnná `AZURE_CLIENT_ID` – nejdřív spusťte `setup-azure` (`.ps1` nebo `.sh`) |
| Smoke test čeká a vyprší | Studený start Javy; podívejte se do logu: `az webapp log tail -g rg-javadays-cicd -n <app>` |
| Aplikace neodpovídá na portu | Nastavte v Bicepu app setting `SERVER_PORT` na `80` a nasaďte znovu |
| Název aplikace je obsazený | Změňte `appName` v `infra/main.bicepparam` (musí být globálně unikátní) |
| Skript hlásí *Repozitář … nevidím* (`gh: Not Found (HTTP 404)`) | Repozitář na GitHubu ještě neexistuje, nebo k němu přihlášený účet nemá přístup. Založte ho (`gh repo create <účet>/javadays-2026-cicd --public` nebo `-CreateRepo`), účet ověříte `gh auth status` |
| Push hlásí *refusing to allow an OAuth App to create or update workflow* | Přihlášení `gh` nemá oprávnění `workflow`: `gh auth refresh -h github.com -s workflow` a skript spusťte znovu |
| Push hlásí *rejected (fetch first)* | Repozitář na GitHubu už obsahuje commity (např. README z webu) – použijte prázdný repozitář |
| První běh CD spadne na `azure/login` nebo *AuthorizationFailed* hned po skriptu | Nová identita a role se v Azure propisují pár minut – v GitHubu dejte *Re-run failed jobs* |
| PowerShell: *running scripts is disabled on this system* | `Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned` (pokud to nezakazuje politika organizace) |
| PowerShell: *… is not digitally signed* | Soubory ze staženého ZIPu odblokujte: `Get-ChildItem .\scripts\*.ps1 \| Unblock-File` |
| PowerShell: *Azure CLI / GitHub CLI není přihlášené* | `az login`, `gh auth login` a skript spusťte znovu (je opakovatelný) |
