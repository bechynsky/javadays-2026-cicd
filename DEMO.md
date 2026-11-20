# Scénář živého dema (cca 15 minut)

Tři ukázky, které na sebe navazují. Každá ukazuje jednu část pipeline.

| # | Ukázka | Co publikum uvidí | Čas |
|---|---|---|---|
| 1 | Změna kódu → push do `main` | CD: build, infra beze změn, nasazení, nové číslo buildu na stránce | ~4 min |
| 2 | Rozbitý test v pull requestu | CI zčervená, merge je zablokovaný | ~4 min |
| 3 | Změna prostředí + aplikace v jednom PR | what-if v PR, po merge nejdřív infra (Application Insights), pak aplikace | ~7 min |

## Příprava (den předem)

- [ ] Repozitář je založený, `scripts/setup-azure.ps1` (nebo `.sh`) proběhl, první běh **CD** je zelený
- [ ] Ruleset na `main` je zapnutý (povinné kontroly `Build & test` a `Bicep lint`, bypass pro admina)
- [ ] Ráno před přednáškou spusťte **CD** ručně (*Actions → CD → Run workflow*) – aplikace se zahřeje
- [ ] Otevřené záložky: repozitář, *Actions*, běžící aplikace, resource group v Azure portálu
- [ ] VS Code s otevřeným repozitářem, větev `main` aktuální (`git pull`)
- [ ] Záloha: snímky obrazovky každého kroku pro případ výpadku Wi-Fi

---

## Krok 1 – Změna kódu (CD)

1. Ukažte běžící aplikaci – nadpis *Ahoj, JavaDays 2026!* a číslo buildu.
2. V `src/main/java/cz/javadays/cicd/GreetingService.java` změňte:

   ```java
   public static final String DEFAULT_NAME = "JavaDays 2026";
   ```

   na

   ```java
   public static final String DEFAULT_NAME = "všichni v sále";
   ```

3. Commit a push:

   ```bash
   git commit -am "Pozdrav pro sál"
   git push
   ```

4. *Actions → CD*: ukažte joby **Build & test → Infrastruktura → Nasazení aplikace**,
   smoke test čeká na nové číslo buildu.
5. Obnovte stránku: *Ahoj, všichni v sále!* a nové číslo buildu.

> Pointa: commit → běžící verze v Azure během pár minut, bez ručního kroku.

## Krok 2 – Rozbitý test (CI jako brána kvality)

1. Nová větev a „drobná“ změna:

   ```bash
   git switch -c demo/nazdar
   ```

   V `GreetingService.java` změňte `"Ahoj, "` na `"Nazdar, "`.

2. Commit, push a pull request:

   ```bash
   git commit -am "Neformální pozdrav"
   git push -u origin demo/nazdar
   gh pr create --fill
   ```

3. V pull requestu: **Build & test** je červený, merge je zablokovaný.
   Otevřete log – test `greetsByName` čekal `Ahoj, Eva!`.
4. Oprava: v `src/test/java/cz/javadays/cicd/GreetingServiceTest.java` změňte očekávání
   na `"Nazdar, Eva!"`, commit + push → CI zezelená.
5. Pull request **zavřete bez merge** (ušetří čas), nebo ho mergněte, pokud čas dovolí.

   ```bash
   gh pr close --delete-branch
   git switch main
   ```

> Pointa: chyba se zastaví v pull requestu, ne u zákazníka.

## Krok 3 – Změna prostředí + aplikace v jednom pull requestu (IaC)

1. Nová větev:

   ```bash
   git switch -c demo/monitoring
   ```

2. **Infrastruktura** – v `infra/main.bicepparam`:

   ```bicep
   param themeColor = '#EC1034'
   param enableMonitoring = true
   ```

3. **Aplikace** – v `src/main/java/cz/javadays/cicd/HomeController.java`:

   - nahraďte komentář `// DEMO krok 3: sem přidáte pole ...` polem:

     ```java
     @org.springframework.beans.factory.annotation.Value("${app.monitoring:false}")
     private boolean monitoring;
     ```

   - v metodě `home` nahraďte komentář řádkem:

     ```java
     model.addAttribute("monitoring", monitoring);
     ```

   V `src/main/resources/templates/index.html` nahraďte komentář `<!-- DEMO krok 3 ... -->` kartou:

   ```html
   <section class="card">
       <span class="label">Monitoring</span>
       <strong th:text="${monitoring} ? 'Application Insights ✔' : 'vypnuto'">vypnuto</strong>
   </section>
   ```

4. Commit, push, pull request:

   ```bash
   git commit -am "Monitoring a nová barva"
   git push -u origin demo/monitoring
   gh pr create --fill
   ```

5. V pull requestu ukažte job **Bicep what-if** → *Summary*: vzniknou `log-…` a `appi-…`,
   Web App dostane nové app settings. Reviewer vidí dopad na prostředí ještě před merge.
6. Merge (`gh pr merge --squash --delete-branch`) → *Actions → CD*:
   nejdřív **Infrastruktura** (vytvoří Application Insights a změní nastavení),
   potom **Nasazení aplikace** se změněným kódem.
7. Obnovte stránku: červené záhlaví a karta *Monitoring: Application Insights ✔*.
   V Azure portálu otevřete Application Insights → *Live metrics* a pár requestů ukažte živě.

> Pointa: prostředí i aplikace mají stejný proces – pull request, review, automatické nasazení
> ve správném pořadí.

## Po přednášce

```powershell
.\scripts\cleanup-azure.ps1 -ResourceGroup rg-javadays-cicd   # Windows
```

```bash
bash scripts/cleanup-azure.sh rg-javadays-cicd                  # bash
```
