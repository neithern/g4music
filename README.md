# G4Music

Play your music in an elegant way.

![Screen shot](./shots/window.png)
![Screen shot](./shots/playbar.png)
![Screen shot](./shots/playlist.png)

A fast, fluent, light weight music player written in GTK4, with a beautiful, adaptive user interface, so named G4Music.

## Features
- Supports most music file types, samba and any other remote protocols (thanks to great GIO and GStreamer).
- Fast loading and parsing hundreds of music files, in very few seconds.
- Low memory usage for large playlist with album covers, no thumbnail caches to store.
- Sort by album/artist/title or shuffle, supports full-text searching.
- Album cover is original resolution, can be exported.
- Gaussian blurred cover as window background. 
- Follow GNOME 42 light/dark mode.
- Supports MPRIS control.
- Supports drag-drop from file manager.
- Supports pipewire audio sink.
- Show dynamic audio peak when playing.
- All these in a small package with 300KB.

## Install from Flathub
<a href="https://flathub.org/apps/details/com.github.neithern.g4music">
<img src="https://flathub.org/assets/badges/flathub-badge-en.png" width="120"/></a>

## How to build 
It is written in Vala, simple and clean code, with few third-party dependencies:

1. Clone the code from gitlab.
2. Install vala, develop packages of gtk4, libadwaita, gstreamer.
3. Run in the project directory:

    `meson setup build`

    `meson install -C build`

## Change Log
Check the [app data](./data/app.appdata.xml.in) for change log.

## About this project
I was inspired by [Amberol](https://gitlab.gnome.org/World/amberol), but it has some performance issues and missing some key features, but I am not good at Rust so can't help more.

Then I found it is very convenient to write code in Vala language: handle signal with closure, async tasks, easy to compile with C code, so I decided to write a new music player in Vala, focusing on smooth experience and high performance, for those people who has large number of songs.
