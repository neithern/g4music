conf = configuration_data()
conf.set('app_id', app_id)
conf.set('version', version)
conf.set('bindir', get_option('prefix') / get_option('bindir'))

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

service_file = configure_file(
  input: 'app.service.in',
  output: '@0@.service'.format(app_id),
  configuration: conf,
)

install_data(
  service_file,
  install_dir: get_option('datadir') / 'dbus-1' / 'services'
)

appstream_conf = configure_file(
  input: 'app.metainfo.xml.in',
  output: '@0@.metainfo.xml.in'.format(app_id),
  configuration: conf
)

appstream_file = i18n.merge_file(
  input: appstream_conf,
  output: '@0@.metainfo.xml'.format(app_id),
  po_dir: '../po',
  install: true,
  install_dir: get_option('datadir') / 'metainfo'
)

appstreamcli = find_program('appstreamcli', required: false)
if not appstreamcli.found()
  appstreamcli = find_program('appstream-util', required: false)
endif
if appstreamcli.found()
  test('Validate appstream file', appstreamcli,
    args: ['validate', '--no-net', '--explain', appstream_file],
    suite: ['lint'],
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
