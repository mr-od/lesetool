import type { Permission } from '@directus/types';
export interface DynamicVariableContext {
    $CURRENT_USER: Set<string>;
    $CURRENT_ROLE: Set<string>;
    $CURRENT_ROLES: Set<string>;
    $CURRENT_POLICIES: Set<string>;
}
export declare function extractRequiredDynamicVariableContextForPermissions(permissions: Permission[]): DynamicVariableContext;
export declare function extractRequiredDynamicVariableContext(val: any): DynamicVariableContext;
