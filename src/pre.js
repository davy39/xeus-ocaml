try {

    Module['ocamlWorker'] = new Worker('/xeus/kernel/xocaml/x-ocaml.worker+effects.js');

    // 4. Set up an onerror handler to catch loading errors (like 404s).
    // This is CRITICAL for debugging worker loading issues.
    Module.ocamlWorker.onerror = (error) => {
        console.error('[pre.js] FATAL ERROR IN WORKER:', error);
    };
    
} catch (e) {
    // This will catch synchronous errors, e.g., if the path is syntactically invalid
    // or if the browser's security policy blocks worker creation.
    console.error('[pre.js] A synchronous error occurred while creating the worker:', e);
    alert('A critical error occurred setting up the application worker. Check the console.');
}
