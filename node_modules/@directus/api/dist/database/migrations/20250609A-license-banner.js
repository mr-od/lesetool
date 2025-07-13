import { useEnv } from '@directus/env';
import { toBoolean } from '@directus/utils';
export async function up(knex) {
    const env = useEnv();
    const acceptedTerms = toBoolean(env['ACCEPT_TERMS']);
    await knex.schema.alterTable('directus_settings', (table) => {
        table.boolean('accepted_terms').defaultTo(acceptedTerms);
    });
}
export async function down(knex) {
    await knex.schema.alterTable('directus_settings', (table) => {
        table.dropColumn('accepted_terms');
    });
}
