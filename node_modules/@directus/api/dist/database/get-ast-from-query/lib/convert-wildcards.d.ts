import type { Accountability, Query, Relation, SchemaOverview } from '@directus/types';
import type { Knex } from 'knex';
export interface ConvertWildcardsOptions {
    collection: string;
    fields: string[];
    alias: Query['alias'];
    accountability: Accountability | null;
    backlink: boolean | undefined;
}
export interface ConvertWildCardsContext {
    schema: SchemaOverview;
    knex: Knex;
    parentRelation?: Relation;
}
export declare function convertWildcards(options: ConvertWildcardsOptions, context: ConvertWildCardsContext): Promise<string[]>;
