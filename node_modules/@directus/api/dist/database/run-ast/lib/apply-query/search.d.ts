import type { Permission, SchemaOverview } from '@directus/types';
import type { Knex } from 'knex';
import type { AliasMap } from '../../../../utils/get-column-path.js';
export declare function applySearch(knex: Knex, schema: SchemaOverview, dbQuery: Knex.QueryBuilder, searchQuery: string, collection: string, aliasMap: AliasMap, permissions: Permission[]): void;
