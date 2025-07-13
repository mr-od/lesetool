export function applyAggregate(schema, dbQuery, aggregate, collection, hasJoins) {
    for (const [operation, fields] of Object.entries(aggregate)) {
        if (!fields)
            continue;
        for (const field of fields) {
            if (operation === 'countAll') {
                dbQuery.count('*', { as: 'countAll' });
                continue;
            }
            if (operation === 'count' && field === '*') {
                dbQuery.count('*', { as: 'count' });
                continue;
            }
            if (operation === 'countDistinct' && !hasJoins && schema.collections[collection]?.primary === field) {
                // Optimize to count as primary keys are unique
                dbQuery.count(`${collection}.${field}`, { as: `countDistinct->${field}` });
                continue;
            }
            if (['count', 'countDistinct', 'avg', 'avgDistinct', 'sum', 'sumDistinct', 'min', 'max'].includes(operation)) {
                dbQuery[operation](`${collection}.${field}`, { as: `${operation}->${field}` });
            }
        }
    }
}
