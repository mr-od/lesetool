export function joinFilterWithCases(filter, cases) {
    if (cases.length > 0 && !filter) {
        return { _or: cases };
    }
    else if (filter && cases.length === 0) {
        return filter ?? null;
    }
    else if (filter && cases.length > 0) {
        return { _and: [filter, { _or: cases }] };
    }
    return null;
}
