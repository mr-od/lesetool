import { deepMap } from '@directus/utils';
export function extractRequiredDynamicVariableContextForPermissions(permissions) {
    let permissionContext = {
        $CURRENT_USER: new Set(),
        $CURRENT_ROLE: new Set(),
        $CURRENT_ROLES: new Set(),
        $CURRENT_POLICIES: new Set(),
    };
    for (const permission of permissions) {
        permissionContext = mergeContexts(permissionContext, extractRequiredDynamicVariableContext(permission.permissions));
        permissionContext = mergeContexts(permissionContext, extractRequiredDynamicVariableContext(permission.validation));
        permissionContext = mergeContexts(permissionContext, extractRequiredDynamicVariableContext(permission.presets));
    }
    return permissionContext;
}
export function extractRequiredDynamicVariableContext(val) {
    const permissionContext = {
        $CURRENT_USER: new Set(),
        $CURRENT_ROLE: new Set(),
        $CURRENT_ROLES: new Set(),
        $CURRENT_POLICIES: new Set(),
    };
    deepMap(val, extractPermissionData);
    return permissionContext;
    function extractPermissionData(val) {
        for (const placeholder of [
            '$CURRENT_USER',
            '$CURRENT_ROLE',
            '$CURRENT_ROLES',
            '$CURRENT_POLICIES',
        ]) {
            if (typeof val === 'string' && val.startsWith(`${placeholder}.`)) {
                permissionContext[placeholder].add(val.replace(`${placeholder}.`, ''));
            }
        }
    }
}
function mergeContexts(context1, context2) {
    const permissionContext = {
        $CURRENT_USER: new Set([...context1.$CURRENT_USER, ...context2.$CURRENT_USER]),
        $CURRENT_ROLE: new Set([...context1.$CURRENT_ROLE, ...context2.$CURRENT_ROLE]),
        $CURRENT_ROLES: new Set([...context1.$CURRENT_ROLES, ...context2.$CURRENT_ROLES]),
        $CURRENT_POLICIES: new Set([...context1.$CURRENT_POLICIES, ...context2.$CURRENT_POLICIES]),
    };
    return permissionContext;
}
