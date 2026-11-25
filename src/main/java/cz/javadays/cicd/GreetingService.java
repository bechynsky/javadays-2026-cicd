package cz.javadays.cicd;

import org.springframework.stereotype.Service;

@Service
public class GreetingService {

    /** DEMO krok 1: změňte tuto hodnotu, pushněte do main a sledujte nasazení. */
    public static final String DEFAULT_NAME = "JavaDays 2026";

    public String greet(String name) {
        String who = (name == null || name.isBlank()) ? DEFAULT_NAME : name.strip();
        return "Nazdar, " + who + "!";
    }
}
