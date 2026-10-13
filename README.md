# App Closer

Native macOS menu bar utility for quitting selected running applications and saving reusable profiles. Exam Mode is an editable example profile.

## Use

- Click the menu bar icon to open **Open Apps** and **Profiles**; click it again, click outside the panel, or use its close button to dismiss it. Use the gear button to open **Settings** in its own window.
- In Open Apps, type in the search field to filter running applications. **Select All** and **Deselect All** act on the visible results. Click a checkbox or anywhere on an application row, then choose **Quit Selected Apps**. Protected system apps and LockDown Browser cannot be selected.
- Option-click the menu bar icon to run a saved profile directly.
- In Profiles, use **Edit** in the selected profile card to change its name, symbol, or accent. Duplicate and delete are in the card's **More** menu. **Close** and **Keep Open** can each be collapsed; their collapsed state remains while switching between Open Apps and Profiles. With multiple profiles, use **Hide list** or **Show list** beside **New**, or change the setting in Settings. When the list is hidden, use the profile picker to switch profiles. Use **Select All** in **Close** to add currently running eligible apps, except those in **Keep Open**. **Deselect All** clears the Close list.
- Add individual apps from the current running list or choose an application bundle, then run the profile.
- Choose a profile symbol from the scrollable gallery or enter another SF Symbol name. Each profile can have its own muted accent color.
- Profile workspace restoration records the apps that actually quit and can reopen their application bundles later. It does not restore unsaved documents or exact window positions.
- No keyboard shortcut is set by default. Record one in Settings if desired.
- Settings has a color slider for the app accent, a Liquid Glass transparency slider, light, dark, or system appearance, and a **Quit App Closer** button. Drag the lower-right corner of the main panel to resize it.
- Click the symbol at the top of Settings to choose among twelve menu bar symbols, including the original App Closer mark. The app icon uses that same overlapping-window and close motif.

App Closer sends ordinary macOS quit requests. Apps with unsaved work can present their own save dialogs. App Closer never force quits them.

## Build and test

```sh
Scripts/test.sh
Scripts/build.sh
```

The build script prints the signed app bundle path in the temporary build directory. Its bundle identifier is `com.vladikmartinez.appcloser`.
