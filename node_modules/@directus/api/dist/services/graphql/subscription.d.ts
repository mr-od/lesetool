import type { GraphQLService } from './index.js';
import type { GraphQLResolveInfo } from 'graphql';
export declare function bindPubSub(): void;
export declare function createSubscriptionGenerator(gql: GraphQLService, event: string): (_x: unknown, _y: unknown, _z: unknown, request: GraphQLResolveInfo) => AsyncGenerator<{
    [event]: {
        key: string | number;
        data: null;
        event: "delete";
    };
} | {
    [event]: {
        key: string | number;
        data: any;
        event: "create";
    };
} | {
    [event]: {
        key: string | number;
        data: any;
        event: "update";
    };
}, void, unknown>;
