import { definePanel } from '@directus/extensions-sdk';
import PanelComponent from './panel.vue';

export default definePanel({
  id: 'csv-import',
  name: 'CSV Import',
  icon: 'upload_file',
  description: 'Upload CSV files with column mapping and bulk import',
  component: PanelComponent,
  minWidth: 12,
  minHeight: 12,
  options: [
    {
      field: 'collection',
      type: 'string',
      name: 'Target Collection (Settings)',
      meta: {
        interface: 'system-collection',
        options: {
          includeSystem: false,
          includeSingleton: false,
        },
        width: 'half',
        note: 'Select the collection where CSV data will be imported (can be overridden in panel)'
      },
    },
    {
      field: 'allowTableSelection',
      name: 'Allow Table Selection in Panel',
      type: 'boolean',
      meta: {
        interface: 'boolean',
        width: 'half',
        note: 'Allow users to select the target table from a dropdown in the panel'
      },
      schema: {
        default_value: true
      }
    },
    {
      field: 'showPreview',
      name: 'Show Data Preview',
      type: 'boolean',
      meta: {
        interface: 'boolean',
        width: 'half',
      },
      schema: {
        default_value: true
      }
    },
    {
      field: 'maxPreviewRows',
      name: 'Preview Rows',
      type: 'integer',
      meta: {
        interface: 'input',
        width: 'half',
        options: {
          placeholder: '10'
        }
      },
      schema: {
        default_value: 10
      }
    }
  ],
});