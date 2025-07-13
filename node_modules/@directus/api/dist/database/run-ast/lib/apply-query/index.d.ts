import type { Filter, Permission, Query, SchemaOverview } from '@directus/types';
import type { Knex } from 'knex';
import type { AliasMap } from '../../../../utils/get-column-path.js';
export declare const generateAlias: (size?: number) => string;
type ApplyQueryOptions = {
    aliasMap?: AliasMap;
    isInnerQuery?: boolean;
    hasMultiRelationalSort?: boolean | undefined;
    groupWhenCases?: number[][] | undefined;
    groupColumnPositions?: number[] | undefined;
};
/**
 * Apply the Query to a given Knex query builder instance
 */
export default function applyQuery(knex: Knex, collection: string, dbQuery: Knex.QueryBuilder, query: Query, schema: SchemaOverview, cases: Filter[], permissions: Permission[], options?: ApplyQueryOptions): {
    query: Knex.QueryBuilder<any, any>;
    hasJoins: boolean;
    hasMultiRelationalFilter: boolean;
};
export {};
