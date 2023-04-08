project('com.github.neithern.g4music',
  ['c', 'vala'],
  version: '1.9.2'
)

gnome = import('gnome')
i18n = import('i18n')

app_id = meson.project_name()
version = meson.project_version()

add_project_arguments('-DGETTEXT_PACKAGE="' + app_id + '"', language: 'c')
add_project_arguments('--enable-experimental-non-null', language: 'vala')

gtk_dep = dependency('gtk4')
if gtk_dep.version().version_compare('>=4.10.0')
  add_project_arguments('--define=GTK_4_10', language: 'vala')
endif

adw_dep = dependency('libadwaita-1')
if adw_dep.version().version_compare('>=1.2.0')
  add_project_arguments('--define=ADW_1_2', language: 'vala')
endif

libm_dep = meson.get_compiler('c').find_library('m', required: false)
posix_dep = meson.get_compiler('vala').find_library('posix', required: false)

dependencies = [
  dependency('gstreamer-1.0'),
  dependency('gstreamer-tag-1.0'),
  adw_dep,
  libm_dep,
  posix_dep,
]

subdir('data')
subdir('po')
subdir('src')

gnome.post_install(
  glib_compile_schemas: true,
  gtk_update_icon_cache: true,
  update_desktop_database: true,
)
