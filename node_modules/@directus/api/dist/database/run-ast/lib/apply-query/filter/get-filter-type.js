import { parseFilterKey } from '../../../../../utils/parse-filter-key.js';
import { InvalidQueryError } from '@directus/errors';
import { getFunctionsForType, getOutputTypeForFunction } from '@directus/utils';
export function getFilterType(fields, key, collection = 'unknown') {
    const { fieldName, functionName } = parseFilterKey(key);
    const field = fields[fieldName];
    if (!field) {
        throw new InvalidQueryError({ reason: `Invalid filter key "${key}" on "${collection}"` });
    }
    const { type } = field;
    if (functionName) {
        const availableFunctions = getFunctionsForType(type);
        if (!availableFunctions.includes(functionName)) {
            throw new InvalidQueryError({ reason: `Invalid filter key "${key}" on "${collection}"` });
        }
        const functionType = getOutputTypeForFunction(functionName);
        return { type: functionType };
    }
    return { type, special: field.special };
}
