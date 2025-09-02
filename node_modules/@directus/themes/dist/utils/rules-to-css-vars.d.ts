import { DeepPartial, Theme } from '@directus/types';
export declare const rulesToCssVars: (rules: DeepPartial<Theme["rules"]>) => Record<string, string | number>;
