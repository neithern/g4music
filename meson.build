project('com.github.neithern.g4music',
  ['c', 'vala'],
  version: '0.1.0'
)

gnome = import('gnome')
i18n = import('i18n')

app_id = meson.project_name()
version = meson.project_version()

add_project_arguments('-DGETTEXT_PACKAGE="' + app_id + '"', language: 'c')
add_project_arguments('--enable-experimental-non-null', language: 'vala')

libm_dep = meson.get_compiler('c').find_library('m', required: false)

gnome_desktop_dep = dependency('gnome-desktop-4', required: false)
if gnome_desktop_dep.found()
  add_project_arguments('-DGNOME_DESKTOP_USE_UNSTABLE_API', language: 'c')
  add_project_arguments('--define=HAS_GNOME_DESKTOP', language: 'vala')
endif

taglib_c_dep = dependency('taglib_c', required: false)
if taglib_c_dep.found()
  add_project_arguments('--define=HAS_TAGLIB_C', language: 'vala')
endif

tracker_sparql_dep = dependency('tracker-sparql-3.0', required: false)
if tracker_sparql_dep.found()
  add_project_arguments('--define=HAS_TRACKER_SPARQL', language: 'vala')
endif

dependencies = [
  dependency('gstreamer-1.0'),
  dependency('gstreamer-tag-1.0'),
  dependency('libadwaita-1'),
  gnome_desktop_dep,
  libm_dep,
  taglib_c_dep,
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
