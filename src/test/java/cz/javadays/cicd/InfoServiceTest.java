package cz.javadays.cicd;

import static org.junit.jupiter.api.Assertions.assertEquals;

import java.util.Optional;
import java.util.Properties;

import org.junit.jupiter.api.Test;
import org.springframework.boot.info.BuildProperties;

class InfoServiceTest {

    @Test
    void readsBuildInformation() {
        Properties entries = new Properties();
        entries.setProperty("version", "1.2.3");
        entries.setProperty("number", "42");
        entries.setProperty("commit", "0123456789abcdef");

        InfoService service = new InfoService(
                new AppProperties("dev", "#EC1034"),
                Optional.of(new BuildProperties(entries)));

        AppInfo info = service.info();
        assertEquals("1.2.3", info.version());
        assertEquals("42", info.buildNumber());
        assertEquals("0123456", info.commit());
        assertEquals("dev", info.environment());
        assertEquals("#EC1034", info.themeColor());
    }

    @Test
    void worksWithoutBuildInformation() {
        InfoService service = new InfoService(new AppProperties("local", "#1F6FEB"), Optional.empty());

        AppInfo info = service.info();
        assertEquals("dev", info.version());
        assertEquals("local", info.buildNumber());
    }
}
