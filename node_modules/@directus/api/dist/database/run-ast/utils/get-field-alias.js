import { applyFunctionToColumnName } from './apply-function-to-column-name.js';
export function getNodeAlias(node) {
    return applyFunctionToColumnName(node.fieldKey);
}
