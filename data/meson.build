conf = configuration_data()
conf.set('app_id', app_id)
conf.set('version', version)

desktop_conf = configure_file(
  input: 'app.desktop.in',
  output: '@0@.desktop.in'.format(app_id),
  configuration: conf
)

desktop_file = i18n.merge_file(
  input: desktop_conf,
  output: '@0@.desktop'.format(app_id),
  type: 'desktop',
  po_dir: '../po',
  install: true,
  install_dir: get_option('datadir') / 'applications'
)

desktop_utils = find_program('desktop-file-validate', required: false)
if desktop_utils.found()
  test('Validate desktop file', desktop_utils,
    args: [desktop_file]
  )
endif

appstream_conf = configure_file(
  input: 'app.appdata.xml.in',
  output: '@0@.appdata.xml.in'.format(app_id),
  configuration: conf
)

appstream_file = i18n.merge_file(
  input: appstream_conf,
  output: '@0@.appdata.xml'.format(app_id),
  po_dir: '../po',
  install: true,
  install_dir: get_option('datadir') / 'metainfo'
)

appstream_util = find_program('appstream-util', required: false)
if appstream_util.found()
  test('Validate appstream file', appstream_util,
    args: ['validate', '--nonet', appstream_file]
  )
endif

gschema_file = configure_file(
  input: 'app.gschema.xml',
  output: app_id + '.gschema.xml',
  configuration: conf,
)

install_data(
  gschema_file,
  install_dir: get_option('datadir') / 'glib-2.0' / 'schemas'
)

compile_schemas = find_program('glib-compile-schemas', required: false)
if compile_schemas.found()
  test('Validate schema file', compile_schemas,
    args: ['--strict', '--dry-run', meson.current_source_dir()]
  )
endif

subdir('icons')
