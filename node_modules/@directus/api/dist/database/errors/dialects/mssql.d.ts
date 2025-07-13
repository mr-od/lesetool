import type { MSSQLError } from './types.js';
import type { Item } from '@directus/types';
export declare function extractError(error: MSSQLError, data: Partial<Item>): Promise<MSSQLError | Error>;
