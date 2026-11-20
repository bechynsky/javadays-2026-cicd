package cz.javadays.cicd;

import org.springframework.boot.context.properties.ConfigurationProperties;

/**
 * Nastavení, které do aplikace posílá prostředí (App Service → app settings z Bicepu).
 * Lokálně se použijí výchozí hodnoty z application.properties.
 */
@ConfigurationProperties(prefix = "app")
public record AppProperties(String environment, String themeColor) {
}
