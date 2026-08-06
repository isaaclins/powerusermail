# Powerusermail

> Native macOS mail client with poweruser interface, keybinds and system in mind.

## Hotkeys

### What is a Hotkey?

A hotkey is a global keyboard shortcut that launches a Raycast command from anywhere on your system. Unlike aliases (which require Root Search to be open), hotkeys work even when Raycast is in the background. Press the key combination, and the command runs immediately.

Assigned hotkeys are displayed next to the command name in Root Search when the command is selected, using platform-appropriate symbols.

### How to Set a Hotkey

to assign a hotkey, you can do that from

`Settings > Hotkeys`

1. Open `Powerusermail.app`
2. Press `⌘`+`,` or open the menu bar and choose Settings and then Hotkeys.
3. In the new settings window, click **Create Hotkey**.
4. The keyboard shortcut recorder opens. Press the key combination you want to assign.
5. The hotkey auto-saves after a short countdown, or press `↵` to save immediately.

--- everything from here is AI slop:

**From Settings**

1. Open **Settings → Shortcuts**.
2. Find the command and click **Record Hotkey**.
3. Press your desired key combination in the recorder popover.
4. Save with `↵` or wait for auto-save.

### The Hotkey Recorder

**New** A redesigned, visual keyboard shortcut recorder with auto-save and real-time conflict detection.

When you record a hotkey, a popover appears with a visual key recorder. Here's what you'll see:

- **Real-time key display**: As you press keys, they appear as styled keyboard buttons in the recorder, so you can see exactly what you're recording.
- **Auto-save with countdown**: Once a valid combination is entered, a visual progress bar counts down (~1.5 seconds) before auto-saving. You can press `↵` to save immediately.
- **Conflict warnings**: If the combination conflicts with another command, the recorder highlights in red and shows which command owns the shortcut.
- **Clear button**: Click the `✕` button to remove the current hotkey, or press `Backspace` while recording to clear.

### Supported Key Combinations

A hotkey is typically a modifier key (or combination of modifiers) plus a regular key. Modifiers can also stand on their own: a multi-modifier combination (such as `⌥` `⌘` on macOS or `Ctrl` `⇧` on Windows) or a single modifier key (such as Right `⌘` or Right `Ctrl`) can be assigned as a hotkey. See [Hotkey Types](#hotkey-types) below.

**Modifier Keys**

_(Only on Mac)_ `⌘`, `⌃`, `⌥`, `⇧`, **New** `GlobeIcon` `fn`

_(Only on Windows)_ `Ctrl`, `Alt`, `⇧`, `Win`

**New** Modifier-only hotkeys can be tied to one side of the keyboard: a lone tap records the side you pressed, shown as a small **L** or **R** next to the modifier. Click the key in the recorder to cycle through **left → right → any side**, where any side means either key triggers it.

**Regular Keys**

Letters (A–Z), numbers (0–9), function keys (F1–F24), punctuation (`. , ; = - [ ] / \`), and special keys (Return/Enter, Tab, Escape, Delete, Arrows, Home, End, Page Up/Down).

### Hotkey Types

**New** To give you a wider range of hotkey options we support a few different hotkey types:

#### Single Step

This is when you record your hotkey with one press of each key in the sequence. For example `⌥` `⌘` `A` on Mac or `Ctrl` `⇧` `L` on Windows

#### Multi-Modifier Hotkeys

_(Available on Mac and Windows)_

**New** You can assign hotkeys made up of more than one modifier key, such as `⌥` `⌘` on macOS or `Ctrl` `⇧` on Windows. This gives you more combinations to work with when single modifiers are already taken.

#### Double-Tap Modifiers

**New** You can record a hotkey using a double-tap modifier: two quick presses of a modifier key, such as `⌘`/`Ctrl` `⌘`/`Ctrl`. Release the key between the presses, since holding a modifier and then pressing its opposite side is a different gesture, covered in [Both-Sided Modifiers](#both-sided-modifiers).

#### Single-Tap Modifier Hotkeys

_(Available on Mac and Windows)_

**New** You can use a single modifier key as a hotkey, and left and right modifiers are treated separately. For example, Right `⌘` or Right `⇧` on macOS, or Right `Ctrl` or Right `Alt` on Windows, can each be assigned as their own hotkey, leaving the other side free for its normal use.

#### Both-Sided Modifiers

_(Only on Mac)_

Holding both keys of the same modifier at once (left and right `⌘` together, for example) is a hotkey in its own right, separate from a `⌘` `⌘` double tap, and shows in the recorder as L`⌘` R`⌘`. This only applies to modifier-only hotkeys: as soon as a regular key joins, both sides collapse into one, so left `⌘`, right `⌘`, and `S` records plain `⌘` `S`.

#### Single Key

**New** A single press of certain keys can launch a command, no modifiers needed.

- _(Only on Mac)_ You can assign the `GlobeIcon` / `fn` key as a single-tap hotkey. Before recording it in Raycast, open **System Settings → Keyboard → Press `GlobeIcon` / `fn` key to** and set it to **Do Nothing** so macOS doesn't intercept the press first. Users with an extended keyboard layout can also assign `F13`–`F18` as single-tap hotkeys.

![macOS Keyboard settings showing the fn key set to Do Nothing](https://fz1sd71lwhbqy6sh.public.blob.vercel-storage.com/raycast/images/app/core/mac-commandhotkey-settings.png)

- _(Only on Windows)_ You can assign the `Win` key as a single-tap hotkey.

These keys can also be combined with other keys for more complex shortcuts, such as `fn` `A`, `fn` `Ctrl` `A`, `F13` `⌘`, or `Win` `A`.

### Support for International Keyboards

**New** You can now choose to record hotkeys as either physical keys or key equivalents, making it easier to switch between different keyboard layouts.

- **Physical Key**: The hotkey stays on the same key position across different layouts. For example, a hotkey recorded with the `Z` key on a QWERTZ keyboard corresponds to the `Y` key on a QWERTY keyboard.
- **Key Equivalent**: The hotkey maps to the same character regardless of layout. For example, a hotkey recorded with `Z` on a QWERTZ keyboard remains `Z` when switched to a QWERTY layout.

By default, all hotkeys are recorded as phyical keys. You can configure this for each key. To do this:

1. Open the hotkey recorder from Settings or via Root Search.
2. Record your hotkey if one is not already set.
3. Click on the key you wish to change.
4. No blue dot on the key means it was recorded as a physical key. A blue dot indicates it was recorded as a key equivalent.

> [!NOTE]
> All built-in Raycast shortcuts use key equivalent keys, and this setting cannot be changed.

### Conflict Detection & Overwrites

**New** Improved conflict detection with the ability to overwrite conflicting shortcuts.

The hotkey recorder automatically detects conflicts at two levels:

**Raycast Global Shortcut Conflict**

If you try to assign a combination that's already used as Raycast's main launcher shortcut, you'll see an error: "Already used by Raycast." This type of conflict cannot be overwritten.

**Command Conflict**

If you try to assign a combination already used by another command, the recorder shows the conflicting command's name and icon with a red warning. You have two options:

- **Choose a different combination**: Press new keys to try a different shortcut.
- **Overwrite**: Save the shortcut anyway. The conflicting command loses its hotkey, and your new command takes over. The previous command will need to be reassigned if you still want it to have a hotkey.

**Shortcuts That Can't Coexist**

Raycast also flags hotkeys that can't both work, because one fires on a press the other is still waiting to complete. A single `⌥` tap conflicts with an `⌥` `⌥` double tap, and on macOS a side-agnostic `⌘` tap conflicts with a both-sided L`⌘` R`⌘` hotkey. Combinations using a _different_ modifier are fine, since that press cancels the lone tap. A saved shortcut that conflicts with another shows a red dot, with a tooltip naming the command it clashes with.

### Removing a Hotkey

- Click the `✕` button next to the hotkey display in Settings or the recorder.
- Or open the recorder and press `Backspace` to clear, then save.
- Or use Action Panel → Configure Command → Delete Hotkey.

The hotkey is removed immediately and the global shortcut stops working.
