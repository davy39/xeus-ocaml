// File: /tests/jest.setup.js

const fs = require('fs');
const path = require('path');

// --- NEW: Asynchronous Mock XMLHttpRequest ---
// This mock simulates the async, binary-safe fetching used by the new xmerlin.ml
class MockXMLHttpRequest {
  constructor() {
    this.status = 0;
    this.response = null;
    this.responseType = '';
    this.onload = () => {};
    this.onerror = () => {};
  }

  open(method, url, async) {
    this._method = method;
    this._url = url;
    this._async = async; // Should be true for our async_get
  }

  send() {
    // Simulate the async nature of a network request with setTimeout
    setTimeout(() => {
      // The test server root is the project root. The URL will be relative.
      const filePath = path.resolve(__dirname, '..', this._url.replace('./', ''));

      if (fs.existsSync(filePath)) {
        this.status = 200;
        // Read the file and return it as an ArrayBuffer, which is what the
        // OCaml code now correctly expects for `responseType = 'arraybuffer'`.
        const buffer = fs.readFileSync(filePath);
        // Convert Node's Buffer to a standard ArrayBuffer
        this.response = buffer.buffer.slice(buffer.byteOffset, buffer.byteOffset + buffer.byteLength);
        // Trigger the success callback
        this.onload();
      } else {
        console.error(`MockXMLHttpRequest: File not found at ${filePath} (URL: ${this._url})`);
        this.status = 404;
        this.response = null;
        // Trigger the error callback
        this.onerror();
      }
    }, 0); // 0ms delay simulates the next turn of the event loop
  }
}
global.XMLHttpRequest = MockXMLHttpRequest;


// --- Mock OCaml C Stubs (unchanged) ---
global.caml_ml_merlin_fs_exact_case = (path) => path;
global.caml_ml_merlin_fs_exact_case_basename = (path) => 0;

// --- Load the OCaml Kernel and Expose the API (unchanged) ---
const ocamlKernel = require('../_build/default/src/xocaml/xocaml.bc.js');
global.xocaml_api = {
  merlinSync: ocamlKernel.xocaml.processMerlinAction,
  toplevelAsync: ocamlKernel.xocaml.processToplevelAction,
};