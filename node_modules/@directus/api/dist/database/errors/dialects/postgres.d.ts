import type { PostgresError } from './types.js';
import type { Item } from '@directus/types';
export declare function extractError(error: PostgresError, data: Partial<Item>): PostgresError | Error;
