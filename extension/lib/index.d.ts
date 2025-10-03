/**
 * @file This file defines the main JupyterLab plugin for executing frontend
 * commands triggered by kernel messages.
 * @author Davy Cottet
 * @copyright 2025
 */
import { JupyterFrontEndPlugin } from '@jupyterlab/application';
/**
 * The main plugin object exported for JupyterLab.
 */
declare const plugin: JupyterFrontEndPlugin<void>;
export default plugin;
