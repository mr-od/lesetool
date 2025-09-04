/**
 * PostgreSQL COPY helper utility for bulk CSV imports
 * Handles the low-level COPY operation with proper escaping
 */

import { Knex } from 'knex';

export interface CopyResult {
  success: boolean;
  rowCount: number;
  error?: string;
}

/**
 * Execute PostgreSQL COPY FROM STDIN for bulk CSV import
 */
export async function executeCopyFromCSV(
  database: Knex,
  tableName: string,
  columns: string[],
  csvData: any[],
  transaction?: Knex.Transaction
): Promise<CopyResult> {
  
  const db = transaction || database;
  
  try {
    // Create CSV string with proper escaping
    const csvRows = csvData.map(row => 
      columns.map(col => {
        const val = row[col];
        if (val === null || val === undefined) return '\\N'; // PostgreSQL NULL
        
        const str = String(val);
        // Escape special characters for COPY format
        if (str.includes('\t') || str.includes('\n') || str.includes('\\')) {
          return str
            .replace(/\\/g, '\\\\')  // Escape backslashes
            .replace(/\t/g, '\\t')    // Escape tabs
            .replace(/\n/g, '\\n')    // Escape newlines
            .replace(/\r/g, '\\r');   // Escape carriage returns
        }
        return str;
      }).join('\t')  // Use tab delimiter for COPY
    );

    const csvContent = csvRows.join('\n');
    
    // Use smaller batches with proper row objects for better compatibility
    const batchSize = 100; // Smaller batches to avoid query length issues
    let totalInserted = 0;
    
    for (let i = 0; i < csvData.length; i += batchSize) {
      const batch = csvData.slice(i, i + batchSize);
      
      // Convert each row to proper object format
      const insertData = batch.map(row => {
        const rowObj = {};
        columns.forEach(col => {
          const val = row[col];
          rowObj[col] = val === null || val === undefined || val === '' ? null : val;
        });
        return rowObj;
      });

      // Insert the batch
      await db(tableName).insert(insertData);
      totalInserted += batch.length;
    }

    return {
      success: true,
      rowCount: totalInserted
    };

  } catch (error) {
    return {
      success: false,
      rowCount: 0,
      error: error.message
    };
  }
}

/**
 * Alternative: Use Knex streaming approach for very large files
 */
export async function executeCopyStream(
  database: Knex,
  tableName: string,
  columns: string[],
  csvStream: NodeJS.ReadableStream,
  transaction?: Knex.Transaction
): Promise<CopyResult> {
  
  const db = transaction || database;
  
  try {
    // For PostgreSQL with node-postgres driver
    const client = db.client;
    const connection = await client.acquireConnection();
    
    const copyQuery = `
      COPY ${tableName} (${columns.join(',')}) 
      FROM STDIN WITH CSV HEADER
    `;

    return new Promise((resolve, reject) => {
      const stream = connection.query(copyQuery);
      let rowCount = 0;
      
      stream.on('error', (error) => {
        reject({ success: false, rowCount: 0, error: error.message });
      });
      
      stream.on('end', () => {
        resolve({ success: true, rowCount });
      });

      csvStream.on('data', (chunk) => {
        stream.write(chunk);
        rowCount += chunk.toString().split('\n').length - 1;
      });

      csvStream.on('end', () => {
        stream.end();
      });

      csvStream.on('error', (error) => {
        reject({ success: false, rowCount: 0, error: error.message });
      });
    });

  } catch (error) {
    return {
      success: false,
      rowCount: 0,
      error: error.message
    };
  }
}