
sources = [
  'application.vala',
  'config.vapi',
  'main.vala',
  'gst/ape-demux.c',
  'gst/gst-player.vala',
  'gst/tag-parser.vala',
  'ui/mini-bar.vala',
  'ui/music-entry.vala',
  'ui/paintables.vala',
  'ui/peak-bar.vala',
  'ui/play-bar.vala',
  'ui/preferences.vala',
  'ui/volume-button.vala',
  'ui/window.vala',
  'utils/async-task.vala',
  'utils/cover-cache.vala',
  'utils/data-io.vala',
  'utils/dir-cache.vala',
  'utils/mpris.vala',
  'utils/music.vala',
  'utils/music-store.vala',
  'utils/playlist-file.vala',
  'utils/portal.vala',
  'utils/tag-cache.vala',
  'utils/thumbnailer.vala',
]

conf = configuration_data()
conf.set_quoted('APP_ID', app_id)
conf.set_quoted('CODE_NAME', meson.project_name())
conf.set_quoted('VERSION', version)
conf.set_quoted('LOCALEDIR', get_option('prefix') / get_option('localedir'))
configure_file(output: 'config.h', configuration: conf)

c_name = meson.project_name()
res_name = c_name + '-resources'

sources += gnome.compile_resources(res_name,
  'gresource.xml',
  c_name: c_name
)

add_project_arguments('-I' + meson.current_source_dir () + '/gst/', language: 'c')

executable(c_name, sources,
  vala_args: [
    # meson.current_source_dir () + '/config.vapi',
    meson.current_source_dir () + '/gst/gst-ext.vapi',
  ],
  dependencies: dependencies,
  install: true,
)
