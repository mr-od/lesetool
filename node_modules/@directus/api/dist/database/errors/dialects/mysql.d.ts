import type { MySQLError } from './types.js';
import type { Item } from '@directus/types';
export declare function extractError(error: MySQLError, data: Partial<Item>): MySQLError | Error;
