import type { Accountability, Query, SchemaOverview } from '@directus/types';
/**
 * Sanitize the query parameters and parse them where necessary.
 */
export declare function sanitizeQuery(rawQuery: Record<string, any>, schema: SchemaOverview, accountability?: Accountability | null): Promise<Query>;
