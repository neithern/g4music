
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
    meson.project_source_root() + '/src/config.vapi',
    '--gresourcesdir=' + meson.current_build_dir(),
  ],
  dependencies: dependencies,
  install: true,
)
