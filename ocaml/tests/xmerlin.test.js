// File: /tests/xmerlin.test.js

const { callToplevelAsync, callMerlinSync } = require('./test-utils.js');
const { merlinSync } = global.xocaml_api;

describe('XOCaml Hybrid API (Async Pre-fetch)', () => {
  // Setup is async, so beforeAll must be async.
  beforeAll(async () => {
    console.log('--- beforeAll: Running async Setup command ---');
    const setupPayload = { dsc_url: "./_build/default/src/xmerlin/dynamic/stdlib" };
    const response = await callToplevelAsync('Setup', setupPayload);
    
    expect(response.class).toBe('return');
    expect(response.value).toBe('Setup complete');
    console.log('--- beforeAll: Setup completed successfully. ---');
  });

  test('should be defined globally', () => {
    expect(global.xocaml_api).toBeDefined();
    expect(typeof merlinSync).toBe('function');
  });

  describe('Merlin Commands (Sync)', () => {
    test('Complete_prefix: should get completions for List module', () => {
      const response = callMerlinSync('Complete_prefix', {
        source: 'let l = List.',
        position: ["Offset", 13]
      });

      expect(response.class).toBe('return');
      const value = response.value;
      expect(value.entries.length).toBeGreaterThan(0);
      const mapEntry = value.entries.find(e => e.name === 'map');
      expect(mapEntry).toBeDefined();
      expect(mapEntry.kind).toBe('Value');
    });

    // This test is now updated to expect success.
    test('Document: should return documentation for List.map', () => {
      const response = callMerlinSync('Document', {
        source: 'let x = List.map',
        position: ["Offset", 15] // Cursor on 'map'
      });

      expect(response.class).toBe('return');
      const value = response.value;
      expect(typeof value).toBe('string');
      expect(value).toContain('applies function [f] to');
    });
  });
});