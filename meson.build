project('com.github.neithern.g4music',
  ['c', 'vala'],
  version: '0.7.0'
)

gnome = import('gnome')
i18n = import('i18n')

app_id = meson.project_name()
version = meson.project_version()

add_project_arguments('-DGETTEXT_PACKAGE="' + app_id + '"', language: 'c')
add_project_arguments('--enable-experimental-non-null', language: 'vala')

libm_dep = meson.get_compiler('c').find_library('m', required: false)

taglib_c_dep = dependency('taglib_c', required: false)
if taglib_c_dep.found()
  add_project_arguments('--define=HAS_TAGLIB_C', language: 'vala')
endif

dependencies = [
  dependency('gstreamer-1.0'),
  dependency('gstreamer-tag-1.0'),
  dependency('libadwaita-1'),
  libm_dep,
  taglib_c_dep,
]

subdir('data')
subdir('po')
subdir('src')

gnome.post_install(
  glib_compile_schemas: true,
  gtk_update_icon_cache: true,
  update_desktop_database: true,
)
