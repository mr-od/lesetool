// 📁 /extensions/panel-energy-summary/index.ts
import { definePanel } from '@directus/extensions-sdk';
import PanelComponent from './panel.vue';

export default definePanel({
  id: 'energy-summary-panel',
  name: 'Energy Summary Panel',
  icon: 'bar_chart',
  description: 'Displays pivoted year-by-metric energy summary.',
  component: PanelComponent,
  options: [
    {
      field: 'column_mode',
      name: 'Column Layout',
      type: 'string',
      meta: {
        interface: 'select-dropdown',
        width: 'full',
        options: [
          { text: 'Years as Columns', value: 'years' },
          { text: 'Metrics as Columns', value: 'metrics' }
        ],
        // defaultValue: 'years',
        note: 'Choose how to orient the data table.'
      }
    },
  {
  field: 'year_range',
  name: 'Year Range',
  type: 'json',
  meta: {
    interface: 'select-multiple-dropdown',
    width: 'full',
    options: async ({ database }: { database: any }) => {
      const result = await database.raw(
        `SELECT DISTINCT EXTRACT(YEAR FROM timestamp)::int AS year FROM power_consumption ORDER BY year`
      );
      return result.rows.map((r: any) => ({ text: r.year.toString(), value: r.year.toString() }));
    },
    note: 'Select which years to display.'
  }
},
    {
      field: 'order_metrics',
      name: 'Metric Order',
      type: 'json',
      meta: {
        interface: 'select-multiple-dropdown',
        width: 'full',
        options: [
          { text: 'Main Site Consumption', value: 'Main Site Consumption' },
          { text: 'Solar Production', value: 'Solar Production' }
        ],
        note: 'Select which metrics to show and in what order.'
      }
    }
  ],
  minWidth: 6,
  minHeight: 6,
});
