# Named workspaces

Name each Hyprland workspace from the Omarchy bar. A named workspace shows its number and name together (`1 web`). An empty name shows only the number. A short hairline separates workspaces. The workspace you are on uses the theme accent color.

Enabling this plugin replaces the stock `omarchy.workspaces` widget. Removing it puts that widget back.

Names are labels for the bar. Hyprland still addresses each workspace by its number.

## Install

```bash
omarchy plugin add https://github.com/kdriedger/omarchy-named-workspaces.git --enable
```

If this machine already has a local `linuxbox.workspaces` folder, remove it first:

```bash
omarchy plugin remove linuxbox.workspaces --yes
omarchy plugin add https://github.com/kdriedger/omarchy-named-workspaces.git --enable
```

## Usage

Right-click a workspace to rename it. Enter saves. Escape cancels. Clear the field to show only the number.

Names are stored in `~/.local/state/omarchy/workspace-names.json`.

## Remove

```bash
omarchy plugin remove linuxbox.workspaces --yes
```

## Dependencies

None. The plugin is QML loaded by the Omarchy shell. It does not install packages, change Hyprland config, or request extra privileges.

## License

[MIT](LICENSE)
