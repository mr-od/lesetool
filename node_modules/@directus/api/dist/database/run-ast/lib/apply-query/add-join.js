import { InvalidQueryError } from '@directus/errors';
import { clone } from 'lodash-es';
import { getRelationInfo } from '../../../../utils/get-relation-info.js';
import { getHelpers } from '../../../helpers/index.js';
import { generateAlias } from './index.js';
export function addJoin({ path, collection, aliasMap, rootQuery, schema, knex }) {
    let hasMultiRelational = false;
    let isJoinAdded = false;
    path = clone(path);
    followRelation(path);
    return { hasMultiRelational, isJoinAdded };
    function followRelation(pathParts, parentCollection = collection, parentFields) {
        /**
         * For A2M fields, the path can contain an optional collection scope <field>:<scope>
         */
        const pathRoot = pathParts[0].split(':')[0];
        const { relation, relationType } = getRelationInfo(schema.relations, parentCollection, pathRoot);
        if (!relation) {
            return;
        }
        const existingAlias = parentFields
            ? aliasMap[`${parentFields}.${pathParts[0]}`]?.alias
            : aliasMap[pathParts[0]]?.alias;
        if (!existingAlias) {
            const alias = generateAlias();
            const aliasKey = parentFields ? `${parentFields}.${pathParts[0]}` : pathParts[0];
            const aliasedParentCollection = aliasMap[parentFields ?? '']?.alias || parentCollection;
            aliasMap[aliasKey] = { alias, collection: '' };
            if (relationType === 'm2o') {
                rootQuery.leftJoin({ [alias]: relation.related_collection }, `${aliasedParentCollection}.${relation.field}`, `${alias}.${schema.collections[relation.related_collection].primary}`);
                aliasMap[aliasKey].collection = relation.related_collection;
                isJoinAdded = true;
            }
            else if (relationType === 'a2o') {
                const pathScope = pathParts[0].split(':')[1];
                if (!pathScope) {
                    throw new InvalidQueryError({
                        reason: `You have to provide a collection scope when sorting or filtering on a many-to-any item`,
                    });
                }
                rootQuery.leftJoin({ [alias]: pathScope }, (joinClause) => {
                    joinClause
                        .onVal(`${aliasedParentCollection}.${relation.meta.one_collection_field}`, '=', pathScope)
                        .andOn(`${aliasedParentCollection}.${relation.field}`, '=', knex.raw(getHelpers(knex).schema.castA2oPrimaryKey(), `${alias}.${schema.collections[pathScope].primary}`));
                });
                aliasMap[aliasKey].collection = pathScope;
                isJoinAdded = true;
            }
            else if (relationType === 'o2a') {
                rootQuery.leftJoin({ [alias]: relation.collection }, (joinClause) => {
                    joinClause
                        .onVal(`${alias}.${relation.meta.one_collection_field}`, '=', parentCollection)
                        .andOn(`${alias}.${relation.field}`, '=', knex.raw(getHelpers(knex).schema.castA2oPrimaryKey(), `${aliasedParentCollection}.${schema.collections[parentCollection].primary}`));
                });
                aliasMap[aliasKey].collection = relation.collection;
                hasMultiRelational = true;
                isJoinAdded = true;
            }
            else if (relationType === 'o2m') {
                rootQuery.leftJoin({ [alias]: relation.collection }, `${aliasedParentCollection}.${schema.collections[relation.related_collection].primary}`, `${alias}.${relation.field}`);
                aliasMap[aliasKey].collection = relation.collection;
                hasMultiRelational = true;
                isJoinAdded = true;
            }
        }
        let parent;
        if (relationType === 'm2o') {
            parent = relation.related_collection;
        }
        else if (relationType === 'a2o') {
            const pathScope = pathParts[0].split(':')[1];
            if (!pathScope) {
                throw new InvalidQueryError({
                    reason: `You have to provide a collection scope when sorting or filtering on a many-to-any item`,
                });
            }
            parent = pathScope;
        }
        else {
            parent = relation.collection;
        }
        if (pathParts.length > 1) {
            followRelation(pathParts.slice(1), parent, `${parentFields ? parentFields + '.' : ''}${pathParts[0]}`);
        }
    }
}
