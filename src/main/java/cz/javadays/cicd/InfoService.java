package cz.javadays.cicd;

import java.util.Optional;

import org.springframework.boot.info.BuildProperties;
import org.springframework.stereotype.Service;

@Service
public class InfoService {

    private final AppProperties properties;
    private final Optional<BuildProperties> build;

    public InfoService(AppProperties properties, Optional<BuildProperties> build) {
        this.properties = properties;
        this.build = build;
    }

    public AppInfo info() {
        String version = build.map(BuildProperties::getVersion).orElse("dev");
        String number = build.map(b -> b.get("number")).orElse("local");
        String commit = build.map(b -> b.get("commit")).orElse("local");
        return new AppInfo(
                version,
                number,
                shortSha(commit),
                properties.environment(),
                properties.themeColor(),
                Runtime.version().feature());
    }

    private static String shortSha(String sha) {
        return (sha != null && sha.length() > 7) ? sha.substring(0, 7) : sha;
    }
}
