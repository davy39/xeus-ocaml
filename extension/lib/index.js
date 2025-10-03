import { INotebookTracker } from '@jupyterlab/notebook';
const plugin = {
    id: 'jupyterlab-commands-executor:plugin',
    description: 'A JupyterLab extension to execute UI commands from kernel comm messages.',
    autoStart: true,
    // On requiert INotebookTracker pour suivre les notebooks actifs.
    requires: [INotebookTracker],
    activate: (app, notebookTracker) => {
        console.log('[CommExecutor] >>> ACTIVATE: Plugin (version INotebookTracker) is starting.');
        const commTargetName = 'jupyterlab-commands-executor';
        const registeredKernels = new Set();
        const registerCommTarget = (kernel) => {
            if (registeredKernels.has(kernel.id)) {
                return;
            }
            console.log(`[CommExecutor] >>> KERNEL: Attempting to register comm target on kernel ${kernel.id}`);
            kernel.registerCommTarget(commTargetName, (comm, openMsg) => {
                console.log('[CommExecutor] >>> COMM: Comm channel opened by kernel!', { openMsg });
                const data = openMsg.content.data;
                const { command, args } = data;
                if (!command) {
                    console.warn('[CommExecutor] >>> COMM: Received open message without a "command" field.');
                    comm.close();
                    return;
                }
                console.log(`[CommExecutor] >>> EXEC: Executing UI command from open message: '${command}'`, args || {});
                app.commands.execute(command, args || {})
                    .then(result => {
                    console.log(`[CommExecutor] >>> EXEC: Command '${command}' executed successfully.`);
                    comm.send({ status: 'success' }); // Envoyer une confirmation simple
                })
                    .catch(error => {
                    console.error(`[CommExecutor] >>> EXEC: Error executing command '${command}':`, error);
                    comm.send({ status: 'error', error: error.message });
                })
                    .finally(() => {
                    // Fermer le comm après l'opération car c'est un message unique.
                    comm.close();
                });
            });
            registeredKernels.add(kernel.id);
            console.log(`[CommExecutor] >>> KERNEL: Comm target "${commTargetName}" successfully registered for kernel: ${kernel.id}`);
            kernel.disposed.connect(() => {
                console.log(`[CommExecutor] >>> KERNEL: Kernel ${kernel.id} disposed. Cleaning up.`);
                registeredKernels.delete(kernel.id);
            });
        };
        // Cette fonction sera appelée pour chaque panneau de notebook.
        const connectToNotebook = (panel) => {
            // Attendre que la session du notebook soit prête avant de faire quoi que ce soit.
            // C'est une étape cruciale pour éviter les race conditions.
            panel.sessionContext.ready.then(() => {
                console.log(`[CommExecutor] >>> NOTEBOOK: Session ready for ${panel.context.path}`);
                const kernel = panel.sessionContext.session?.kernel;
                if (kernel) {
                    registerCommTarget(kernel);
                }
            });
            // Écouter les futurs changements de noyau pour ce panneau spécifique.
            panel.sessionContext.kernelChanged.connect((_, args) => {
                if (args.newValue) {
                    console.log(`[CommExecutor] >>> NOTEBOOK: Kernel changed for ${panel.context.path}`);
                    registerCommTarget(args.newValue);
                }
            });
        };
        // Quand un nouveau notebook est ajouté (ouvert), on s'y connecte.
        notebookTracker.widgetAdded.connect((_, panel) => {
            console.log('[CommExecutor] >>> SIGNAL: widgetAdded fired.');
            connectToNotebook(panel);
        });
        console.log('[CommExecutor] >>> ACTIVATE: Plugin activation finished.');
    }
};
export default plugin;
//# sourceMappingURL=index.js.map