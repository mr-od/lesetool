import type { Aggregate, SchemaOverview } from '@directus/types';
import type { Knex } from 'knex';
export declare function applyAggregate(schema: SchemaOverview, dbQuery: Knex.QueryBuilder, aggregate: Aggregate, collection: string, hasJoins: boolean): void;
