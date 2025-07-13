import { GraphQLSchema } from 'graphql';
import { LRUMap } from 'mnemonist';
export declare const cache: LRUMap<string, string | GraphQLSchema>;
