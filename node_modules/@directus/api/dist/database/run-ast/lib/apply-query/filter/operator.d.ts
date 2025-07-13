import type { SchemaOverview } from '@directus/types';
import type { Knex } from 'knex';
export declare function applyOperator(knex: Knex, dbQuery: Knex.QueryBuilder, schema: SchemaOverview, key: string, operator: string, compareValue: any, logical?: 'and' | 'or', originalCollectionName?: string): void;
