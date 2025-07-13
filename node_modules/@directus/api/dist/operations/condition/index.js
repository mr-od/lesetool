import { defineOperationApi } from '@directus/extensions';
import { parseFilter, validatePayload } from '@directus/utils';
import { FailedValidationError, joiValidationErrorItemToErrorExtensions } from '@directus/validation';
export default defineOperationApi({
    id: 'condition',
    handler: ({ filter }, { data, accountability }) => {
        const parsedFilter = parseFilter(filter, accountability, undefined, true);
        if (!parsedFilter) {
            return null;
        }
        const errors = validatePayload(parsedFilter, data, { requireAll: true });
        if (errors.length > 0) {
            const validationErrors = errors
                .map((error) => error.details.map((details) => new FailedValidationError(joiValidationErrorItemToErrorExtensions(details))))
                .flat();
            throw validationErrors;
        }
        else {
            return null;
        }
    },
});
