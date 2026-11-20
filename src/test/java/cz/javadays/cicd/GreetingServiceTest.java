package cz.javadays.cicd;

import static org.junit.jupiter.api.Assertions.assertEquals;

import org.junit.jupiter.api.Test;

class GreetingServiceTest {

    private final GreetingService service = new GreetingService();

    /** DEMO krok 2: změna "Ahoj" bez úpravy tohoto testu shodí CI. */
    @Test
    void greetsByName() {
        assertEquals("Ahoj, Eva!", service.greet("Eva"));
    }

    @Test
    void usesDefaultNameWhenNameIsMissing() {
        String expected = service.greet(GreetingService.DEFAULT_NAME);
        assertEquals(expected, service.greet(null));
        assertEquals(expected, service.greet("   "));
    }

    @Test
    void trimsWhitespace() {
        assertEquals(service.greet("Petr"), service.greet("  Petr  "));
    }
}
