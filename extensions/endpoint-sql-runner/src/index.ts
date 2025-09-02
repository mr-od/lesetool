import { defineEndpoint } from '@directus/extensions-sdk';

export default defineEndpoint((router, { database }) => {
  router.post('/run-sql', async (req, res) => {
    try {
      if (!req.accountability?.user) {
        return res.status(401).json({ error: 'Unauthorized' });
      }

      const { query, parameters } = (req.body ?? {}) as {
        query?: string;
        parameters?: { limit?: number };
      };

      if (!query || !/^\s*select\s+/i.test(query)) {
        return res.status(400).json({ error: 'Only SELECT queries are allowed' });
      }

      // 1) Allow trailing semicolons, but block stacked statements
      //    - Strip ALL trailing semicolons + whitespace at the end
      const trimmed = query.trim();
      const withoutTrailing = trimmed.replace(/;+\s*$/g, '');

      // 2) If any semicolons remain, assume stacked statements → block
      if (withoutTrailing.includes(';')) {
        return res.status(400).json({ error: 'Multiple statements are not allowed' });
      }

      // 3) Append LIMIT if missing
      const limit = Math.max(1, Math.min(1000, Number(parameters?.limit ?? 100)));
      const hasLimit = /\blimit\s+\d+\s*$/i.test(withoutTrailing);
      const finalQuery = hasLimit ? withoutTrailing : `${withoutTrailing} LIMIT ${limit}`;

      const result = await database.raw(finalQuery);

      const data =
        (result as any)?.rows ??
        (Array.isArray((result as any)?.[0]) ? (result as any)[0] : result);

      return res.json({
        success: true,
        data,
        rowCount: Array.isArray(data) ? data.length : 0,
      });
    } catch (error: any) {
      console.error('SQL execution error:', error);
      return res.status(500).json({ error: 'Query execution failed', message: error.message });
    }
  });

  return router;
});
