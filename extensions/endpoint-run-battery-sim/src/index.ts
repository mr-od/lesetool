// import { defineEndpoint } from '@directus/extensions-sdk';

// export default defineEndpoint((router) => {
// 	router.get('/', (_req, res) => res.send('Hello, World!'));
// });

// extensions/run-sql-endpoint/index.ts
import { defineEndpoint } from '@directus/extensions-sdk';

export default defineEndpoint((router, { database }) => {
  router.post('/', async (req, res) => {
    const { site_id, initial_soc_kwh, charge_limit_kwh } = req.body;

    if (!site_id || !initial_soc_kwh || !charge_limit_kwh) {
      res.status(400).json({ error: 'Missing required parameters.' });
      return;
    }

    try {
      const result = await database.raw(
        `SELECT run_battery_simulation_by_site(?, ?, ?)`,
        [site_id, initial_soc_kwh, charge_limit_kwh]
      );
      res.json({ success: true, result });
    } catch (error) {
      console.error('Error running SQL:', error);
      res.status(500).json({ success: false, error: 'Execution failed.' });
    }
  });

  return router;
});