
sources = [
  'application.vala',
  'async-task.vala',
  'gst-player.vala',
  'main.vala',
  'mpris.vala',
  'paintables.vala',
  'play-bar.vala',
  'preferences.vala',
  'song-entry.vala',
  'song-store.vala',
  'tag-parser.vala',
  'thumbnailer.vala',
  'window.vala',
]

sources += gnome.compile_resources('g4music-resources',
  'g4music.gresource.xml',
  c_name: 'g4music'
)

executable('g4music', sources,
  dependencies: dependencies,
  install: true,
)
