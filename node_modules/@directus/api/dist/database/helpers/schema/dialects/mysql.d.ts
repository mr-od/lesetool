import type { Knex } from 'knex';
import { SchemaHelper, type SortRecord } from '../types.js';
export declare class SchemaHelperMySQL extends SchemaHelper {
    generateIndexName(type: 'unique' | 'foreign' | 'index', collection: string, fields: string | string[]): string;
    getDatabaseSize(): Promise<number | null>;
    addInnerSortFieldsToGroupBy(groupByFields: (string | Knex.Raw)[], sortRecords: SortRecord[], hasRelationalSort: boolean): void;
}
