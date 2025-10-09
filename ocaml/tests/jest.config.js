module.exports = {
  // Load the compiled OCaml code before running tests.
  // This part is correct and should be kept.
  setupFiles: [
    '<rootDir>/jest.setup.js'
  ],
  // testEnvironment: 'jsdom',
  // Define where your tests are located.
  testMatch: [
    '<rootDir>/*.test.js'
  ],

  // --- FIX #1: PREVENT BABEL TRANSFORMATION ---
  // A list of regexp patterns that Jest uses to detect files that should NOT
  // be transformed. We add our kernel.bc.js to this list.
  // The default is ["/node_modules/"], so we add our path to it.
  transformIgnorePatterns: [
    '/node_modules/',
    '../_build/default/src/xocaml/xocaml.bc.js'

  ],

  // --- FIX #2: IGNORE OPAM AND BUILD DIRECTORIES ---
  // A list of regexp patterns that Jest uses to detect test files.
  // By ignoring these paths, we fix the Haste collision warnings and speed up Jest.
  testPathIgnorePatterns: [
    '../_build/',
    '../.opam/',
  ],
};