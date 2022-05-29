add_project_arguments('-DGNOME_DESKTOP_USE_UNSTABLE_API', language: 'c')

dependencies = [
  dependency('glib-2.0'),
  dependency('gobject-2.0'),
  dependency('gtk4'),
  dependency('gnome-desktop-4'),
  dependency('gstreamer-1.0'),
  dependency('libadwaita-1'),
  dependency('taglib_c'),
  dependency('tracker-sparql-3.0'),
  meson.get_compiler('c').find_library('m', required: false),
]

sources = [
  'async-task.vala',
  'application.vala',
  'gst-player.vala',
  'mpris.vala',
  'paintables.vala',
  'play-bar.vala',
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
