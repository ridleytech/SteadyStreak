# SteadyStreak

SteadyStreak is an iOS app for tracking daily exercise goals, logging reps, and planning macro goals for fitness routines. It features customizable reminders, progress tracking, and upgradeable features for power users.

## Features

- **Add & Edit Exercises:** Set up exercises with daily rep goals and custom schedules.
- **Progress Logging:** Log your daily progress and view historical data with charts.
- **Reminders:** Flexible notification scheduling (interval-based or custom times).
- **Themes:** Choose from multiple color themes, including dark and high-contrast options.
- **Macro Planner:** Estimate long-term goals and save macro plans (Pro feature).
- **Upgrade Option:** Unlock unlimited goals and macro planning with a one-time purchase.

## Screenshots

_(Add screenshots here)_

## Getting Started

### Requirements

- Xcode 15 or later
- iOS 17.6 or later

### Installation

1. Clone the repository:
   ```sh
   git clone <repo-url>
   ```
2. Open `SteadyStreak.xcodeproj` in Xcode.
3. Build and run on a simulator or device.

### Project Structure

- [`SteadyStreak/`](SteadyStreak/) — Main app source code
- [`SteadyStreakTests/`](SteadyStreakTests/) — Unit tests
- [`SteadyStreakUITests/`](SteadyStreakUITests/) — UI tests

### Key Files

- [`App.swift`](SteadyStreak/App.swift): App entry point and setup
- [`ContentViews.swift`](SteadyStreak/ContentViews.swift): Main UI and navigation
- [`Models.swift`](SteadyStreak/Models.swift): Data models (Exercise, RepEntry, AppSettings, MacroGoal)
- [`DataService.swift`](SteadyStreak/DataService.swift): Data querying and aggregation
- [`Scheduler.swift`](SteadyStreak/Scheduler.swift): Background and local notification scheduling
- [`StoreKitManager.swift`](SteadyStreak/StoreKitManager.swift): In-app purchase logic
- [`Theme.swift`](SteadyStreak/Theme.swift): Theme and palette definitions

## Customization

- **Notification Times:** Change reminder modes and times in the Settings screen.
- **Themes:** Select your preferred color theme in Settings.
- **Macro Planner:** Use the Macro Planner to estimate and save long-term goals (requires upgrade).

## Contributing

Pull requests are welcome! For major changes, please open an issue first to discuss what you would like to change.

## License

_(Add your license here)_
