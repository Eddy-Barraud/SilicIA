//
//  SilicIASearchWidget.swift
//  SilicIAWidget
//
//  Created by Copilot on 31/03/2026.
//

import SwiftUI
import WidgetKit

private func loadWidgetStrings(_ key: String) -> String {
    let locale = Locale.current
    let langCode: String
    if #available(iOS 16, macOS 13, *) {
        langCode = locale.language.languageCode?.identifier ?? "en"
    } else {
        langCode = locale.languageCode ?? "en"
    }
    let subdirs: [String?] = [nil, "Resources/Localization"]
    for code in [langCode, "en"] {
        let name = "widget.\(code)"
        for subdir in subdirs {
            if let url = Bundle.main.url(forResource: name, withExtension: "json", subdirectory: subdir),
               let data = try? Data(contentsOf: url),
               let dict = try? JSONDecoder().decode([String: String].self, from: data),
               let value = dict[key] {
                return value
            }
        }
    }
    return key
}

private struct SearchWidgetEntry: TimelineEntry {
    let date: Date
}

private struct SearchWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> SearchWidgetEntry {
        SearchWidgetEntry(date: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (SearchWidgetEntry) -> Void) {
        completion(SearchWidgetEntry(date: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SearchWidgetEntry>) -> Void) {
        completion(Timeline(entries: [SearchWidgetEntry(date: Date())], policy: .never))
    }
}

private struct SilicIASearchWidgetView: View {
    var body: some View {
        ZStack {
            Color.clear
            Image(systemName: "magnifyingglass.circle.fill")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .foregroundColor(.accentColor)
                .padding(20)
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

struct SilicIASearchWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "SilicIASearchWidget", provider: SearchWidgetProvider()) { _ in
            SilicIASearchWidgetView()
        }
        .configurationDisplayName(loadWidgetStrings("widget.displayName"))
        .description(loadWidgetStrings("widget.description"))
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
