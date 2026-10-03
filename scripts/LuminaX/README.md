# LuminaX Lua Subsystem

This directory contains the core Lua modules and entry points for LuminaX.

## Module Structure

* `main.lua`: Main script entry point and coordinator across all subsystems.
* `version.lua`: Version constants and SemVer comparison engine.
* `modules/osc.lua`: Timeline, seekbar, volume slider, and on-screen control layouts.
* `modules/screensaver.lua`: TMDB metadata integration, logo processing, and pause screensaver.
* `modules/subtitle.lua`: Real-time subtitle styling drawer and preset manager.
* `modules/menu.lua`: Floating menus for playlists, chapters, audio, and video settings.
* `modules/huds.lua`: Notification capsules for volume, seeks, delays, and updates.
* `modules/tag_editor.lua`: Tracker watermark cleaner and title editor.
* `modules/updater.lua`: Background release checks and in-player update runner.
* `modules/smart_skip.lua`: Smart chapter skip, Next Episode binge card, and seekbar zone tinting.
* `modules/utils.lua`: Geometry, color formatting, and ASS drawing utilities.

For full installation instructions, keybindings, and configuration documentation, refer to the main repository [README.md](../../README.md) or at https://github.com/lumidenoir/LuminaX.
