import type { SchemaComposer } from 'graphql-compose';
import type { Schema } from '../schema/index.js';
export declare function getRelationType(schemaComposer: SchemaComposer, schema: Schema, action: 'read' | 'write'): import("graphql-compose").ObjectTypeComposer<any, any>;
