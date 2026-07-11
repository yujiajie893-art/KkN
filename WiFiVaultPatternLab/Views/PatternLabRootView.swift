import SwiftUI

enum PatternLabWallpaper: String, CaseIterable, Identifiable {
    case clean
    case laboratory
    case timeMachine
    case portrait
    case nightLab
    case nightPortrait

    var id: String { rawValue }

    var title: String {
        switch self {
        case .clean: return "纯净背景"
        case .laboratory: return "实验室静坐"
        case .timeMachine: return "时间机器"
        case .portrait: return "现实映射"
        case .nightLab: return "夜间实验室"
        case .nightPortrait: return "夜色肖像"
        }
    }

    var imageName: String? {
        switch self {
        case .clean: return nil
        case .laboratory: return "PatternWallpaper01"
        case .timeMachine: return "PatternWallpaper02"
        case .portrait: return "PatternWallpaper03"
        case .nightLab: return "PatternWallpaper04"
        case .nightPortrait: return "PatternWallpaper05"
        }
    }
}

struct PatternLabRootView: View {
    @StateObject private var model = PatternLabViewModel()

    var body: some View {
        TabView {
            GeneratorView(model: model)
                .tabItem { Label("生成器", systemImage: "text.badge.plus") }

            AnalyzerView(model: model)
                .tabItem { Label("分析器", systemImage: "checkmark.shield") }

            DataSourcesView(model: model)
                .tabItem { Label("来源与隐私", systemImage: "hand.raised.shield") }

            PatternLabPersonalizationView()
                .tabItem { Label("外观", systemImage: "photo.on.rectangle") }
        }
        .tint(.accentColor)
    }
}

struct PatternLabWallpaperBackdrop: View {
    @AppStorage("patternLabWallpaper") private var wallpaperRawValue = PatternLabWallpaper.clean.rawValue
    @AppStorage("patternLabWallpaperDim") private var dimAmount = 0.44
    @AppStorage("patternLabWallpaperBlur") private var blurRadius = 1.5

    private var wallpaper: PatternLabWallpaper {
        PatternLabWallpaper(rawValue: wallpaperRawValue) ?? .clean
    }

    var body: some View {
        Group {
            if let imageName = wallpaper.imageName {
                Image(imageName)
                    .resizable()
                    .scaledToFill()
                    .blur(radius: blurRadius)
                    .overlay(Color.black.opacity(dimAmount))
            } else {
                LinearGradient(
                    colors: [
                        Color.accentColor.opacity(0.16),
                        Color(uiColor: .systemBackground),
                        Color(uiColor: .secondarySystemBackground),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct PatternLabPersonalizationView: View {
    @AppStorage("patternLabWallpaper") private var wallpaperRawValue = PatternLabWallpaper.clean.rawValue
    @AppStorage("patternLabWallpaperDim") private var dimAmount = 0.44
    @AppStorage("patternLabWallpaperBlur") private var blurRadius = 1.5

    var body: some View {
        NavigationStack {
            ZStack {
                PatternLabWallpaperBackdrop()
                Form {
                    Section("背景") {
                        Picker("壁纸", selection: $wallpaperRawValue) {
                            ForEach(PatternLabWallpaper.allCases) { wallpaper in
                                Text(wallpaper.title).tag(wallpaper.rawValue)
                            }
                        }
                        .pickerStyle(.inline)
                    }

                    Section("可读性") {
                        VStack(alignment: .leading) {
                            Text("暗化：\(Int(dimAmount * 100))%")
                            Slider(value: $dimAmount, in: 0...0.8, step: 0.05)
                        }
                        VStack(alignment: .leading) {
                            Text("模糊：\(blurRadius, specifier: "%.1f")")
                            Slider(value: $blurRadius, in: 0...8, step: 0.5)
                        }
                    }

                    Section {
                        Text("壁纸与设置全部保存在本机，不联网下载。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("外观")
        }
    }
}
