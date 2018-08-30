//
//  HabitsTableViewController.swift
//  Active
//
//  Created by Tiago Maia Lopes on 06/06/18.
//  Copyright © 2018 Tiago Maia Lopes. All rights reserved.
//

import UIKit
import CoreData
import UserNotifications

/// Controller in charge of displaying the list of tracked habits.
class HabitsTableViewController: UITableViewController, NSFetchedResultsControllerDelegate {

    // MARK: Types

    /// The segments displayed by this controller, which show habits in progress and habits that were completed.
    enum Segment: Int {
        case inProgress
        case completed
    }

    // MARK: Properties

    /// The identifier for the habit creation controller's segue.
    private let newHabitSegueIdentifier = "Create a new habit"

    /// The identifier for the habit details controller's segue.
    private let detailsSegueIdentifier = "Show habit details"

    /// The in progress habit cell's reuse identifier.
    private let inProgressHabitCellIdentifier = "In progress habit table view cell"

    /// The completed habit cell's reuse identifier.
    private let completedHabitCellIdentifier = "Completed habit table view cell"

    /// The used persistence container.
    var container: NSPersistentContainer!

    /// The Habit storage used to fetch the tracked habits.
    var habitStorage: HabitStorage!

    /// The segmented control used to change the habits being displayed, based on its stage (completed or in progress).
    @IBOutlet weak var habitsSegmentedControl: UISegmentedControl!

    /// The fetched results controller used to get the habits that are in progress and display them with the tableView.
    private lazy var progressfetchedResultsController: NSFetchedResultsController<HabitMO> = {
        let fetchedController = habitStorage.makeFetchedResultsController(context: container.viewContext)
        fetchedController.delegate = self

        return fetchedController
    }()

    /// The fetched results controller used to get the habits that are completed and display them with the tableView.
    private lazy var completedfetchedResultsController: NSFetchedResultsController<HabitMO> = {
        let fetchedController = habitStorage.makeCompletedFetchedResultsController(context: container.viewContext)
        fetchedController.delegate = self

        return fetchedController
    }()

    /// The currently selected segment.
    private var selectedSegment: Segment {
        return Segment(rawValue: habitsSegmentedControl.selectedSegmentIndex)!
    }

    /// The fetched results controller for the selected segment (in progress or completed habits).
    /// - Note: This is the fetched results controller used by the tableView's data source, which is chosen based
    ///         on the currently selected segmented.
    private var selectedFetchedResultsController: NSFetchedResultsController<HabitMO> {
        switch selectedSegment {
        case .inProgress:
            return progressfetchedResultsController

        case .completed:
            return completedfetchedResultsController
        }
    }

    // MARK: Deinitialization

    deinit {
        // Remove the registered observers.
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: ViewController Life Cycle

    override func viewDidLoad() {
        super.viewDidLoad()

        // Assert if the dependencies were properly injected.
        assert(container != nil, "The persistent container must be injected.")
        assert(habitStorage != nil, "The habit storage must be injected.")

        // Register to possible notifications thrown by changes in other managed contexts.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleContextChanges(notification:)),
            name: Notification.Name.NSManagedObjectContextDidSave,
            object: nil
        )

        // Configure the nav bar.
        navigationController?.navigationBar.prefersLargeTitles = true

        // Remove the empty separators from the table view.
        tableView.tableFooterView = UIView()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        // Start fetching for the habits.
        // TODO: Check what errors are thrown by the fetch. Every error should be reported to the user.
        do {
            try selectedFetchedResultsController.performFetch()
        } catch {
            assertionFailure("Error: Couldn't fetch the user's habits.")
        }
    }

    // MARK: Navigation

    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        let notificationManager = UserNotificationManager(
            notificationCenter: UNUserNotificationCenter.current()
        )

        switch segue.identifier {
        case newHabitSegueIdentifier:
            // Inject the controller's habit storage, user storage,
            // and persistent container.
            if let habitCreationController = segue.destination as? HabitCreationTableViewController {
                habitCreationController.container = container
                habitCreationController.habitStore = habitStorage
                habitCreationController.userStore = AppDelegate.current.userStorage
                habitCreationController.notificationManager = notificationManager
            } else {
                assertionFailure(
                    "Error: Couldn't get the habit creation controller."
                )
            }
        case detailsSegueIdentifier:
            // Inject the controller's habit, habit storage and container.
            if let habitDetailsController = segue.destination as? HabitDetailsViewController {
                habitDetailsController.container = container
                habitDetailsController.habitStorage = habitStorage
                habitDetailsController.notificationManager = notificationManager

                // Get the selected habit for injection.
                guard let indexPath = tableView.indexPathForSelectedRow else {
                    assertionFailure("Error: couldn't get the user's selected row.")
                    return
                }
                let selectedHabit = selectedFetchedResultsController.object(at: indexPath)

                // Inject the selected habit.
                habitDetailsController.habit = selectedHabit
            } else {
                assertionFailure(
                    "Error: Couldn't get the habit details controller."
                )
            }
        default:
            break
        }
    }

    // MARK: Actions

    @IBAction func switchSegment(_ sender: UISegmentedControl) {
        // TODO: Alert the user in case of errors.
        try? selectedFetchedResultsController.performFetch()
        tableView.reloadData()
    }

    // MARK: DataSource Methods

    override func numberOfSections(in tableView: UITableView) -> Int {
        return selectedFetchedResultsController.sections?.count ?? 1
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if let sections = selectedFetchedResultsController.sections, sections.count > 0 {
            return sections[section].numberOfObjects
        }

        return 0
    }
     override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        var cell: UITableViewCell? = nil

        // Get the current habit object.
        let habit = selectedFetchedResultsController.object(at: indexPath)

        switch selectedSegment {
        case .inProgress:
            cell = tableView.dequeueReusableCell(
                withIdentifier: inProgressHabitCellIdentifier,
                for: indexPath
            )
            if let cell = cell as? HabitTableViewCell {
                // Display the habit properties:
                // Its name.
                cell.nameLabel?.text = habit.name
                // And its progress.
                var pastCount = habit.getCurrentChallenge()?.getPastDays()?.count ?? 0
                let daysCount = habit.getCurrentChallenge()?.days?.count ?? 1

                // If the current day was marked as executed, account it as a past day as well.
                if habit.getCurrentChallenge()?.getCurrentDay()?.wasExecuted ?? false {
                    pastCount += 1
                }

                cell.progressLabel?.text = "\(pastCount) / \(daysCount) completed days"
                cell.progressBar.tint = habit.getColor().uiColor
                // Change the bar's progress (past days / total).
                cell.progressBar.progress = CGFloat(Double(pastCount) / Double(daysCount))
            }
        case .completed:
            cell = tableView.dequeueReusableCell(
                withIdentifier: completedHabitCellIdentifier,
                for: indexPath
            )
            if let cell = cell as? CompletedHabitTableViewCell {
                // Display the habit's name and color.
                cell.nameLabel.text = habit.name
                cell.colorView.backgroundColor = habit.getColor().uiColor
            }
        }

        return cell!
    }

    // MARK: Delegate methods

    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        switch selectedSegment {
        case .inProgress:
            return 145
        case .completed:
            return 100
        }
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        performSegue(withIdentifier: detailsSegueIdentifier, sender: self)
    }

    // MARK: Actions

    /// Listens to any saved changes happening in other contexts and refreshes
    /// the viewContext.
    /// - Parameter notification: The thrown notification
    @objc private func handleContextChanges(notification: Notification) {
        // If the changes were only updates, reload the tableView.
        if (notification.userInfo?["updated"] as? Set<NSManagedObject>) != nil {
            DispatchQueue.main.async {
                self.tableView.reloadData()
            }
        }

        // Refresh the current view context by using the payloads in the notifications.
        container.viewContext.mergeChanges(fromContextDidSave: notification)
    }
}

extension HabitsTableViewController {

    // MARK: NSFetchedResultsControllerDelegate implementation methods

    func controllerWillChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        // Begin the tableView updates.
        tableView.beginUpdates()
    }

    func controller(
        _ controller: NSFetchedResultsController<NSFetchRequestResult>,
        didChange anObject: Any,
        at indexPath: IndexPath?,
        for type: NSFetchedResultsChangeType,
        newIndexPath: IndexPath?
    ) {
        // Only execute the updates if the segment being shown is handled by the passed controller.
        // There're two fetchedResultsController instances managing different segments of the table view,
        // One for the in progress habits and another for the completed ones. Only update the one being displayed.
        guard shouldUpdateSegmentFrom(controller: controller) else { return }

        // Add or remove rows based on the kind of changes:
        switch type {
        case .delete:
            if let indexPath = indexPath {
                tableView.deleteRows(at: [indexPath], with: .automatic)
            }
        case .insert:
            if let indexPath = newIndexPath {
                tableView.insertRows(at: [indexPath], with: .automatic)
            }
        case .move:
            if let indexPath = indexPath, let newIndexPath = newIndexPath {
                tableView.deleteRows(at: [indexPath], with: .automatic)
                tableView.insertRows(at: [newIndexPath], with: .automatic)
            }
        case .update:
            if let indexPath = indexPath {
                tableView.reloadRows(at: [indexPath], with: .automatic)
            }
        }
    }

    /// Informs if the changed fetched results controller should update the current segment being displayed
    /// by the table view.
    /// - Parameter fetchedResultsController: The updated fetched results controller.
    /// - Returns: True if the update should be displayed by the segment, false otherwise.
    private func shouldUpdateSegmentFrom(controller: NSFetchedResultsController<NSFetchRequestResult>) -> Bool {
        switch selectedSegment {
        case .inProgress:
            return controller == progressfetchedResultsController
        case .completed:
            return controller == completedfetchedResultsController
        }
    }

    func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        // End the tableView updates.
        tableView.endUpdates()
    }
}
