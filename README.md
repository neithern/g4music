<img align="left" alt="Project logo" src="data/icons/hicolor/scalable/apps/app.svg" />

# Gapless
Play your music elegantly.

<img src="https://gitlab.gnome.org/neithern/screenshots/-/raw/main/g4music/window.png" width="1134"/>
<img src="https://gitlab.gnome.org/neithern/screenshots/-/raw/main/g4music/albums.png" width="1134"/>
<img src="https://gitlab.gnome.org/neithern/screenshots/-/raw/main/g4music/playing.png" width="462"/>
<img src="https://gitlab.gnome.org/neithern/screenshots/-/raw/main/g4music/playlist.png" width="466"/>

Gapless (AKA: G4Music) is a light weight music player written in GTK4, focuses on large music collection.

## Features
- Supports most music file types, Samba and any other remote protocols (depends on GIO and GStreamer).
- Fast loading and parsing thousands of music files in very few seconds, monitor local changes.
- Low memory usage for large music collection with album covers (embedded and external), no thumbnail caches to store.
- Group and sorts by album/artist/title, shuffle list, full-text searching.
- Fluent adaptive user interface for different screen (Desktop, Tablet, Mobile).
- Gaussian blurred cover as background, follows GNOME light/dark mode.
- Supports creating and editing playlists, drag cover to change order or add to another playlist.
- Supports drag and drop with other apps.
- Supports audio peaks visualizer.
- Supports gapless playback.
- Supports normalizing volume with ReplayGain.
- Supports specified audio sink.
- Supports MPRIS control.

## Install from Flathub
<a href="https://flathub.org/apps/com.github.neithern.g4music">
<img src="https://flathub.org/assets/badges/flathub-badge-en.png" width="240"/></a>

## Install from Snapcraft (unofficial)
<a href="https://snapcraft.io/g4music">
<img alt="Get it from the Snap Store" src="https://camo.githubusercontent.com/ab077b20ad9938c23fbdac223ab101df5ed27329bbadbe7f98bfd62d5808f0a7/68747470733a2f2f736e617063726166742e696f2f7374617469632f696d616765732f6261646765732f656e2f736e61702d73746f72652d626c61636b2e737667" data-canonical-src="https://snapcraft.io/static/images/badges/en/snap-store-black.svg" width="240" style="max-width: 100%;"> 

## FreeBSD Dependencies

```bash
pkg install vala meson libadwaita gstreamer1-plugins-all gettext gtk4
```

## macOS Dependencies

### Install Homebrew

First, install Homebrew by running the following command in your terminal:
```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

### Install Required Packages

Once Homebrew is installed, install the necessary dependencies with:
```bash
brew install vala meson gobject-introspection libadwaita ninja gtk4 gstreamer gst-plugins-base gst-plugins-good gst-plugins-bad gst-plugins-ugly gst-libav desktop-file-utils
```

## How to build 

Gapless is written in Vala with clean and straightforward code, relying on minimal third-party dependencies. Follow these steps to build the application:

1. Clone the Repository:
    
    `git clone https://github.com/neithern/g4music.git`
    
    `cd g4music`
    
2. Install Dependencies: Ensure that Vala, GTK4 development packages, libadwaita, and GStreamer are installed on your system.
3. Build the Project: Run the following commands in the project directory:

    `meson setup build --buildtype=release`

    `meson install -C build`

## Change Log
Check the [release tags](https://gitlab.gnome.org/neithern/g4music/-/tags) for change log.

## 问题排查

### Mac运行无响应

添加如下环境变量
```bash
# for g4music
export GSK_RENDERER="gl"
```

然后重新运行
```
g4music
```