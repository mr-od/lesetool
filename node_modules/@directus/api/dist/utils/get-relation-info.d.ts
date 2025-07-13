import type { Relation } from '@directus/types';
type RelationInfo = {
    relation: Relation | null;
    relationType: 'o2m' | 'm2o' | 'a2o' | 'o2a' | null;
};
export declare function getRelationInfo(relations: Relation[], collection: string, field: string): RelationInfo;
export {};
