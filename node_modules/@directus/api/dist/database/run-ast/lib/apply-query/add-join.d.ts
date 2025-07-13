import type { SchemaOverview } from '@directus/types';
import type { Knex } from 'knex';
import type { AliasMap } from '../../../../utils/get-column-path.js';
/**
 * Apply a given filter object to the Knex QueryBuilder instance.
 *
 * Relational nested filters, like the following example:
 *
 * ```json
 * // Fetch pages that have articles written by Rijk
 *
 * {
 *   "articles": {
 *     "author": {
 *       "name": {
 *         "_eq": "Rijk"
 *       }
 *     }
 *   }
 * }
 * ```
 *
 * are handled by joining the nested tables, and using a where statement on the top level on the
 * nested field through the join. This allows us to filter the top level items based on nested data.
 * The where on the root is done with a subquery to prevent duplicates, any nested joins are done
 * with aliases to prevent naming conflicts.
 *
 * The output SQL for the above would look something like:
 *
 * ```sql
 * SELECT *
 * FROM pages
 * WHERE
 *   pages.id in (
 *     SELECT articles.page_id AS page_id
 *     FROM articles
 *     LEFT JOIN authors AS xviqp ON articles.author = xviqp.id
 *     WHERE xviqp.name = 'Rijk'
 *   )
 * ```
 */
type AddJoinProps = {
    path: string[];
    collection: string;
    aliasMap: AliasMap;
    rootQuery: Knex.QueryBuilder;
    schema: SchemaOverview;
    knex: Knex;
};
export declare function addJoin({ path, collection, aliasMap, rootQuery, schema, knex }: AddJoinProps): {
    hasMultiRelational: boolean;
    isJoinAdded: boolean;
};
export {};
