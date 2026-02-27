import SwiftUI

struct ContentView: View {
    @Bindable var appState: AppState
    @Binding var showSettings: Bool
    
    var body: some View {
        NavigationSplitView {
            HistoryList(appState: appState)
                .frame(minWidth: 200)
        } detail: {
            if showSettings {
                SettingsView(appState: appState, showSettings: $showSettings)
            } else if let current = appState.currentTranslation {
                TranslationDetailView(result: current)
            } else {
                PlaceholderView()
            }
        }
        .navigationTitle("TransReader")
        .toolbar {
            ToolbarItemGroup {
                if appState.isTranslating {
                    ProgressView()
                        .controlSize(.small)
                    
                    Button("取消") {
                        appState.cancelCurrentTranslation()
                    }
                    .buttonStyle(.bordered)
                }
                
                Button {
                    showSettings.toggle()
                } label: {
                    Image(systemName: "gearshape")
                }
                .help("设置")
            }
        }
        .alert("错误", isPresented: .constant(appState.error != nil)) {
            Button("确定") {
                appState.error = nil
            }
        } message: {
            if let error = appState.error {
                Text(error)
            }
        }
    }
}

struct PlaceholderView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "character.book.closed")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
            
            Text("按 Cmd+T 截取屏幕翻译")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct HistoryList: View {
    @Bindable var appState: AppState
    
    var body: some View {
        List(selection: $appState.currentTranslation) {
            ForEach(appState.translationHistory, id: \.timestamp) { result in
                HistoryRow(result: result)
                    .tag(result)
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("历史")
    }
}

struct HistoryRow: View {
    let result: TranslationResult
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(result.sourceText)
                .lineLimit(2)
                .font(.body)
            
            HStack {
                Text(result.source.rawValue)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                Text(result.timestamp, style: .time)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
