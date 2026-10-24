# Install

## 1. Download and move it

1. Download `Blindspot.zip` from the [latest release](../../../releases/latest) and double-click it to unzip.
2. Drag `Blindspot.app` into your **Applications** folder.

## 2. Open it the first time

The app is not signed by Apple, so macOS blocks it the first time.
Do one of these, once:

- **System Settings** (macOS 15 and later):
  1. Double-click `Blindspot.app`.
     macOS says it cannot be opened.
     Click **Done**.
  2. Open **System Settings > Privacy & Security**, scroll down, and click **Open Anyway** next to Blindspot.
  3. Confirm with your password or Touch ID, then click **Open Anyway** once more.
- **Finder** (macOS 13 and 14 only): right-click `Blindspot.app`, choose **Open**, then **Open** again in the dialog.
- **Terminal** (any version): remove the download flag, then open it normally:

  ```
  xattr -dr com.apple.quarantine /Applications/Blindspot.app
  open /Applications/Blindspot.app
  ```

A shield appears in the menu bar.

## 3. Grant permissions

| Permission | Needed for |
|---|---|
| **Screen Recording** | Required. Lets Blindspot read window titles, which is how it spots a Teams share and Teams chat windows. Blindspot never records or saves your screen. |
| **Accessibility** | Optional. Only needed to minimize Teams windows automatically. |

On first launch, Blindspot opens **Settings** on the **Permissions** tab; click **Allow Screen Recording...** to get the macOS prompt.
Accessibility is asked for only when you turn on minimizing in the **Detection** tab.
If you never changed the minimize setting, minimizing is now off until you turn it on in **Detection**.
To come back later, right-click the shield, choose **Settings**, and open the **Permissions** tab.
Each permission shows a green check or a red cross, with a button to the right page in System Settings.
If Accessibility is not allowed and minimizing is off, it shows a gray dash instead, since it is not needed then.
If macOS offers **Quit & Reopen** after you turn one on, accept it.
If Screen Recording still shows a red cross after you allowed it, the tab says "If you already allowed it, quit and reopen Blindspot."

<img src="images/settings-permissions.png" width="440" alt="Permissions tab">

## 4. Start at login (optional)

In **Settings > General**, turn on **Start at Login**.
It takes effect from your next login.
If you move the app, Settings says "Start at Login pointed at an old copy; turn it on again to fix."
If turning it on or off fails, the checkbox goes back to what it was and a short reason appears under it.

## Updating

Right-click the shield and choose **Quit Blindspot**; a second copy would close itself while the old one is running.
Then download the new release and replace the app in Applications.
Repeat step 2.
If you put the new copy somewhere else, turn **Start at Login** on again.
macOS ties permissions to each build's signature, so it may ask for them again; if the Permissions tab shows a red cross even though the switch is on in System Settings, remove Blindspot from that list with the minus button and add it again.

To help keep permissions across updates, [build it yourself](BUILDING.md) with a local signing certificate.

## Uninstall

1. Right-click the shield and choose **Quit Blindspot**.
2. Delete `Blindspot.app`.
3. If you turned on Start at Login, delete `~/Library/LaunchAgents/com.abhichandra.blindspot.plist`.
4. Optionally remove Blindspot from **Screen Recording** and **Accessibility** in **System Settings > Privacy & Security**.
