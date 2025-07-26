// import { definePanel } from '@directus/extensions-sdk';
// import PanelComponent from './panel.vue';

// export default definePanel({
//   id: 'sql-table-panel',
//   name: 'SQL Table Panel',
//   icon: 'table',
//   description: 'Run a SELECT SQL query and view results as a table.',
//   component: PanelComponent,
//   options: [
//     {
//       field: 'sql_query',
//       name: 'SQL Query',
//       type: 'string',
//       meta: {
//         interface: 'input-code',
//         options: {
//           language: 'sql',
//         },
//         width: 'full',
//       },
//     },
//   ],
//   minWidth: 6,
//   minHeight: 6,
// });



///////V2 WORKING
import { definePanel } from '@directus/extensions-sdk';
import PanelComponent from './panel.vue';

export default definePanel({
  id: 'sql-table-panel',
  name: 'SQL Table Panel',
  icon: 'table',
  description: 'Run a SELECT SQL query and view results as a table.',
  component: PanelComponent,
  options: [
    {
      field: 'sql_query',
      name: 'SQL Query',
      type: 'string',
      meta: {
        interface: 'input-code',
        options: {
          language: 'sql',
        },
        width: 'full',
      },
    },
    {
      field: 'column_order',
      name: 'Column Order (comma-separated)',
      type: 'string',
      meta: {
        interface: 'input',
        // placeholder: 'e.g., country, name, age',
        width: 'full',
      },
    },
  ],
  minWidth: 6,
  minHeight: 6,
});

///////////v4//////////////////
