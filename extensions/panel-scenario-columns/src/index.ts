import { definePanel } from '@directus/extensions-sdk';
import PanelComponent from './panel.vue';

export default definePanel({
  id: 'panel-scenario-summary',
  name: 'Scenario Summary Analysis',
  icon: 'analytics',
  description: 'Dropdown to choose a scenario, run public.f_summary_year(), and render results',
  component: PanelComponent,
  minWidth: 24,
  minHeight: 12,
  options: [
    {
      field: 'collection',
      type: 'string',
      name: 'Scenario Table',
      meta: {
        interface: 'system-collection',
        options: { includeSystem: false, includeSingleton: false },
        width: 'half',
      },
      schema: { default_value: 'scenario' },
    },
    {
      field: 'functionSchema',
      name: 'Function Schema',
      type: 'string',
      meta: { interface: 'input', width: 'half' },
      schema: { default_value: 'public' },
    },
    {
      field: 'functionName',
      name: 'Function Name',
      type: 'string',
      meta: { interface: 'input', width: 'half' },
      schema: { default_value: 'f_summary_year' },
    },
    {
      field: 'showParameters',
      name: 'Show Parameters Panel',
      type: 'boolean',
      meta: {
        interface: 'boolean',
        width: 'half',
        note: 'Display the parameters used for the function call',
      },
      schema: { default_value: true },
    },
    {
      field: 'autoFormat',
      name: 'Auto-format Numbers',
      type: 'boolean',
      meta: {
        interface: 'boolean',
        width: 'half',
        note: 'Format numbers as currency/energy units',
      },
      schema: { default_value: true },
    },
    {
      field: 'exportEnabled',
      name: 'Enable Export',
      type: 'boolean',
      meta: {
        interface: 'boolean',
        width: 'half',
        note: 'Allow exporting results to CSV',
      },
      schema: { default_value: true },
    },
  ],
});
