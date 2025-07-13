import type { Knex } from 'knex';
export declare function applyLimit(knex: Knex, rootQuery: Knex.QueryBuilder, limit: any): void;
export declare function applyOffset(knex: Knex, rootQuery: Knex.QueryBuilder, offset: any): void;
