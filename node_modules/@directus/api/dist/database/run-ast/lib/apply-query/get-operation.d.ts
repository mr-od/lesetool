/**
 * Returns null or the operation information form a FieldFilter
 */
export declare function getOperation(key: string, value: unknown): {
    operator: string;
    value: unknown;
} | null;
