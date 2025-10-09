// File: /tests/toplevel.test.js

const { callToplevelAsync } = require('./test-utils.js');

describe('Eval Command (Async)', () => {
  console.log('--- Starting Toplevel Test Suite ---');

  // beforeAll is now async and sends the setup payload
  beforeAll(async () => {
    console.log('--- beforeAll: Running async Setup command ---');
    const setupPayload = { dsc_url: "./_build/default/src/xmerlin/dynamic/stdlib" };
    const response = await callToplevelAsync('Setup', setupPayload);

    expect(response.class).toBe('return');
    expect(response.value).toBe('Setup complete');
    console.log('--- beforeAll: Setup completed successfully. ---');
  });

  // All other tests in this file remain unchanged.
  test('should evaluate a simple expression', async () => {
    const response = await callToplevelAsync('Eval', { source: '1 + 1' });
    expect(response.class).toBe('return');
    expect(response.value).toEqual([['Value', expect.stringContaining('- : int = 2')]]);
  });

  test('should capture stdout', async () => {
    const response = await callToplevelAsync('Eval', { source: 'print_endline "hello"' });
    expect(response.class).toBe('return');
    expect(response.value).toContainEqual(['Stdout', 'hello\n']);
    expect(response.value).toContainEqual(['Value', expect.stringContaining('- : unit = ()')]);
  });

  test('should capture a type error and send it to stderr', async () => {
    const response = await callToplevelAsync('Eval', { source: '1 + "a"' });
    expect(response.class).toBe('return');
    const stderrOutput = response.value.find(v => v[0] === 'Stderr');
    expect(stderrOutput).toBeDefined();
    expect(stderrOutput[1]).toContain('has type string but an expression was expected of type');
  });

  test('should maintain state between phrases', async () => {
    const response = await callToplevelAsync('Eval', { source: 'let x = 10;; x * 2' });
    expect(response.class).toBe('return');
    expect(response.value).toContainEqual(['Value', expect.stringContaining('val x : int = 10')]);
    expect(response.value).toContainEqual(['Value', expect.stringContaining('- : int = 20')]);
  });

  test('should have access to the standard library', async () => {
    const response = await callToplevelAsync('Eval', { source: 'List.map ((+) 1) [1; 2; 3]' });
    expect(response.class).toBe('return');
    expect(response.value).toEqual([['Value', expect.stringContaining('- : int list = [2; 3; 4]')]]);
  });
});