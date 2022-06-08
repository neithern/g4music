### Run at project root directory:
1. Update template.pot: xgettext -f po/POTFILES.in -o po/template.pot
2. Update a language XX.po: msgmerge -o po/XX.po po/XX.po po/template.pot
