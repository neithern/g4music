project('com.github.neithern.g4music',
  ['c', 'vala'],
  version: '0.1'
)

gnome = import('gnome')
i18n = import('i18n')

app_id = meson.project_name()
version = meson.project_version()

add_project_arguments('-DGETTEXT_PACKAGE="' + app_id + '"', language: 'c')
add_project_arguments('-DGNOME_DESKTOP_USE_UNSTABLE_API', language: 'c')

libm_dep = meson.get_compiler('c').find_library('m', required: false)

tracker_sparql_dep = dependency('tracker-sparql-3.0', required: false)
if tracker_sparql_dep.found()
  add_project_arguments('--define=HAS_TRACKER_SPARQL', language: 'vala')
endif

dependencies = [
  dependency('gnome-desktop-4'),
  dependency('gstreamer-1.0'),
  dependency('libadwaita-1'),
  dependency('taglib_c'),
  libm_dep,
  tracker_sparql_dep,
]

subdir('data')
subdir('po')
subdir('src')

gnome.post_install(
  glib_compile_schemas: true,
  gtk_update_icon_cache: true,
  update_desktop_database: true,
)
