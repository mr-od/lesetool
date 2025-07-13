import type { Accountability, Query, SchemaOverview } from '@directus/types';
import type { GraphQLResolveInfo, SelectionNode } from 'graphql';
/**
 * Get a Directus Query object from the parsed arguments (rawQuery) and GraphQL AST selectionSet. Converts SelectionSet into
 * Directus' `fields` query for use in the resolver. Also applies variables where appropriate.
 */
export declare function getQuery(rawQuery: Query, schema: SchemaOverview, selections: readonly SelectionNode[], variableValues: GraphQLResolveInfo['variableValues'], accountability?: Accountability | null, collection?: string): Promise<Query>;
