import type { Aggregate, SchemaOverview } from '@directus/types';
import type { Knex } from 'knex';
import type { AliasMap } from '../../../../utils/get-column-path.js';
export type ColumnSortRecord = {
    order: 'asc' | 'desc';
    column: string;
};
export declare function applySort(knex: Knex, schema: SchemaOverview, rootQuery: Knex.QueryBuilder, sort: string[], aggregate: Aggregate | null | undefined, collection: string, aliasMap: AliasMap, returnRecords?: boolean): {
    sortRecords: {
        order: "asc" | "desc";
        column: any;
    }[];
    hasJoins: boolean;
    hasMultiRelationalSort: boolean;
} | {
    hasJoins: boolean;
    hasMultiRelationalSort: boolean;
    sortRecords?: never;
};
