import { definePanel } from '@directus/extensions-sdk';
import PanelComponent from './panel.vue';

export default definePanel({
  id: 'hello-button',
  name: 'Open Link Button',
  icon: 'link',
  description: 'A button that opens a custom link in a new tab.',
  component: PanelComponent,
    options: [
    {
      field: 'url',
      name: 'Streamlit App URL',
      type: 'string',
      meta: {
        interface: 'input',
        width: 'full',
        required: true,
      },
    },
  ],
  minWidth: 3,
  minHeight: 3,
});
