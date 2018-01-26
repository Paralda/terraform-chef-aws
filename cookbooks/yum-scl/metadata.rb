name             'yum-scl'
maintainer       'Dmitry Shestoperov'
maintainer_email 'dmitry@shestoperov.info'
license          'All rights reserved'
description      'Installs/Configures softwarecollections repositories'
long_description IO.read(File.join(File.dirname(__FILE__), 'README.md'))
version          '0.2.0'
issues_url       'https://github.com/dimsh99/yum-scl/issues'
source_url       'https://github.com/dimsh99/yum-scl'

depends		 'yum'
depends		 'inifile_chef_gem'
