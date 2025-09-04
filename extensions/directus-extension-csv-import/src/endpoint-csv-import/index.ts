import { defineEndpoint } from '@directus/extensions-sdk';
import { createError } from '@directus/errors';
import Busboy from 'busboy';
import Papa from 'papaparse';
import { executeCopyFromCSV } from '../shared/copy-helper.js'; // Add this line

const ForbiddenError = createError('CSV_IMPORT_FORBIDDEN', 'You need permission to import data to this collection');
const ValidationError = createError('CSV_IMPORT_VALIDATION', 'CSV validation failed');

export default defineEndpoint({
  id: 'csv-import',
  handler: (router, context) => {
    const { services, getSchema, database, logger } = context;
    const { FieldsService, RelationsService, ItemsService, CollectionsService } = services;

    // Get collection schema and detect auto-generated fields
    router.get('/schema/:collection', async (req, res) => {
      try {
        const fieldsService = new FieldsService({
          schema: await getSchema(),
          accountability: req.accountability
        });

        const relationsService = new RelationsService({
          schema: await getSchema(),
          accountability: req.accountability
        });

        const collection = req.params.collection;
        
        // Validate collection exists and user has access
        const itemsService = new ItemsService(collection, {
          schema: await getSchema(),
          accountability: req.accountability
        });

        const fields = await fieldsService.readAll(collection);
        const relations = await relationsService.readAll();

        // Get collection relations for foreign keys
        const collectionRelations = relations.filter(r => 
          r.collection === collection || r.related_collection === collection
        );

        // Separate auto-generated from required fields
        const autoFields = fields.filter(f => 
          f.schema?.has_auto_increment || 
          f.schema?.is_generated ||
          (f.schema?.default_value && String(f.schema.default_value).includes('nextval'))
        );
        
        const requiredFields = fields.filter(f => 
          !autoFields.some(af => af.field === f.field) &&
          !f.schema?.nullable
        );

        // Get foreign key options
        const foreignKeys = {};
        for (const relation of collectionRelations) {
          if (relation.collection === collection && relation.field) {
            try {
              const relatedItemsService = new ItemsService(relation.related_collection, {
                schema: await getSchema(),
                accountability: req.accountability
              });
              
              // Get first 100 items for dropdown
              const relatedItems = await relatedItemsService.readByQuery({
                limit: 100,
                fields: ['*']
              });
              
              foreignKeys[relation.field] = {
                collection: relation.related_collection,
                items: relatedItems
              };
            } catch (err) {
              logger.warn(`Could not fetch items for ${relation.related_collection}`);
            }
          }
        }

        res.json({
          fields: fields.map(f => ({
            field: f.field,
            type: f.type,
            required: !f.schema?.nullable && !autoFields.some(af => af.field === f.field),
            auto: autoFields.some(af => af.field === f.field),
            foreign_key: foreignKeys[f.field] || null
          })),
          autoFields: autoFields.map(f => f.field),
          requiredFields: requiredFields.map(f => f.field),
          foreignKeys
        });

      } catch (error) {
        logger.error('Schema fetch error:', error);
        res.status(500).json({ error: error.message });
      }
    });

    // Validate CSV structure against collection schema
    router.post('/validate/:collection', async (req, res) => {
      try {
        const collection = req.params.collection;
        
        const busboy = Busboy({ headers: req.headers });
        let csvData = '';
        let mapping = {};

        busboy.on('field', (fieldname, val) => {
          if (fieldname === 'mapping') {
            mapping = JSON.parse(val);
          }
        });

        busboy.on('file', async (fieldname, file, info) => {
          if (fieldname === 'csv') {
            const chunks = [];
            file.on('data', (chunk) => chunks.push(chunk));
            file.on('end', async () => {
              csvData = Buffer.concat(chunks).toString();
              
              // Parse CSV
              const parseResult = Papa.parse(csvData, {
                header: true,
                skipEmptyLines: true,
                dynamicTyping: true
              });

              if (parseResult.errors.length > 0) {
                return res.status(400).json({ 
                  error: 'CSV Parse Error', 
                  details: parseResult.errors 
                });
              }

              // Get schema info
              const fieldsService = new FieldsService({
                schema: await getSchema(),
                accountability: req.accountability
              });

              const fields = await fieldsService.readAll(collection);
              const requiredFields = fields.filter(f => 
                !f.schema?.nullable && 
                !f.schema?.has_auto_increment &&
                !f.schema?.is_generated
              ).map(f => f.field);

              // Apply mapping to first few rows
              const sampleData = parseResult.data.slice(0, 5).map(row => {
                const mappedRow = {};
                Object.entries(mapping).forEach(([csvCol, dbCol]) => {
                  if (dbCol && dbCol !== '-- skip --') {
                    mappedRow[dbCol] = row[csvCol];
                  }
                });
                return mappedRow;
              });

              // Check for missing required fields
              const mappedFields = Object.values(mapping).filter(f => f && f !== '-- skip --');
              const missingRequired = requiredFields.filter(f => !mappedFields.includes(f));

              res.json({
                success: true,
                totalRows: parseResult.data.length,
                sampleData,
                csvColumns: parseResult.meta.fields,
                missingRequired,
                validation: missingRequired.length === 0 ? 'passed' : 'failed'
              });
            });
          }
        });

        req.pipe(busboy);

      } catch (error) {
        logger.error('Validation error:', error);
        res.status(500).json({ error: error.message });
      }
    });

    // Execute bulk CSV import using COPY
    router.post('/import/:collection', async (req, res) => {
      try {
        const collection = req.params.collection;
        
        // Check permissions first
        const itemsService = new ItemsService(collection, {
          schema: await getSchema(),
          accountability: req.accountability
        });

        const busboy = Busboy({ headers: req.headers });
        let csvData = '';
        let mapping = {};
        let additionalValues = {};

        busboy.on('field', (fieldname, val) => {
          if (fieldname === 'mapping') {
            mapping = JSON.parse(val);
          } else if (fieldname === 'additionalValues') {
            additionalValues = JSON.parse(val);
          }
        });

        busboy.on('file', async (fieldname, file, info) => {
          if (fieldname === 'csv') {
            const chunks = [];
            file.on('data', (chunk) => chunks.push(chunk));
            file.on('end', async () => {
              const trx = await database.transaction();
              
              try {
                csvData = Buffer.concat(chunks).toString();
                
                // Parse CSV
                const parseResult = Papa.parse(csvData, {
                  header: true,
                  skipEmptyLines: true,
                  dynamicTyping: false // Keep as strings for COPY
                });

                if (parseResult.errors.length > 0) {
                  await trx.rollback();
                  return res.status(400).json({ 
                    error: 'CSV Parse Error', 
                    details: parseResult.errors 
                  });
                }

                // Apply mapping and additional values
                const mappedData = parseResult.data.map(row => {
                  const mappedRow = { ...additionalValues };
                  Object.entries(mapping).forEach(([csvCol, dbCol]) => {
                    if (dbCol && dbCol !== '-- skip --') {
                      mappedRow[dbCol] = row[csvCol] || null;
                    }
                  });
                  return mappedRow;
                });

                // Create CSV string for COPY
                const columnOrder = Object.keys(mappedData[0]);
                const csvRows = mappedData.map(row => 
                  columnOrder.map(col => {
                    const val = row[col];
                    if (val === null || val === undefined) return '';
                    // Escape quotes and wrap in quotes if contains comma/newline/quote
                    const str = String(val);
                    if (str.includes(',') || str.includes('\n') || str.includes('"')) {
                      return `"${str.replace(/"/g, '""')}"`;
                    }
                    return str;
                  }).join(',')
                );

                const csvForCopy = csvRows.join('\n');

                // Use COPY helper for bulk insert
const copyResult = await executeCopyFromCSV(
  database, // Pass database instead of trx for the helper
  collection,
  columnOrder,
  mappedData,
  trx // Pass transaction as parameter
);

if (!copyResult.success) {
  await trx.rollback();
  return res.status(500).json({ error: copyResult.error });
}

await trx.commit();

res.json({
  success: true,
  imported: copyResult.rowCount,
  collection
});

              } catch (error) {
                await trx.rollback();
                logger.error('Import error:', error);
                res.status(500).json({ error: error.message });
              }
            });
          }
        });

        busboy.on('error', (error) => {
          logger.error('Busboy error:', error);
          res.status(500).json({ error: error.message });
        });

        req.pipe(busboy);

      } catch (error) {
        logger.error('Import endpoint error:', error);
        res.status(500).json({ error: error.message });
      }
    });
  }
});