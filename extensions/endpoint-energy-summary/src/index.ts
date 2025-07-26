// import { defineEndpoint } from '@directus/extensions-sdk';

// export default defineEndpoint((router) => {
// 	router.get('/', (_req, res) => res.send('Hello, World!'));
// });

import { defineEndpoint } from '@directus/extensions-sdk';

export default defineEndpoint((router, { database }) => {
  router.post('/', async (req, res) => {
    let { query, limit, offset } = req.body;

    if (!query || !query.trim().toLowerCase().startsWith('select')) {
      res.status(400).json({ error: 'Only SELECT queries are allowed.' });
      return;
    }

    try {
      query = query.trim().replace(/;$/, '');
      const wrappedQuery = `SELECT * FROM (${query}) AS sub LIMIT ${limit ?? 10} OFFSET ${offset ?? 0}`;
      const result = await database.raw(wrappedQuery);
      res.json(result.rows ?? result);
    } catch (error: any) {
      console.error('SQL error:', error);
      res.status(500).json({ error: error.message ?? 'SQL execution failed' });
    }
  });

  return router;
});