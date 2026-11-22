import Foundation

enum TerminalArt {
    static func mug(time: Float) -> [String] {
        let steam = ["  )  (  ", " (  )   ", "  (  )  ", " )  (   "]
        let phase = Int(time * 3) % steam.count
        return [steam[phase], steam[(phase + 1) % steam.count], " .----. ", " | [] |>", " '----' "]
    }

    static func splash(time: Float) -> [String] {
        let steam = ["      (           )", "       )   (     (", "      (     )     )", "       )     (   ("]
        let phase = Int(time * 3) % steam.count
        return [
            "L I Q U I D B R E W",
            "",
            steam[phase],
            steam[(phase + 1) % steam.count],
            steam[(phase + 2) % steam.count],
            "      .-=========-.",
            "      |           |___",
            "      |  ~ BREW ~ |   \\",
            "      |           |   /",
            "      |           |--'",
            "       \\_________/",
            "       '---------'",
            "",
            "  [#] packages   <~> dependencies   {*} discover",
            "",
            "  Fresh packages. A warm terminal.",
            "  Space pauses motion. A returns to the workspace."
        ]
    }
}
