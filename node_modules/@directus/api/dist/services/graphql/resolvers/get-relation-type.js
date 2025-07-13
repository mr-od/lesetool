import { GraphQLNonNull, GraphQLString } from 'graphql';
import { getGraphQLType } from '../../../utils/get-graphql-type.js';
export function getRelationType(schemaComposer, schema, action) {
    const prefix = action === 'read' ? '' : 'write_';
    const Relation = schemaComposer.createObjectTC({
        name: `${prefix}directus_relations`,
    });
    if ('directus_relations' in schema.read.collections === false) {
        return Relation;
    }
    Relation.addFields({
        collection: GraphQLString,
        field: GraphQLString,
        related_collection: GraphQLString,
        schema: schemaComposer.createObjectTC({
            name: `${prefix}directus_relations_schema`,
            fields: {
                table: new GraphQLNonNull(GraphQLString),
                column: new GraphQLNonNull(GraphQLString),
                foreign_key_table: new GraphQLNonNull(GraphQLString),
                foreign_key_column: new GraphQLNonNull(GraphQLString),
                constraint_name: GraphQLString,
                on_update: new GraphQLNonNull(GraphQLString),
                on_delete: new GraphQLNonNull(GraphQLString),
            },
        }),
        meta: schemaComposer.createObjectTC({
            name: `${prefix}directus_relations_meta`,
            fields: Object.values(schema.read.collections['directus_relations'].fields).reduce((acc, field) => {
                acc[field.field] = {
                    type: getGraphQLType(field.type, field.special),
                    description: field.note,
                };
                return acc;
            }, {}),
        }),
    });
    return Relation;
}
