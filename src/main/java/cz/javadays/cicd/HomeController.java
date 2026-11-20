package cz.javadays.cicd;

import org.springframework.stereotype.Controller;
import org.springframework.ui.Model;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestParam;

@Controller
public class HomeController {

    private final GreetingService greetingService;
    private final InfoService infoService;

    // DEMO krok 3: sem přidáte pole s @Value("${app.monitoring:false}")

    public HomeController(GreetingService greetingService, InfoService infoService) {
        this.greetingService = greetingService;
        this.infoService = infoService;
    }

    @GetMapping("/")
    public String home(@RequestParam(name = "name", required = false) String name, Model model) {
        model.addAttribute("greeting", greetingService.greet(name));
        model.addAttribute("info", infoService.info());
        // DEMO krok 3: model.addAttribute("monitoring", monitoring);
        return "index";
    }
}
