/**
 * Unsigned macOS .app (darwin/x64). Run on macOS with Node 10 after `npm ci` and a production webpack build (`dist/` present).
 * App Store / signed builds still require bin/pack.js on Mac with Apple signing setup.
 */
const packager = require('electron-packager')
const path = require('path')
const pkg = require('../package')

const resourcesPath = path.join(__dirname, '..', 'resources')

packager({
  dir: path.join(__dirname, '..'),
  appCopyright: '© 2019, Zihua Li',
  asar: true,
  overwrite: true,
  electronVersion: pkg.electronVersion,
  icon: path.join(resourcesPath, 'icns', 'MyIcon'),
  out: path.join(__dirname, '..', 'dist', 'out'),
  platform: 'darwin',
  arch: process.env.ELECTRON_ARCH || 'x64',
  appBundleId: `li.zihua.${pkg.name}`,
  appCategoryType: 'public.app-category.developer-tools',
}).then((appPaths) => {
  console.log('Packaged:', appPaths)
}).catch((err) => {
  console.error(err)
  process.exit(1)
})
