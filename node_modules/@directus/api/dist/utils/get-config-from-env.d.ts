export interface GetConfigFromEnvOptions {
    omitPrefix?: string | string[];
    omitKey?: string | string[];
    type?: 'camelcase' | 'underscore';
}
export declare function getConfigFromEnv(prefix: string, options?: GetConfigFromEnvOptions): Record<string, any>;
