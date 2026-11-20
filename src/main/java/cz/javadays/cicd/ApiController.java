package cz.javadays.cicd;

import java.util.Map;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api")
public class ApiController {

    private final GreetingService greetingService;
    private final InfoService infoService;

    public ApiController(GreetingService greetingService, InfoService infoService) {
        this.greetingService = greetingService;
        this.infoService = infoService;
    }

    @GetMapping("/greeting")
    public Map<String, String> greeting(@RequestParam(name = "name", required = false) String name) {
        return Map.of("message", greetingService.greet(name));
    }

    /** Používá ho smoke test v pipeline: ověří, že běží právě nasazený build. */
    @GetMapping("/info")
    public AppInfo info() {
        return infoService.info();
    }
}
