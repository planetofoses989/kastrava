const path = require('path')
const HtmlWebpackPlugin = require('html-webpack-plugin')
const CopyPlugin = require('copy-webpack-plugin')

module.exports = [
  {
    target: 'electron-main',
    entry: './src/main.js',
    output: { path: path.resolve(__dirname, 'dist'), filename: 'main.js' },
    node: { __dirname: false, __filename: false },
    externals: { 'sql.js': 'commonjs sql.js', 'electron-updater': 'commonjs electron-updater' }
  },
  {
    target: 'electron-preload',
    entry: './src/preload.js',
    output: { path: path.resolve(__dirname, 'dist'), filename: 'preload.js' },
    node: { __dirname: false, __filename: false }
  },
  {
    target: 'web',
    entry: './src/renderer.js',
    output: { path: path.resolve(__dirname, 'dist'), filename: 'renderer.js' },
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
