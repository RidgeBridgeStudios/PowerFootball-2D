# Boot Splash Plus

Boot Splash Plus is a Godot 4 addon that adds a custom startup loading screen system.

It keeps Godot's default settings under `Application > Boot Splash` and adds a separate custom section under `Application > Boot Splash+`.

## Features

- Separate `Application > Boot Splash+` Project Settings section.
- Custom startup overlay after the engine boot splash.
- Background color or background image.
- Background animation, blur amount, and darken amount.
- PNG, WebP, JPG, JPEG, and SVG logo/background support through Godot's normal runtime loader.
- Logo image or fallback text.
- Logo opacity control.
- Logo animation options: fade in, fade in-out, pulse, scale in, and slight float.
- Real progress bar styling.
- Progress bar position, width, and height controls.
- Progress bar style options: fill, pulse, and blink.
- Editor playtest support.
- Optional wait until the current scene has loaded before fading out.
- Optional Scene Loader mode using the included Boot Splash+ loader scene.
- Optional native splash image disable setting, labeled as not complete engine replacement.
- Optional startup sound/music with fade in and fade out controls.
- Optional sound delay.
- No editor dock.

## How To Use

1. Copy `addons/boot_splash_plus` into your Godot project.
2. Enable `Boot Splash Plus` from `Project > Project Settings > Plugins`.
3. Open `Project > Project Settings > Application > Boot Splash+`.
4. Set `Enabled` to true.
5. Choose background, logo, progress bar colors, and minimum display time.
6. Press Play.

If you do not see the Boot Splash+ settings, enable `Advanced Settings` in the Project Settings window.

Godot's original engine startup still happens before scripts run. Boot Splash+ replaces the practical startup/loading screen after engine boot, not the engine's earliest native splash.

For exported games, disable or minimize Godot's default boot splash in your export preset/project boot splash settings if you want Boot Splash+ to feel like the main startup screen. Do not confuse this with the export icon; the icon is only the app/window icon.

Scene Loader Mode is optional and is off by default. To use it, set `scene_loader/use_as_main_scene` to true, set `scene_loader/target_scene`, and set your project main scene to `res://addons/boot_splash_plus/boot_splash_plus_loader.tscn`. The loader scene shows Boot Splash+ first, loads the target scene, then changes to it.

## Settings

General:

- `general/enabled`
- `general/run_in_editor_playtest`
- `general/wait_for_scene_load`

Scene Loader:

- `scene_loader/use_as_main_scene`
- `scene_loader/target_scene`

Native Splash:

- `native_splash/disable_native_boot_splash_not_completely`

Timing:

- `timing/minimum_display_time_seconds`
- `timing/fade_in_time`
- `timing/fade_out_time`

Background:

- `background/mode`
- `background/color`
- `background/image`
- `background/fit`
- `background/animation`
- `background/animation_duration`
- `background/blur_amount`
- `background/darken_amount`
- `background/overlay_color`

Logo:

- `logo/logo_type`
- `logo/text`
- `logo/image`
- `logo/size_percent`
- `logo/position`
- `logo/opacity`
- `logo/show_fallback_logo`
- `logo/animation`
- `logo/animation_duration`

`logo/logo_type` options are `Logo` and `Text`. The default text is `Boot Splash+`.

Progress Bar:

- `progress_bar/show`
- `progress_bar/position`
- `progress_bar/width_percent`
- `progress_bar/height_px`
- `progress_bar/style`
- `progress_bar/color`
- `progress_bar/background_color`

`progress_bar/position` options are `Lower Middle`, `Bottom`, `More Bottom`, `Center`, and `Top`.

Sound:

- `sound/file`
- `sound/volume_db`
- `sound/pitch_scale`
- `sound/delay_seconds`
- `sound/fade_in`
- `sound/fade_in_time`
- `sound/fade_out`
- `sound/fade_out_time`

## Versioning

Every update should bump the addon version in `addons/boot_splash_plus/plugin.cfg`, the `VERSION` file, and the release zip filename. The visible Godot plugin name should stay clean and not include the version.

Current version: `0.4.5`
