import type { KNEX_TYPES } from '@directus/constants';
import { type Knex } from 'knex';
import type { Options, SortRecord } from '../types.js';
import { SchemaHelper } from '../types.js';
export declare class SchemaHelperCockroachDb extends SchemaHelper {
    changeToType(table: string, column: string, type: (typeof KNEX_TYPES)[number], options?: Options): Promise<void>;
    constraintName(existingName: string): string;
    getDatabaseSize(): Promise<number | null>;
    addInnerSortFieldsToGroupBy(groupByFields: (string | Knex.Raw)[], sortRecords: SortRecord[], hasRelationalSort: boolean): void;
}
