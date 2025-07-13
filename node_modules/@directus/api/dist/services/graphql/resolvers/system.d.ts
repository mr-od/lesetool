import { SchemaComposer } from 'graphql-compose';
import type { GraphQLParams } from '../../../types/index.js';
import { GraphQLService } from '../index.js';
import { type CollectionTypes, type Schema } from '../schema/index.js';
export declare function injectSystemResolvers(gql: GraphQLService, schemaComposer: SchemaComposer<GraphQLParams['contextValue']>, { CreateCollectionTypes, ReadCollectionTypes, UpdateCollectionTypes }: CollectionTypes, schema: Schema): SchemaComposer<any>;
