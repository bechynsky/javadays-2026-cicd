package cz.javadays.cicd;

import static org.junit.jupiter.api.Assertions.assertTrue;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;

@SpringBootTest
class DemoApplicationTests {

    @Autowired
    private ApiController api;

    @Test
    void contextLoadsAndApiAnswers() {
        assertTrue(api.greeting("Praha").get("message").contains("Praha"));
    }
}
