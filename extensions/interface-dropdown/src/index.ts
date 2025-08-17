// import { defineInterface } from '@directus/extensions-sdk';
// import InterfaceComponent from './interface.vue';

// export default defineInterface({
// 	id: 'custom',
// 	name: 'Custom',
// 	icon: 'box',
// 	description: 'This is my custom interface!',
// 	component: InterfaceComponent,
// 	options: null,
// 	types: ['string'],
// });

import { defineInterface } from '@directus/extensions-sdk';
import InterfaceComponent from './interface.vue'; // ✅ static import — no tsconfig changes

export default defineInterface({
  id: 'dropdown-from-collection',
  name: 'Dropdown From Collection',
  icon: 'box',
  description: 'Dropdown populated from another collection',
  component: InterfaceComponent, // ✅ static import avoids dynamic import issue
  types: ['string'],
  group: 'selection', // ✅ valid interface group
  options: [
    {
      field: 'collection',
      name: 'Collection',
      type: 'string',
      meta: {
        interface: 'system-collection',
        width: 'full',
      },
    },
    {
      field: 'valueField',
      name: 'Value Field',
      type: 'string',
      meta: {
        width: 'half',
        note: 'Field used as the actual stored value',
      },
    },
    {
      field: 'labelField',
      name: 'Label Field',
      type: 'string',
      meta: {
        width: 'half',
        note: 'Field used for display in the dropdown',
      },
    },
  ],
});
