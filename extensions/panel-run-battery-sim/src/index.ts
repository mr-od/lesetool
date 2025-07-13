// import { definePanel } from '@directus/extensions-sdk';
// import PanelComponent from './panel.vue';

// export default definePanel({
// 	id: 'custom',
// 	name: 'Custom',
// 	icon: 'box',
// 	description: 'This is my custom panel!',
// 	component: PanelComponent,
// 	options: [
// 		{
// 			field: 'text',
// 			name: 'Text',
// 			type: 'string',
// 			meta: {
// 				interface: 'input',
// 				width: 'full',
// 			},
// 		},
// 	],
// 	minWidth: 12,
// 	minHeight: 8,
// });

// import { definePanel } from '@directus/extensions-sdk';
// import PanelComponent from './panel.vue';

// export default definePanel({
//   id: 'run-sql-button',
//   name: 'Battery Simulation Panel',
//   icon: 'cpu',
//   description: 'Trigger the battery simulation SQL function.',
//   component: PanelComponent,
//   options: [],
//   minWidth: 4,
//   minHeight: 6,
// });

import { definePanel } from '@directus/extensions-sdk';
import PanelComponent from './panel.vue';

export default definePanel({
  id: 'run-sql-button',
  name: 'Battery Simulation Panel',
  icon: 'cpu',
  description: 'Trigger a battery simulation SQL function.',
  component: PanelComponent,
  options: [],
  minWidth: 4,
  minHeight: 6,
});
