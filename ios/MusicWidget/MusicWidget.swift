import WidgetKit
import SwiftUI

struct MusicWidgetEntry: TimelineEntry {
    let date: Date
    let title: String
    let artist: String
    let artwork: UIImage?
}

struct MusicWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> MusicWidgetEntry {
        MusicWidgetEntry(date: Date(), title: "Track Title", artist: "Artist Name", artwork: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (MusicWidgetEntry) -> ()) {
        let entry = MusicWidgetEntry(date: Date(), title: "Track Title", artist: "Artist Name", artwork: nil)
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> ()) {
        // Fetch data from App Group Shared UserDefaults
        let sharedDefaults = UserDefaults(suiteName: "group.com.fireball.music")
        let title = sharedDefaults?.string(forKey: "track_title") ?? "Not Playing"
        let artist = sharedDefaults?.string(forKey: "track_artist") ?? ""
        
        let entry = MusicWidgetEntry(date: Date(), title: title, artist: artist, artwork: nil)
        
        let timeline = Timeline(entries: [entry], policy: .atEnd)
        completion(timeline)
    }
}

struct MusicWidgetView : View {
    var entry: MusicWidgetProvider.Entry

    var body: some View {
        ZStack {
            // Glassmorphism background
            Color(white: 0.1).opacity(0.8)
            
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    if let artwork = entry.artwork {
                        Image(uiImage: artwork)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 50, height: 50)
                            .cornerRadius(8)
                    } else {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(LinearGradient(gradient: Gradient(colors: [.blue, .purple]), startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 50, height: 50)
                            .overlay(
                                Image(systemName: "music.note")
                                    .foregroundColor(.white)
                            )
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.title)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        
                        Text(entry.artist)
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.7))
                            .lineLimit(1)
                    }
                }
                
                Spacer()
                
                HStack {
                    Image(systemName: "backward.fill")
                    Spacer()
                    Image(systemName: "play.fill")
                        .font(.system(size: 20))
                    Spacer()
                    Image(systemName: "forward.fill")
                }
                .foregroundColor(.white)
                .padding(.horizontal, 20)
            }
            .padding()
        }
    }
}

@main
struct MusicWidget: Widget {
    let kind: String = "MusicWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: MusicWidgetProvider()) { entry in
            MusicWidgetView(entry: entry)
        }
        .configurationDisplayName("Fireball Music")
        .description("Control your music from the home screen.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
