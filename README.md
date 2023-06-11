<img align="left" alt="Project logo" src="data/icons/hicolor/scalable/apps/app.svg" />

# G4Music
Play your music elegantly.


<img src="./shots/window.png" width="822"/>
<img src="./shots/playbar.png" width="458"/>
<img src="./shots/playlist.png" width="458"/>

A fast, fluent, light weight music player written in GTK4, with a beautiful, adaptive user interface, so named G4Music. It is also focusing on high performance, for those people who has huge number of songs.

## Features
- Supports most music file types, samba and any other remote protocols (thanks to great GIO and GStreamer).
- Fast loading and parsing thousands of music files in very few seconds, monitor local changes.
- Low memory usage for huge playlist with album covers, no thumbnail caches to store.
- Sorts by album/artist/title or shuffle, supports full-text searching.
- Supports embedded album art or external images as album cover, embedded can be exported.
- Gaussian blurred cover as window background, follows GNOME 42 light/dark mode.
- Supports drag-drop from GNOME Files, showing music in Files.
- Supports audio peaks visualizer.
- Supports gapless playback.
- Supports ReplayGain track mode.
- Supports pipewire audio sink.
- Supports MPRIS control.
- Only need less than 400KB to install it.

## Install from Flathub
<a href="https://flathub.org/apps/details/com.github.neithern.g4music">
<img src="https://flathub.org/assets/badges/flathub-badge-en.png" width="240"/></a>

## How to build 
It is written in Vala, simple and clean code, with few third-party dependencies:

1. Clone the code from gitlab.
2. Install vala, develop packages of gtk4, libadwaita, gstreamer.
3. Run in the project directory:

    `meson setup build --buildtype=release`

    `meson install -C build`

## Change Log
Check the [release tags](https://gitlab.gnome.org/neithern/g4music/-/tags) for change log.
