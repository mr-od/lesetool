import { Relation, DeepPartial, SchemaOverview, FieldOverview, CollectionOverview } from '@directus/types';

type InitialRelationOverview = Pick<Relation, 'collection' | 'field'> & {
    _kind: 'initial';
};
type FinalRelationOverview = Relation & {
    _kind: 'finished';
    _type: 'o2m' | 'm2o' | 'a2o';
};
type RelationOveriewBuilderOptions = DeepPartial<{
    meta: Pick<NonNullable<Relation['meta']>, 'id' | 'junction_field' | 'sort_field'>;
    schema: Pick<NonNullable<Relation['schema']>, 'constraint_name' | 'foreign_key_schema'>;
}>;
declare class RelationBuilder {
    _schemaBuilder: SchemaBuilder | undefined;
    _data: InitialRelationOverview | FinalRelationOverview;
    constructor(collection: string, field: string, schema?: SchemaBuilder);
    o2m(related_collection: string, related_field: string): this;
    m2o(related_collection: string, related_field?: string): this;
    a2o(related_collections: string[]): this;
    options(options: RelationOveriewBuilderOptions): this;
    build(schema: SchemaOverview): Relation;
}

type InitialFieldOverview = {
    field: string;
    _kind: 'initial';
};
type FinishedFieldOverview = FieldOverview & {
    _kind: 'finished';
};
type M2AOptions = {
    o2m_relation: RelationBuilder;
    a2o_relation: RelationBuilder;
};
type M2MOptions = {
    o2m_relation: RelationBuilder;
    m2o_relation: RelationBuilder;
};
type FieldOveriewBuilderOptions = Partial<Omit<FieldOverview, 'field' | 'type' | 'dbType'>>;
declare class FieldBuilder {
    _schema: SchemaBuilder | undefined;
    _collection: CollectionBuilder | undefined;
    _data: InitialFieldOverview | FinishedFieldOverview;
    constructor(name: string, schema?: SchemaBuilder, collection?: CollectionBuilder);
    /** Shorthand for creating an integer field and marking it as the primary field */
    id(): this;
    options(options: FieldOveriewBuilderOptions): this;
    /** Resets the field to it's initial state of only the name */
    overwrite(): this;
    /** Marks the field as the primary field of the collection */
    primary(): this;
    /** Marks the field as the sort_field of the collection */
    sort(): void;
    boolean(): this;
    bigInteger(): this;
    date(): this;
    dateTime(): this;
    decimal(): this;
    float(): this;
    integer(): this;
    json(): this;
    string(): this;
    text(): this;
    time(): this;
    timestamp(): this;
    uuid(): this;
    hash(): this;
    csv(): this;
    m2a(related_collections: string[], relation_callback?: (options: M2AOptions) => M2AOptions | void): this;
    m2m(related_collection: string, relation_callback?: (options: M2MOptions) => M2MOptions | void): this;
    translations(language_collection?: string, relation_callback?: (options: M2MOptions) => M2MOptions | void): this;
    o2m(related_collection: string, related_field: string, relation_callback?: (relation: RelationBuilder) => RelationBuilder | void): this;
    m2o(related_collection: string, related_field?: string, relation_callback?: (relation: RelationBuilder) => RelationBuilder | void): this;
    a2o(related_collections: string[], relation_callback?: (relation: RelationBuilder) => RelationBuilder | void): this;
    get_name(): string;
    build(_schema: SchemaOverview): FieldOverview;
}

type InitialCollectionOverview = Omit<CollectionOverview, 'primary' | 'fields'>;
type FinalCollectionOverview = Omit<CollectionOverview, 'fields'>;
type CollectionOveriewBuilderOptions = Partial<Pick<CollectionOverview, 'singleton' | 'accountability' | 'note'>>;
declare class CollectionBuilder {
    _schemaBuilder: SchemaBuilder | undefined;
    _data: InitialCollectionOverview | FinalCollectionOverview;
    _fields: FieldBuilder[];
    constructor(name: string, schema?: SchemaBuilder);
    field(name: string): FieldBuilder;
    get_name(): string;
    build(schema: SchemaOverview): CollectionOverview;
}

declare class SchemaBuilder {
    _collections: CollectionBuilder[];
    _relations: RelationBuilder[];
    _last_collection_configured: boolean;
    _relation_counter: number;
    collection(name: string, callback: (collection: CollectionBuilder) => void): this;
    options(options: CollectionOveriewBuilderOptions): void;
    next_relation_index(): number;
    build(): SchemaOverview;
}

export { CollectionBuilder, FieldBuilder, RelationBuilder, SchemaBuilder };
