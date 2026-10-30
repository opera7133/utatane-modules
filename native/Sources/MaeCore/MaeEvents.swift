import Foundation

extension MaeSession {
    func permitsTalkFallback(for id: String) -> Bool {
        // Polling, resource queries and playback lifecycle callbacks must stay
        // silent when undefined. In particular OnTranslate/OnBalloonClose can
        // otherwise turn a NothingToTalk response into endless playback.
        guard !["OnTranslate", "OnBalloonClose", "OnSecondChange", "OnMinuteChange", "OnMouseMove", "OnMouseWheel"].contains(id) else { return false }
        return ["OnBoot", "OnFirstBoot", "OnClose", "OnGhostChanging", "OnGhostChanged", "OnShellChanging", "OnShellChanged",
                "OnMouseDoubleClick", "OnMouseClick", "OnKeyPress", "OnCommunicate", "OnChoiceSelect", "OnAITalk", "Mae.Talk"].contains(id)
            || actionAliases.values.contains(id)
    }

    func derivedEvents(_ id: String) -> [String] {
        var names: [String] = []
        if id == "OnSecondChange" {
            for (name, reference, setting) in [("Mikire", 1, "MIKIRE"), ("Kasanari", 2, "KASANARI")] {
                // Missing status references are not an implicit end notification.
                guard ["0", "1"].contains(references[reference]) else { continue }
                let previous = visibilityCounts[name] ?? 0
                if references[reference] == "0" {
                    if previous > 0 { names.append("Mae.\(name)End") }
                    visibilityCounts[name] = 0
                } else {
                    let threshold = max(2, min(86_400, Int(configuration[setting] ?? "20") ?? 20))
                    let count = min(threshold + 1, previous + 1)
                    visibilityCounts[name] = count
                    if previous == 0 { names.append("Mae.\(name)Begin") }
                    else if count == threshold { names.append("Mae.\(name)") }
                }
            }
        } else if id == "OnMouseMove" {
            let area = references[3] + ":" + references[4]
            if references[4].isEmpty { strokeArea = nil; strokeCount = 0 }
            else if strokeArea != area { strokeArea = area; strokeCount = 0 }
            else {
                strokeCount += 1
                let threshold = max(1, min(1_000_000, Int(configuration["SAWARI"] ?? "100") ?? 100))
                if strokeCount >= threshold {
                    strokeCount = 0
                    let name = "Mae.Sawari\(references[3] == "1" ? "Kero" : "Sakura")"
                    names += [name + "." + references[4], name]
                }
            }
        } else if id == "OnCommunicate" {
            let change = words.filter { !$0.text.isEmpty && references[1].contains($0.text) }.reduce(0) { $0 + $1.mood }
            setSentiment(sentiment + change)
            names.append(change < 0 ? "Mae.ResponseAgainst" : "Mae.ResponseFollow")
        } else if id == "OnSurfaceRestore", !references[0].isEmpty {
            names.append("Mae.OnSurfaceRestoreSakura." + references[0])
        }
        return names
    }
}
