project('g4music', ['c', 'vala'],
  version : '0.1')

gnome = import('gnome')
i18n = import('i18n')

subdir('data')
subdir('po')
subdir('src')

gnome.post_install(
  glib_compile_schemas: true,
  gtk_update_icon_cache: true,
  update_desktop_database: true,
)
