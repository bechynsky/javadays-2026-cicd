package cz.javadays.cicd;

/** Informace o běžící verzi – vrací je /api/info a ukazuje je hlavní stránka. */
public record AppInfo(
        String version,
        String buildNumber,
        String commit,
        String environment,
        String themeColor,
        int javaVersion) {
}
