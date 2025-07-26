// import { defineEndpoint } from '@directus/extensions-sdk';

// export default defineEndpoint((router) => {
// 	router.get('/', (_req, res) => res.send('Hello, World!'));
// });

// import { defineEndpoint } from '@directus/extensions-sdk';

// export default defineEndpoint((router, { database }) => {
//   router.post('/', async (req, res) => {
//     const { query } = req.body;

//     if (!query || !query.trim().toLowerCase().startsWith('select')) {
//       res.status(400).json({ error: 'Only SELECT queries are allowed.' });
//       return;
//     }

//     try {
//       const result = await database.raw(query);
//       res.json(result.rows ?? result);
//     } catch (error) {
//       console.error('SQL error:', error);
//       res.status(500).json({ error: 'SQL execution failed.' });
//     }
//   });

//   // ✅ Always return the router
//   return router;
// });


//////////////v2/////////////////////////////////
// import { defineEndpoint } from '@directus/extensions-sdk';

// export default defineEndpoint((router, { database }) => {
//   router.post('/', async (req, res) => {
//     let { query, limit, offset } = req.body;

//     if (!query || !query.trim().toLowerCase().startsWith('select')) {
//       res.status(400).json({ error: 'Only SELECT queries are allowed.' });
//       return;
//     }

//     try {
//       query = query.trim().replace(/;$/, ''); // Remove trailing semicolon
//       const wrappedQuery = `SELECT * FROM (${query}) AS sub LIMIT ${limit ?? 10} OFFSET ${offset ?? 0}`;

//       const result = await database.raw(wrappedQuery);
//       res.json(result.rows ?? result);
//     } catch (error: any) {
//       console.error('SQL error:', error);
//       res.status(500).json({ error: error.message ?? 'SQL execution failed' });
//     }
//   });

//   // ✅ Make sure this is the last line!
//   return router;
// });


//////////////////V3/////////////////////////// Added go to page
import { defineEndpoint } from '@directus/extensions-sdk';

export default defineEndpoint((router, { database }) => {
  router.post('/', async (req, res) => {
    let { query, limit, offset } = req.body;

    if (!query || !query.trim().toLowerCase().startsWith('select')) {
      return res.status(400).json({ error: 'Only SELECT queries are allowed.' });
    }

    try {
      query = query.trim().replace(/;$/, ''); // Remove trailing semicolon

      const countQuery = `SELECT COUNT(*) FROM (${query}) AS sub`;
      const countResult = await database.raw(countQuery);
      const total = parseInt(countResult.rows?.[0]?.count ?? '0');

      const pagedQuery = `SELECT * FROM (${query}) AS sub LIMIT ${limit ?? 10} OFFSET ${offset ?? 0}`;
      const result = await database.raw(pagedQuery);

      return res.json({
        rows: result.rows ?? result,
        total,
      });
    } catch (error: any) {
      console.error('SQL error:', error);
      return res.status(500).json({ error: error.message ?? 'SQL execution failed' });
    }
  });

  return router;
});

///////////v4//////////////////
