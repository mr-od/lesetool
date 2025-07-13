import type { SQLiteError } from './types.js';
import type { Item } from '@directus/types';
export declare function extractError(error: SQLiteError, data: Partial<Item>): SQLiteError | Error;
