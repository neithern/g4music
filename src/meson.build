
sources = [
  'ape-demux.c',
  'application.vala',
  'async-task.vala',
  'gst-player.vala',
  'gst-level.c',
  'main.vala',
  'mini-bar.vala',
  'mpris.vala',
  'paintables.vala',
  'play-bar.vala',
  'preferences.vala',
  'song.vala',
  'song-entry.vala',
  'song-store.vala',
  'tag-parser.vala',
  'thumbnailer.vala',
  'window.vala',
]

conf = configuration_data()
conf.set_quoted('APP_ID', app_id)
conf.set_quoted('VERSION', version)
conf.set_quoted('LOCALEDIR', get_option('prefix') / get_option('localedir'))
configure_file(output: 'config.h', configuration: conf)

sources += gnome.compile_resources('g4music-resources',
  'g4music.gresource.xml',
  c_name: 'g4music'
)

executable('g4music', sources,
  vala_args: [
    meson.current_source_dir () + '/config.vapi',
    meson.current_source_dir () + '/gst-ext.vapi',
  ],
  dependencies: dependencies,
  install: true,
)
