import { getHelpers } from '../../../helpers/index.js';
export function applyLimit(knex, rootQuery, limit) {
    if (typeof limit === 'number') {
        getHelpers(knex).schema.applyLimit(rootQuery, limit);
    }
}
export function applyOffset(knex, rootQuery, offset) {
    if (typeof offset === 'number') {
        getHelpers(knex).schema.applyOffset(rootQuery, offset);
    }
}
