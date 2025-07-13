import { SchemaComposer } from 'graphql-compose';
import type { GraphQLParams } from '../../../types/index.js';
import { GraphQLService } from '../index.js';
import type { Schema } from '../schema/index.js';
export declare function resolveSystemAdmin(gql: GraphQLService, schema: Schema, schemaComposer: SchemaComposer<GraphQLParams['contextValue']>): void;
