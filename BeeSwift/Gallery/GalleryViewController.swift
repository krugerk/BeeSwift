//
//  GalleryViewController.swift
//  BeeSwift
//
//  Created by Andy Brett on 4/19/15.
//  Copyright 2015 APB. All rights reserved.
//

import UIKit
import SnapKit
import MBProgressHUD
import SwiftyJSON
import HealthKit
import SafariServices
import OSLog
import CoreData

import BeeKit


class GalleryViewController: UIViewController, UICollectionViewDelegateFlowLayout, UICollectionViewDelegate, UISearchBarDelegate, SFSafariViewControllerDelegate {
    let logger = Logger(subsystem: "com.beeminder.beeminder", category: "GalleryViewController")
    
    // Dependencies
    private let currentUserManager: CurrentUserManager
    private let viewContext: NSManagedObjectContext
    private let versionManager: VersionManager
    private let goalManager: GoalManager
    private let healthStoreManager: HealthStoreManager
    
    let stackView = UIStackView()
    let collectionContainer = UIView()
    var collectionView :UICollectionView?
    var collectionViewLayout :UICollectionViewFlowLayout?
    private let freshnessIndicator = FreshnessIndicatorView()
    var deadbeatView = UIView()
    var outofdateView = UIView()
    let outofdateLabel = BSLabel()
    let searchBar = UISearchBar()
    var lastUpdated: Date?
    
    var allGoals : [Goal] = [] {
        didSet {
            setBackgroundView(visibleGoals: visibleGoals, allGoals: allGoals)
        }
    }
    var visibleGoals : [Goal] = [] {
        didSet {
            setBackgroundView(visibleGoals: visibleGoals, allGoals: allGoals)
        }
    }
    
    private enum Section: CaseIterable {
        case main
    }
    
    private var dataSource: UICollectionViewDiffableDataSource<Section, Goal>!
    
    public enum NotificationName {
        public static let openGoal = Notification.Name(rawValue: "com.beeminder.openGoal")
    }
    
    init(currentUserManager: CurrentUserManager,
         viewContext: NSManagedObjectContext,
         versionManager: VersionManager,
         goalManager: GoalManager,
         healthStoreManager: HealthStoreManager) {
        self.currentUserManager = currentUserManager
        self.viewContext = viewContext
        self.versionManager = versionManager
        self.goalManager = goalManager
        self.healthStoreManager = healthStoreManager
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        NotificationCenter.default.addObserver(self, selector: #selector(self.handleSignIn), name: CurrentUserManager.NotificationName.signedIn, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(self.handleSignOut), name: CurrentUserManager.NotificationName.signedOut, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(self.openGoalFromNotification(_:)), name: GalleryViewController.NotificationName.openGoal, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(self.handleGoalsFetchedNotification), name: GoalManager.NotificationName.goalsUpdated, object: nil)
        
        self.view.addSubview(stackView)
        stackView.axis = .vertical
        stackView.alignment = .fill
        stackView.distribution = .fill
        stackView.spacing = 0
        stackView.insetsLayoutMarginsFromSafeArea = true
        stackView.snp.makeConstraints { (make) -> Void in
            make.top.left.right.equalToSuperview()
            make.bottom.equalTo(stackView.keyboardLayoutGuide.snp.top)
        }
        
        configureCollectionView()
        configureDataSource()
        
        
        self.view.backgroundColor = .systemBackground
        self.title = "Goals"
        
        let item = UIBarButtonItem(image: UIImage(systemName: "gearshape.fill"), style: UIBarButtonItem.Style.plain, target: self, action: #selector(self.settingsButtonPressed))
        self.navigationItem.rightBarButtonItem = item
        
        stackView.addArrangedSubview(self.freshnessIndicator)
        self.updateLastUpdatedLabel()
        Timer.scheduledTimer(timeInterval: 60, target: self, selector: #selector(GalleryViewController.updateLastUpdatedLabel), userInfo: nil, repeats: true)
        
        stackView.addArrangedSubview(self.deadbeatView)
        self.deadbeatView.accessibilityIdentifier = "deadbeatView"
        self.deadbeatView.backgroundColor = UIColor.Beeminder.gray
        updateDeadbeatVisibility()
        
        let deadbeatLabel = BSLabel()
        self.deadbeatView.addSubview(deadbeatLabel)
        deadbeatLabel.accessibilityIdentifier = "deadbeatLabel"
        deadbeatLabel.textColor = UIColor.Beeminder.red
        deadbeatLabel.numberOfLines = 0
        deadbeatLabel.font = UIFont.beeminder.defaultFontHeavy.withSize(13)
        deadbeatLabel.text = "Hey! Beeminder couldn't charge your credit card, so you can't see your graphs. Please update your card on beeminder.com or email support@beeminder.com if this is a mistake."
        deadbeatLabel.snp.makeConstraints { (make) -> Void in
            make.top.equalTo(3)
            make.bottom.equalTo(-3)
            make.left.equalTo(10)
            make.right.equalTo(-10)
        }
        self.deadbeatView.isHidden = true
        
        stackView.addArrangedSubview(self.outofdateView)
        self.outofdateView.accessibilityIdentifier = "outofdateView"
        self.outofdateView.backgroundColor = UIColor.Beeminder.gray
        self.outofdateView.isHidden = true
        
        self.outofdateView.addSubview(self.outofdateLabel)
        self.outofdateLabel.accessibilityIdentifier = "outofdateLabel"
        self.outofdateLabel.textColor = UIColor.Beeminder.red
        self.outofdateLabel.numberOfLines = 0
        self.outofdateLabel.font = UIFont.beeminder.defaultFontHeavy.withSize(12)
        self.outofdateLabel.textAlignment = .center
        self.outofdateLabel.snp.makeConstraints { (make) in
            make.top.equalTo(3)
            make.bottom.equalTo(-3)
            make.left.equalTo(10)
            make.right.equalTo(-10)
        }
        
        stackView.addArrangedSubview(self.searchBar)
        self.searchBar.accessibilityIdentifier = "searchBar"
        self.searchBar.delegate = self
        self.searchBar.placeholder = "Filter goals by slug"
        self.searchBar.isHidden = true
        self.searchBar.showsCancelButton = true
        
        stackView.addArrangedSubview(self.collectionContainer)
        
        self.collectionContainer.addSubview(self.collectionView!)
        self.collectionView!.delegate = self
        
        self.collectionView?.snp.makeConstraints { (make) in
            make.top.bottom.equalTo(collectionContainer)
            make.left.right.equalTo(collectionContainer.safeAreaLayoutGuide)
        }
        
        self.collectionView?.refreshControl = {
            let refreshControl = UIRefreshControl()
            refreshControl.addTarget(self, action: #selector(self.fetchGoals), for: UIControl.Event.valueChanged)
            return refreshControl
        }()
        
        self.updateGoals()
        self.fetchGoals()
        
        if currentUserManager.signedIn(context: viewContext) {
            UNUserNotificationCenter.current().requestAuthorization(options: UNAuthorizationOptions([.alert, .badge, .sound])) { (success, error) in
                print(success)
                if success {
                    DispatchQueue.main.async {
                        UIApplication.shared.registerForRemoteNotifications()
                    }
                }
            }
        }
        
        Task { @MainActor in
            do {
                let updateState = try await versionManager.updateState()
                
                switch updateState {
                case .UpdateRequired:
                    self.outofdateView.isHidden = false
                    self.outofdateLabel.text = "This version of the Beeminder app is no longer supported.\n Please update to the newest version in the App Store."
                    self.collectionView?.isHidden = true
                case .UpdateSuggested:
                    self.outofdateView.isHidden = false
                    self.outofdateLabel.text = "There is a new version of the Beeminder app in the App Store.\nPlease update when you have a moment."
                    self.collectionView?.isHidden = false
                case .UpToDate:
                    self.outofdateView.isHidden = true
                    self.collectionView?.isHidden = false
                }
            } catch let error as VersionError {
                logger.error("Error checking for current version: \(error)")
            }
        }
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        self.collectionView!.snp.remakeConstraints { make in
            make.top.equalTo(self.searchBar.snp.bottom)
            make.left.equalTo(self.view.safeAreaLayoutGuide.snp.leftMargin)
            make.right.equalTo(self.view.safeAreaLayoutGuide.snp.rightMargin)
            make.bottom.equalTo(self.collectionView!.keyboardLayoutGuide.snp.top)
        }
        
        applySnapshot()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        if !currentUserManager.signedIn(context: viewContext) {
            let signInVC = SignInViewController()
            signInVC.modalPresentationStyle = .fullScreen
            self.present(signInVC, animated: true, completion: nil)
        } else {
            self.updateGoals()
            self.fetchGoals()
        }
    }
    
    @objc func handleGoalsFetchedNotification() {
        Task {
            self.lastUpdated = await goalManager.goalsFetchedAt
            self.updateGoals()
        }
    }
    
    @objc func settingsButtonPressed() {
        self.navigationController?.pushViewController(SettingsViewController(), animated: true)
    }
    
    @objc func searchButtonPressed() {
        self.toggleSearchBar()
    }
    
    private func toggleSearchBar() {
        self.searchBar.isHidden.toggle()
        
        if searchBar.isHidden {
            self.searchBar.text = ""
            self.searchBar.resignFirstResponder()
            self.updateGoals()
        } else {
            self.searchBar.becomeFirstResponder()
        }
    }
    
    @objc func handleSignIn() {
        self.dismiss(animated: true, completion: nil)
        self.fetchGoals()
        
        UNUserNotificationCenter.current().requestAuthorization(options: UNAuthorizationOptions([.alert, .badge, .sound])) { (success, error) in
            print(success)
        }
    }
    
    @objc func handleSignOut() {
        self.allGoals = []
        self.visibleGoals = []
        self.applySnapshot()
        if self.presentedViewController != nil {
            if type(of: self.presentedViewController!) == SignInViewController.self { return }
        }
        let signInVC = SignInViewController()
        signInVC.modalPresentationStyle = .fullScreen
        self.present(signInVC, animated: true, completion: nil)
    }
    
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        updateGoals()
    }
    
    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        self.searchBar.resignFirstResponder()
        updateGoals()
    }
    
    func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
        self.toggleSearchBar()
    }
    
    func updateDeadbeatVisibility() {
        let isKnownDeadbeat = currentUserManager.user(context: viewContext)?.deadbeat == true
        self.deadbeatView.isHidden = !isKnownDeadbeat
    }
    
    @objc func updateLastUpdatedLabel() {
        let lastUpdated = self.lastUpdated ?? .distantPast
        
        self.freshnessIndicator.update(with: lastUpdated)
    }
    
    
    func setupHealthKit() {
        Task { @MainActor in
            do {
                try await healthStoreManager.ensureGoalsUpdateRegularly()
            } catch {
                // We should display an error UI
            }
        }
    }
    
    @objc func fetchGoals() {
        Task { @MainActor in
            if self.allGoals.count == 0 {
                MBProgressHUD.showAdded(to: self.view, animated: true)
            }
            
            do {
                try await goalManager.refreshGoals()
                self.updateGoals()
            } catch {
                if UIApplication.shared.applicationState == .active {
                    let alert = UIAlertController(title: "Error fetching goals", message: error.localizedDescription, preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
                    self.present(alert, animated: true, completion: nil)
                }
                self.collectionView?.refreshControl?.endRefreshing()
                MBProgressHUD.hide(for: self.view, animated: true)
                self.applySnapshot()
            }
        }
    }
    
    func updateGoals() {
        let goals = goalManager.staleGoals(context: viewContext) ?? []
        self.allGoals = sortedGoals(goals)
        self.updateFilteredGoals()
        self.didUpdateGoals()
    }
    
    func sortedGoals(_ goals: any Sequence<Goal>) -> [Goal] {
        let selectedGoalSort = UserDefaults.standard.value(forKey: Constants.selectedGoalSortKey) as? String ?? Constants.urgencyGoalSortString
        
        switch selectedGoalSort {
        case Constants.nameGoalSortString:
            return goals.sorted(using: [SortDescriptor(\.slug),
                                        SortDescriptor(\.urgencyKey)])
        case Constants.recentDataGoalSortString:
            return goals.sorted(using: [SortDescriptor(\.lastTouch, order: .reverse),
                                        SortDescriptor(\.urgencyKey)])
        case Constants.pledgeGoalSortString:
            return goals.sorted(using: [SortDescriptor(\.pledge, order: .reverse),
                                        SortDescriptor(\.urgencyKey)])
        default:
            return goals.sorted(using: SortDescriptor(\.urgencyKey))
        }
    }
    
    func updateFilteredGoals() {
        let searchText = searchBar.text ?? ""
        
        if searchText == "" {
            self.visibleGoals = self.allGoals
        } else {
            self.visibleGoals = self.allGoals.filter { (goal) -> Bool in
                return goal.slug.lowercased().contains(searchText.lowercased())
            }
        }
    }
    
    private func applySnapshot() {
        var goalsToShow: [Goal] {
            guard versionManager.lastChckedUpdateState() != .UpdateRequired else { return [] }
            return visibleGoals
        }
        
        var snapshot = NSDiffableDataSourceSnapshot<Section, Goal>()
        snapshot.appendSections([.main])
        snapshot.appendItems(goalsToShow, toSection: .main)
        snapshot.reconfigureItems(goalsToShow)
        dataSource.apply(snapshot, animatingDifferences: true)
    }
    
    @objc func didUpdateGoals() {
        self.setupHealthKit()
        self.collectionView?.refreshControl?.endRefreshing()
        MBProgressHUD.hide(for: self.view, animated: true)
        self.applySnapshot()
        self.setBackgroundView(visibleGoals: visibleGoals, allGoals: allGoals)
        self.updateDeadbeatVisibility()
        self.lastUpdated = Date()
        self.updateLastUpdatedLabel()
        self.navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .search, target: self, action: #selector(self.searchButtonPressed))
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        let minimumWidth: CGFloat = 320
        
        let availableWidth = self.collectionView!.frame.width - self.collectionView!.contentInset.left - self.collectionView!.contentInset.right
        let itemSpacing = self.collectionViewLayout!.minimumInteritemSpacing
        
        // Calculate how many cells could fit at the minimum width, rounding down (as we can't show a fractional cell)
        // We need to account for there being margin between cells, so there is 1 fewer margin than cell. We do this by
        // imagining there is some non-showed spacing after the final cell. For example with wo cells:
        // | available width in parent | spacing |
        // |  cell  | spacing |  cell  | spacing |
        let cellsWhileMaintainingMinimumWidth = Int(
            (availableWidth + itemSpacing) /
            (minimumWidth + itemSpacing)
        )
        
        // Calculate how wide a cell can be. This can be larger than our minimum width because we
        // may have rounded down the number of cells. E.g. if we could have fit 1.5 minimum width
        // cells we will only show 1, but can make it 50% wider than minimum
        let targetWidth = (availableWidth + itemSpacing) / CGFloat(cellsWhileMaintainingMinimumWidth) -  self.collectionViewLayout!.minimumInteritemSpacing
        
        return CGSize(width: targetWidth, height: 120)
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, referenceSizeForFooterInSection section: Int) -> CGSize {
        return CGSize(width: 320, height: section == 0 && self.allGoals.count > 0 ? 5 : 0)
    }
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let row = (indexPath as NSIndexPath).row
        if row < self.visibleGoals.count { self.openGoal(self.visibleGoals[row]) }
    }
    
    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        // After a rotation or other size change the optimal width for our cells may have changed.
        coordinator.animate(alongsideTransition: { _ in }, completion: { _ in
            self.collectionViewLayout?.invalidateLayout()
        })
    }
    
    @objc func openGoalFromNotification(_ notification: Notification) {
        guard let notif = notification as NSNotification? else { return }
        var matchingGoal: Goal?
        
        if let identifier = notif.userInfo?["identifier"] as? String {
            if let url = URL(string: identifier), let objectID = viewContext.persistentStoreCoordinator?.managedObjectID(forURIRepresentation: url) {
                matchingGoal = viewContext.object(with: objectID) as? Goal
            }
        }
        else if let slug = notif.userInfo?["slug"] as? String {
            matchingGoal = self.allGoals.filter({ (goal) -> Bool in
                return goal.slug == slug
            }).last
        }
        if matchingGoal != nil {
            self.navigationController?.popToRootViewController(animated: false)
            self.openGoal(matchingGoal!)
        }
    }
    
    func openGoal(_ goal: Goal) {
        let goalViewController = GoalViewController(goal: goal)
        self.navigationController?.pushViewController(goalViewController, animated: true)
    }
    
    private func configureCollectionView() {
        self.collectionViewLayout = UICollectionViewFlowLayout()
        self.collectionView = UICollectionView(frame: stackView.frame, collectionViewLayout: self.collectionViewLayout!)
        self.collectionView?.backgroundColor = .systemBackground
        self.collectionView?.alwaysBounceVertical = true
        self.collectionView?.register(UICollectionReusableView.self, forSupplementaryViewOfKind: UICollectionView.elementKindSectionFooter, withReuseIdentifier: "footer")
    }
    
    private func configureDataSource() {
        let cellRegistration = UICollectionView.CellRegistration<GoalCollectionViewCell, Goal> { cell, indexPath, goal in
            cell.configure(with: goal)
        }
        
        self.dataSource = .init(collectionView: collectionView!, cellProvider: { collectionView, indexPath, goal in
            collectionView.dequeueConfiguredReusableCell(using: cellRegistration,
                                                         for: indexPath,
                                                         item: goal)
        })
        dataSource.supplementaryViewProvider = { collectionView, kind, indexPath in
            collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: "footer", for: indexPath)
        }
        self.collectionView?.dataSource = dataSource
    }
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return versionManager.lastChckedUpdateState() == .UpdateRequired ? 0 : self.visibleGoals.count
    }
    
    func numberOfSections(in collectionView: UICollectionView) -> Int {
        [visibleGoals.isEmpty, allGoals.isEmpty].contains(true) ? 0 : 1
    }
    
    private func setBackgroundView(filteredGoals: [Goal], goals: [Goal]) {
        var view: UIView? {
            switch (visibleGoals.isEmpty, allGoals.isEmpty) {
            case (true, false):
                return self.makeViewForEmptyCollection(when: .noGoalsMatchingFilter)
            case (true, true):
                return self.makeViewForEmptyCollection(when: .noActiveGoals)
            default:
                return nil
            }
        }
        collectionView?.backgroundView = view
    }
    
    private func setBackgroundView(visibleGoals: [Goal], allGoals: [Goal]) {
        var view: UIView? {
            switch (visibleGoals.isEmpty, allGoals.isEmpty) {
            case (true, false):
                return self.makeViewForEmptyCollection(when: .noGoalsMatchingFilter)
            case (true, true):
                return self.makeViewForEmptyCollection(when: .noActiveGoals)
            default:
                return nil
            }
        }
        collectionView?.backgroundView = view
    }
    
    
    
    // MARK: - SFSafariViewControllerDelegate
    
    func safariViewControllerDidFinish(_ controller: SFSafariViewController) {
        controller.dismiss(animated: true, completion: nil)
        self.fetchGoals()
    }
}

private extension GalleryViewController {
    enum NoGoalReason: CaseIterable {
        case noActiveGoals
        case noGoalsMatchingFilter
    }
    
    func makeViewForEmptyCollection(when reason: NoGoalReason) -> UIView {
        let container = UIView()
        
        let viewCorrespondingToReason: UIView = {
            switch reason {
            case .noActiveGoals:
                return noGoalsView
            case .noGoalsMatchingFilter:
                return noGoalsMatchingFilterView
            }
        }()
        container.addSubview(viewCorrespondingToReason)
        container.addSubview(UIView())
        
        viewCorrespondingToReason.snp.makeConstraints { make in
            make.top.lessThanOrEqualTo(100)
            make.horizontalEdges.equalTo(container)
        }
        
        return container
    }
    
    private var noGoalsView: UIView {
        let label = BSLabel()
        label.text = """
        You have no Beeminder goals!
        
        You'll need to create one before this app will be any use.
        """
        label.textAlignment = .center
        label.numberOfLines = 0
        
        return label
    }
    
    private var noGoalsMatchingFilterView: UIView {
        let label = BSLabel()
        label.text = """
        You have Beeminder goals!
        
        None match the current filter.
        """
        label.textAlignment = .center
        label.numberOfLines = 0
        
        return label
    }
}
