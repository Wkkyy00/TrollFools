//
//  AppListModel.swift
//  TrollFools
//
//  Created by 82Flex on 2024/10/30.
//

import Combine
import OrderedCollections
import SwiftUI

final class AppListModel: ObservableObject {
    enum Scope: Int, CaseIterable {
        case all
        case recent

        var localizedShortName: String {
            switch self {
            case .all:
                return NSLocalizedString("All", comment: "")
            case .recent:
                return NSLocalizedString("Recent", value: "最近注入", comment: "")
            }
        }

        var localizedName: String {
            switch self {
            case .all:
                return NSLocalizedString("All Applications", comment: "")
            case .recent:
                return NSLocalizedString("Recently Injected", value: "最近注入", comment: "")
            }
        }
    }

    static let recentInjectionsKey = "RecentInjections"
    static var recentInjectedIdentifiers: [String] {
        get { return UserDefaults.standard.stringArray(forKey: recentInjectionsKey) ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: recentInjectionsKey) }
    }
    
    static func recordInjection(for bid: String) {
        var recents = recentInjectedIdentifiers
        if let index = recents.firstIndex(of: bid) {
            recents.remove(at: index)
        }
        recents.insert(bid, at: 0)
        recentInjectedIdentifiers = recents
    }

    static func removeRecentInjection(for bid: String) {
        var recents = recentInjectedIdentifiers
        if let index = recents.firstIndex(of: bid) {
            recents.remove(at: index)
            recentInjectedIdentifiers = recents
        }
    }

    func removeRecentInjectionRecord(for bid: String) {
        Self.removeRecentInjection(for: bid)
        // ======== 优化：为删除记录操作添加弹簧动画 ========
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            self.performFilter()
        }
    }

    static let isLegacyDevice: Bool = { return UIScreen.main.fixedCoordinateSpace.bounds.height <= 736.0 }()
    static let hasTrollStore: Bool = { return LSApplicationProxy(forIdentifier: "com.opa334.TrollStore") != nil }()
    private var _allApplications: [App] = []

    let selectorURL: URL?
    var isSelectorMode: Bool { selectorURL != nil }

    @Published var filter = FilterOptions()
    
    @Published var activeScope: Scope = {
        let key = "DefaultSearchScopeIndex"
        let savedIndex = UserDefaults.standard.object(forKey: key) == nil ? 1 : UserDefaults.standard.integer(forKey: key)
        return Scope(rawValue: savedIndex) ?? .recent
    }()
    
    @Published var activeScopeApps: OrderedDictionary<String, [App]> = [:]

    @Published var unsupportedCount: Int = 0

    lazy var isFilzaInstalled: Bool = {
        if let filzaURL {
            UIApplication.shared.canOpenURL(filzaURL)
        } else {
            false
        }
    }()
    private let filzaURL = URL(string: "filza://view")

    @Published var isRebuildNeeded: Bool = false

    private let applicationChanged = PassthroughSubject<Void, Never>()
    private var cancellables = Set<AnyCancellable>()

    init(selectorURL: URL? = nil) {
        self.selectorURL = selectorURL
        reload()

        // ======== 核心优化：拆分监听，移除导致卡顿的 0.5s 延迟 ========
        
        // 1. 专门监听搜索框，保留 0.3 秒防抖，防止打字过快卡顿
        $filter
            .dropFirst()
            .throttle(for: 0.3, scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] _ in
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    self?.performFilter()
                }
            }
            .store(in: &cancellables)

        // 2. 专门监听分类切换，瞬间响应，零延迟，并注入原生弹簧动画
        $activeScope
            .dropFirst()
            .sink { [weak self] _ in
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    self?.performFilter()
                }
            }
            .store(in: &cancellables)
            
        // ======== 优化结束 ========

        applicationChanged
            .throttle(for: 0.5, scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] _ in
                self?.reload()
            }
            .store(in: &cancellables)

        let darwinCenter = CFNotificationCenterGetDarwinNotifyCenter()
        CFNotificationCenterAddObserver(darwinCenter, Unmanaged.passRetained(self).toOpaque(), { _, observer, _, _, _ in
            guard let observer = Unmanaged<AppListModel>.fromOpaque(observer!).takeUnretainedValue() as AppListModel?
            else {
                return
            }
            observer.applicationChanged.send()
        }, "com.apple.LaunchServices.ApplicationsChanged" as CFString, nil, .coalesce)
    }

    deinit {
        let darwinCenter = CFNotificationCenterGetDarwinNotifyCenter()
        CFNotificationCenterRemoveObserver(darwinCenter, Unmanaged.passUnretained(self).toOpaque(), nil, nil)
    }

    func reload() {
        let allApplications = Self.fetchApplications(&unsupportedCount)
        allApplications.forEach { $0.appList = self }
        _allApplications = allApplications
        performFilter()
    }

    func performFilter() {
        var filteredApplications = _allApplications

        if !filter.searchKeyword.isEmpty {
            filteredApplications = filteredApplications.filter {
                $0.name.localizedCaseInsensitiveContains(filter.searchKeyword) ||
                $0.bid.localizedCaseInsensitiveContains(filter.searchKeyword) ||
                (
                    $0.latinName.localizedCaseInsensitiveContains(
                        filter.searchKeyword
                            .components(separatedBy: .whitespaces).joined()
                    )
                )
            }
        }

        if filter.showPatchedOnly {
            filteredApplications = filteredApplications.filter { $0.isInjected || $0.hasPersistedAssets }
        }

        switch activeScope {
        case .all:
            activeScopeApps = Self.groupedAppList(filteredApplications)
            
        case .recent: 
            let recents = Self.recentInjectedIdentifiers
            let recentApps = filteredApplications.filter { recents.contains($0.bid) }
            let sortedRecentApps = recentApps.sorted {
                let idx1 = recents.firstIndex(of: $0.bid) ?? Int.max
                let idx2 = recents.firstIndex(of: $1.bid) ?? Int.max
                return idx1 < idx2
            }
            
            var recentDict = OrderedDictionary<String, [App]>()
            if !sortedRecentApps.isEmpty {
                recentDict[NSLocalizedString("Recently Injected", value: "最近注入", comment: "")] = sortedRecentApps
            }
            activeScopeApps = recentDict
        }
    }

    private static let excludedIdentifiers: Set<String> = [
        "com.opa334.Dopamine",
        "org.coolstar.SileoStore",
        "xyz.willy.Zebra",
    ]

    private static func fetchApplications(_ unsupportedCount: inout Int) -> [App] {
        let allApps: [App] = LSApplicationWorkspace.default()
            .allApplications()
            .compactMap { proxy in
                guard let id = proxy.applicationIdentifier(),
                      let url = proxy.bundleURL(),
                      let teamID = proxy.teamID(),
                      let appType = proxy.applicationType(),
                      let localizedName = proxy.localizedName()
                else {
                    return nil
                }

                guard !id.hasPrefix("wiki.qaq.") && !id.hasPrefix("com.82flex.") && !id.hasPrefix("ch.xxtou.") else {
                    return nil
                }

                guard !excludedIdentifiers.contains(id) else {
                    return nil
                }

                let shortVersionString: String? = proxy.shortVersionString()
                let app = App(
                    bid: id,
                    name: localizedName,
                    type: appType,
                    teamID: teamID,
                    url: url,
                    version: shortVersionString
                )

                if app.isUser && app.isFromApple {
                    return nil
                }

                guard app.isRemovable else {
                    return nil
                }

                return app
            }

        let filteredApps = allApps
            .filter { $0.isSystem || InjectorV3.main.checkIsEligibleAppBundle($0.url) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        unsupportedCount = allApps.count - filteredApps.count

        return filteredApps
    }
}

extension AppListModel {
    func openInFilza(_ url: URL) {
        guard let filzaURL else {
            return
        }

        let fileURL: URL
        if #available(iOS 16, *) {
            fileURL = filzaURL.appending(path: url.path)
        } else {
            fileURL = URL(string: filzaURL.absoluteString + (url.path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ""))!
        }

        UIApplication.shared.open(fileURL)
    }

    func rebuildIconCache() {
        DispatchQueue.global(qos: .userInitiated).async {
            LSApplicationWorkspace.default().openApplication(withBundleID: "com.opa334.TrollStore")
        }
    }
}

extension AppListModel {
    static let allowedCharacters = "ABCDEFGHIJKLMNOPQRSTUVWXYZ#"
    private static let allowedCharacterSet = CharacterSet(charactersIn: allowedCharacters)

    private static func groupedAppList(_ apps: [App]) -> OrderedDictionary<String, [App]> {
        var groupedApps = OrderedDictionary<String, [App]>()

        for app in apps {
            var key = app.name
                .trimmingCharacters(in: .controlCharacters)
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .applyingTransform(.stripCombiningMarks, reverse: false)?
                .applyingTransform(.toLatin, reverse: false)?
                .applyingTransform(.stripDiacritics, reverse: false)?
                .prefix(1).uppercased() ?? "#"

            if let scalar = UnicodeScalar(key) {
                if !allowedCharacterSet.contains(scalar) {
                    key = "#"
                }
            } else {
                key = "#"
            }

            if groupedApps[key] == nil {
                groupedApps[key] = []
            }

            groupedApps[key]?.append(app)
        }

        groupedApps.sort { app1, app2 in
            if let c1 = app1.key.first,
               let c2 = app2.key.first,
               let idx1 = allowedCharacters.firstIndex(of: c1),
               let idx2 = allowedCharacters.firstIndex(of: c2)
            {
                return idx1 < idx2
            }
            return app1.key < app2.key
        }

        return groupedApps
    }
}
