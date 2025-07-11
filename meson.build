project(
  'g4music', [ 'vala', 'c' ],
  version: '4.5',
  license: 'GPL3'
)

app_id = 'com.github.neithern.' + meson.project_name()
version = meson.project_version()

gnome = import('gnome')
i18n = import('i18n')

c_compiler = meson.get_compiler('c')
vala_compiler = meson.get_compiler('vala')

add_project_arguments('-DGETTEXT_PACKAGE="' + meson.project_name() + '"', language: 'c')
add_project_arguments('--enable-experimental-non-null', language: 'vala')

if vala_compiler.version().version_compare('>=0.56.10')
  add_project_arguments('--define=VALA_56_10', language: 'vala')
endif

gtk_dep = dependency('gtk4')
if gtk_dep.version().version_compare('>=4.8') and vala_compiler.version().version_compare('>=0.56.6')
  add_project_arguments('--define=GTK_4_8', language: 'vala')
endif
if gtk_dep.version().version_compare('>=4.10') and vala_compiler.version().version_compare('>=0.56.6')
  add_project_arguments('--define=GTK_4_10', language: 'vala')
endif
if gtk_dep.version().version_compare('>=4.12')
  add_project_arguments('--define=GTK_4_12', language: 'vala')
endif

adw_dep = dependency('libadwaita-1')
if adw_dep.version().version_compare('>=1.2')
  add_project_arguments('--define=ADW_1_2', language: 'vala')
endif
if adw_dep.version().version_compare('>=1.3')
  add_project_arguments('--define=ADW_1_3', language: 'vala')
endif
if adw_dep.version().version_compare('>=1.4')
  add_project_arguments('--define=ADW_1_4', language: 'vala')
endif
if adw_dep.version().version_compare('>=1.5')
  add_project_arguments('--define=ADW_1_5', language: 'vala')
endif
if adw_dep.version().version_compare('>=1.6')
  add_project_arguments('--define=ADW_1_6', language: 'vala')
endif

libm_dep = c_compiler.find_library('m', required: false)
posix_dep = vala_compiler.find_library('posix', required: false)

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
