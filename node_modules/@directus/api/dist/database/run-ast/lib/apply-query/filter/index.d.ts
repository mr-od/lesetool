import type { Filter, Permission, SchemaOverview } from '@directus/types';
import type { Knex } from 'knex';
import type { AliasMap } from '../../../../../utils/get-column-path.js';
export declare function applyFilter(knex: Knex, schema: SchemaOverview, rootQuery: Knex.QueryBuilder, rootFilter: Filter, collection: string, aliasMap: AliasMap, cases: Filter[], permissions: Permission[]): {
    query: Knex.QueryBuilder<any, any>;
    hasJoins: boolean;
    hasMultiRelationalFilter: boolean;
};
