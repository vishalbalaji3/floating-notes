const path = require('path');
const webpack = require('webpack');
const TerserPlugin = require('terser-webpack-plugin');

module.exports = {
  entry: './src/editor.js',
  output: {
    filename: 'editor.bundle.js',
    path: path.resolve(__dirname, '../Sources/FloatingNotes/Resources/Editor'),
    clean: { keep: /index\.html$/ },
  },
  plugins: [new webpack.optimize.LimitChunkCountPlugin({ maxChunks: 1 })],
  optimization: {
    minimizer: [new TerserPlugin({ extractComments: false })],
  },
  devtool: false,
  performance: { hints: false },
};
