const path = require('path');

module.exports = {
  entry: './src/editor.js',
  output: {
    filename: 'editor.bundle.js',
    path: path.resolve(__dirname, '../Sources/FloatingNotes/Resources/Editor'),
  },
  devtool: false,
  performance: { hints: false },
};
