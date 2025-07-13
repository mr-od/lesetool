export function contextHasDynamicVariables(context) {
    return Object.values(context).some((v) => v.size > 0);
}
