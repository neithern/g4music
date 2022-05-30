scalable_dir = join_paths('hicolor', 'scalable', 'apps')
scalable_conf = configure_file(
  input: join_paths(scalable_dir, 'app.svg'),
  output: '@0@.svg'.format(app_id),
  configuration: conf
)

install_data(
  scalable_conf,
  install_dir: join_paths(get_option('datadir'), 'icons', scalable_dir)
)

symbolic_dir = join_paths('hicolor', 'symbolic', 'apps')
symbolic_conf = configure_file(
  input: join_paths(symbolic_dir, 'app-symbolic.svg'),
  output: '@0@-symbolic.svg'.format(app_id),
  configuration: conf
)

install_data(
  symbolic_conf,
  install_dir: join_paths(get_option('datadir'), 'icons', symbolic_dir)
)
