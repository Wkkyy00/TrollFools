//
//  AppListSearchModel.swift
//  TrollFools
//
//  Created by 82Flex on 3/8/25.
//

import Combine
import UIKit

final class AppListSearchModel: NSObject, ObservableObject {
    @Published var searchKeyword: String = ""
    
    // ======== 修改部分：加入本地持久化记忆 ========
    @Published var searchScopeIndex: Int = {
        let key = "DefaultSearchScopeIndex"
        // 如果本地还没有存过，默认给 1（最近注入），0 是全部应用
        if UserDefaults.standard.object(forKey: key) == nil {
            return 1
        }
        return UserDefaults.standard.integer(forKey: key)
    }() {
        didSet {
            UserDefaults.standard.set(searchScopeIndex, forKey: "DefaultSearchScopeIndex")
        }
    }
    // ======== 修改部分结束 ========

    weak var searchController: UISearchController?
    weak var forwardSearchBarDelegate: (any UISearchBarDelegate)?
}

extension AppListSearchModel: UISearchBarDelegate, UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        searchKeyword = searchController.searchBar.text ?? ""
    }

    func searchBarShouldBeginEditing(_ searchBar: UISearchBar) -> Bool {
        forwardSearchBarDelegate?.searchBarShouldBeginEditing?(searchBar) ?? true
    }

    func searchBarTextDidBeginEditing(_ searchBar: UISearchBar) {
        forwardSearchBarDelegate?.searchBarTextDidBeginEditing?(searchBar)
    }

    func searchBarShouldEndEditing(_ searchBar: UISearchBar) -> Bool {
        forwardSearchBarDelegate?.searchBarShouldEndEditing?(searchBar) ?? true
    }

    func searchBarTextDidEndEditing(_ searchBar: UISearchBar) {
        forwardSearchBarDelegate?.searchBarTextDidEndEditing?(searchBar)
    }

    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        forwardSearchBarDelegate?.searchBar?(searchBar, textDidChange: searchText)
    }

    func searchBar(_ searchBar: UISearchBar, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        forwardSearchBarDelegate?.searchBar?(searchBar, shouldChangeTextIn: range, replacementText: text) ?? true
    }

    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        forwardSearchBarDelegate?.searchBarSearchButtonClicked?(searchBar)
    }

    func searchBarBookmarkButtonClicked(_ searchBar: UISearchBar) {
        forwardSearchBarDelegate?.searchBarBookmarkButtonClicked?(searchBar)
    }

    func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
        forwardSearchBarDelegate?.searchBarCancelButtonClicked?(searchBar)
    }

    func searchBarResultsListButtonClicked(_ searchBar: UISearchBar) {
        forwardSearchBarDelegate?.searchBarResultsListButtonClicked?(searchBar)
    }

    func searchBar(_ searchBar: UISearchBar, selectedScopeButtonIndexDidChange selectedScope: Int) {
        searchScopeIndex = selectedScope
        forwardSearchBarDelegate?.searchBar?(searchBar, selectedScopeButtonIndexDidChange: selectedScope)
    }
}
