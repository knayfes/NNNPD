# Repository Guidelines

## Project Structure & Module Organization

This is a Godot 4 project configured in `project.godot` (4.7 features, Forward Plus, and Jolt Physics). The project currently has no game scenes or dedicated asset or test directories. `icon.svg` is the project icon. The enabled `addons/godot_mcp/` plugin contains its editor entry point, runtime autoload, tool handlers in `tools/`, and shared helpers in `utils/`. Keep new game code and assets separate from the plugin, using clearly named directories as the project grows. Keep Godot-generated `.uid` and relevant `.import` metadata alongside their source files.

## Build, Test, and Development Commands

- `godot --editor --path .` opens the project in the Godot editor for editing and importing assets. Use the Godot 4.7 executable, substituting its actual name or path if necessary.
- `godot --headless --editor --path . --quit` imports resources and checks editor startup without a graphical window.
- `godot --path .` runs the project once a main scene has been configured in Project Settings. No main scene is currently set.

No export presets or standalone build scripts are present; configure export presets in the editor before building distributable packages.

## Coding Style & Naming Conventions

Use UTF-8 and LF line endings, as specified by `.editorconfig` and `.gitattributes`. Follow existing GDScript: tabs for indentation, `snake_case` for files, functions and variables, `PascalCase` for class names, and `UPPER_SNAKE_CASE` for constants. Use type annotations where useful and keep plugin changes consistent with adjacent code. Prefer the editor UI for project settings.

## Testing Guidelines

There is no committed test suite, test framework, or coverage threshold. For changes, run the headless editor command above and exercise affected scenes or plugin functionality in the editor; describe manual checks in the pull request. Add focused automated tests when introducing a test framework, and document how to run them.

## Commits & Pull Requests

Git history was unavailable in this workspace, so no existing commit convention could be verified. Use concise, imperative commit summaries. Pull requests should explain the change and verification performed, link related issues where applicable, and include screenshots or recordings for visible changes. Do not commit `.godot/` or `/android/` generated output.
