/**
 * @file This file defines the main JupyterLab plugin for executing frontend
 * commands triggered by kernel messages.
 * @author Davy Cottet
 * @copyright 2025
 */
import { INotebookTracker } from '@jupyterlab/notebook';
/**
 * The main plugin object exported for JupyterLab.
 */
const plugin = {
    // A unique identifier for the plugin.
    id: 'jupyterlab-commands-executor:plugin',
    description: 'A JupyterLab extension to execute UI commands from kernel comm messages.',
    // Automatically start the plugin on JupyterLab load.
    autoStart: true,
    // We require INotebookTracker to monitor active notebook panels and their kernels.
    requires: [INotebookTracker],
    /**
     * The activation function for the plugin. This is the main entry point.
     * It sets up listeners to register comm targets on notebook kernels as they
     * become available.
     *
     * @param app The JupyterFrontEnd application instance.
     * @param notebookTracker The service that tracks notebook widgets.
     */
    activate: (app, notebookTracker) => {
        // The unique name used by the kernel to open a communication channel with this extension.
        const commTargetName = 'jupyterlab-commands-executor';
        // A set to keep track of kernel IDs for which the comm target has already been registered.
        // This prevents redundant registrations on the same kernel.
        const registeredKernels = new Set();
        /**
         * Registers the comm target on a given kernel connection.
         * This function sets up the listener that will handle incoming messages from the kernel.
         *
         * @param kernel The kernel connection to register the comm target on.
         */
        const registerCommTarget = (kernel) => {
            // Avoid re-registering on the same kernel.
            if (registeredKernels.has(kernel.id)) {
                return;
            }
            // This callback is executed when the kernel opens a comm channel with our target name.
            kernel.registerCommTarget(commTargetName, (comm, openMsg) => {
                // The kernel sends a single message upon opening the comm to execute a command.
                // We extract the command and its arguments from the open message payload.
                const data = openMsg.content.data;
                const { command, args } = data;
                // Ensure a command was actually provided in the message.
                if (!command) {
                    comm.close();
                    return;
                }
                // Use the JupyterLab command registry to execute the requested command.
                app.commands.execute(command, args || {})
                    .then(result => {
                    // Send a simple confirmation back to the kernel (optional but good practice).
                    comm.send({ status: 'success' });
                })
                    .catch(error => {
                    console.error(`[CommExecutor] >>> EXEC: Error executing command '${command}':`, error);
                    comm.send({ status: 'error', error: error.message });
                })
                    .finally(() => {
                    // This is a one-shot communication, so we close the comm immediately after execution.
                    comm.close();
                });
            });
            // Add the kernel ID to the set to prevent future re-registrations.
            registeredKernels.add(kernel.id);
            // Set up a cleanup function for when the kernel is disposed (e.g., shut down).
            kernel.disposed.connect(() => {
                registeredKernels.delete(kernel.id);
            });
        };
        /**
         * Sets up comm registration for a specific notebook panel.
         * It waits for the session to be ready and handles kernel changes.
         *
         * @param panel The NotebookPanel to connect to.
         */
        const connectToNotebook = (panel) => {
            // Crucially, wait for the session context to be ready. This ensures that the
            // kernel is available and avoids race conditions on notebook load.
            panel.sessionContext.ready.then(() => {
                const kernel = panel.sessionContext.session?.kernel;
                if (kernel) {
                    registerCommTarget(kernel);
                }
            });
            // Also, listen for any subsequent kernel changes (e.g., user switches from Python to OCaml).
            // This ensures we register the comm target on the new kernel.
            panel.sessionContext.kernelChanged.connect((_, args) => {
                if (args.newValue) {
                    registerCommTarget(args.newValue);
                }
            });
        };
        // When a new notebook widget is added (i.e., a notebook is opened),
        // we start the process of connecting our logic to it.
        notebookTracker.widgetAdded.connect((_, panel) => {
            connectToNotebook(panel);
        });
    }
};
// Export the plugin as the default export for JupyterLab to discover.
export default plugin;
//# sourceMappingURL=index.js.map