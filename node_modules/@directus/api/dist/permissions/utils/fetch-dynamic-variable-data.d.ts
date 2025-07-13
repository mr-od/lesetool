import type { Accountability } from '@directus/types';
import type { Context } from '../types.js';
import { type DynamicVariableContext } from './extract-required-dynamic-variable-context.js';
export interface FetchDynamicVariableContext {
    accountability: Pick<Accountability, 'user' | 'role' | 'roles'>;
    policies: string[];
    dynamicVariableContext: DynamicVariableContext;
}
export declare function fetchDynamicVariableData(options: FetchDynamicVariableContext, context: Context): Promise<Record<string, any>>;
