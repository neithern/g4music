<img align="left" alt="Project logo" src="data/icons/hicolor/scalable/apps/app.svg" />

# G4Music
Play your music elegantly.


<img src="./shots/window.png" width="822"/>
<img src="./shots/playbar.png" width="458"/>
<img src="./shots/playlist.png" width="458"/>

A fast, fluent, light weight music player written in GTK4, with a beautiful, adaptive user interface, so named G4Music. It is also focusing on high performance, for those people who have huge number of songs.

## Features
- Supports most music file types, samba and any other remote protocols (depends on GIO and GStreamer).
- Fast loading and parsing thousands of music files in very few seconds, monitor local changes.
- Low memory usage for huge playlist with album covers, no thumbnail caches to store.
- Sorts by album/artist/title and shuffle, full-text searching.
- Supports embedded album art and external album cover.
- Gaussian blurred cover as background, follows GNOME light/dark mode.
- Drag-drop from GNOME Files, showing music in Files.
- Supports audio peaks visualizer.
- Supports gapless playback.
- Supports normalizing volume with ReplayGain.
- Supports pipewire and other audio sink.
- Supports MPRIS control.
- Only need less than 500KB to install.

## Install from Flathub
<a href="https://flathub.org/apps/com.github.neithern.g4music">
<img src="https://flathub.org/assets/badges/flathub-badge-en.png" width="240"/></a>

## Install from Snapcraft
<a href="https://snapcraft.io/g4music">
<img alt="Get it from the Snap Store" src="https://camo.githubusercontent.com/ab077b20ad9938c23fbdac223ab101df5ed27329bbadbe7f98bfd62d5808f0a7/68747470733a2f2f736e617063726166742e696f2f7374617469632f696d616765732f6261646765732f656e2f736e61702d73746f72652d626c61636b2e737667" data-canonical-src="https://snapcraft.io/static/images/badges/en/snap-store-black.svg" style="max-width: 100%;">

## How to build 
It is written in Vala, simple and clean code, with few third-party dependencies:

1. Clone the code from gitlab.
2. Install vala, develop packages of gtk4, libadwaita, gstreamer.
3. Run in the project directory:

    `meson setup build --buildtype=release`

    `meson install -C build`

## Change Log
Check the [release tags](https://gitlab.gnome.org/neithern/g4music/-/tags) for change log.
