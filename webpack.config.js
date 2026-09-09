const path = require('path')
const HtmlWebpackPlugin = require('html-webpack-plugin')
const CopyPlugin = require('copy-webpack-plugin')
const webpack = require('webpack')

// OUT_DIR switches the output folder (dist = premium default, dist-free = free edition).
const OUT_DIR = process.env.OUT_DIR || 'dist'
// KAS_API is the license/payment server the app + built-in store talk to.
const KAS_API = process.env.KAS_API || 'http://127.0.0.1:8787'

// The edition token (__EDITION__) lives inside the hand-written browser.html
// inline script, so it cannot be swapped via DefinePlugin (inline scripts are
// not transformed). It is rewritten by scripts/build-editions.js via sed.

module.exports = [
  {
    target: 'electron-main',
    entry: './src/main.js',
    output: { path: path.resolve(__dirname, OUT_DIR), filename: 'main.js' },
    node: { __dirname: false, __filename: false },
    plugins: [
      new webpack.DefinePlugin({ __KAS_API__: JSON.stringify(KAS_API) })
    ],
    externals: { 'sql.js': 'commonjs sql.js', 'electron-updater': 'commonjs electron-updater' }
  },
  {
    target: 'electron-preload',
    entry: './src/preload.js',
    output: { path: path.resolve(__dirname, OUT_DIR), filename: 'preload.js' },
    node: { __dirname: false, __filename: false }
  },
  {
    target: 'web',
    entry: './src/renderer.js',
    output: { path: path.resolve(__dirname, OUT_DIR), filename: 'renderer.js' },
    plugins: [
      new HtmlWebpackPlugin({
        template: './src/browser.html',
        filename: 'browser.html',
        minify: false
      }),
      new CopyPlugin({
        patterns: [
          { from: 'static', to: '.' }
        ]
      })
    ]
  }
]
