// src/builder.ts
import { ok as assert4 } from "node:assert/strict";

// src/collection.ts
import { ok as assert3 } from "node:assert/strict";

// src/defaults.ts
var COLLECTION_DEFAULTS = {
  singleton: false,
  sortField: null,
  note: null,
  accountability: "all"
};
var FIELD_DEFAULTS = {
  defaultValue: null,
  nullable: true,
  generated: false,
  precision: null,
  scale: null,
  special: [],
  note: null,
  validation: null,
  alias: false
};
var INTEGER_FIELD = {
  ...FIELD_DEFAULTS,
  type: "integer",
  dbType: "integer"
};
var ID_FIELD = {
  ...INTEGER_FIELD,
  defaultValue: "AUTO_INCREMENT",
  nullable: false
};
var JSON_FIELD = {
  ...FIELD_DEFAULTS,
  type: "json",
  dbType: "json"
};
var DATE_FIELD = {
  ...FIELD_DEFAULTS,
  type: "date",
  dbType: "date"
};
var TIME_FIELD = {
  ...FIELD_DEFAULTS,
  type: "time",
  dbType: "time without time zone"
};
var DATE_TIME_FIELD = {
  ...FIELD_DEFAULTS,
  type: "dateTime",
  dbType: "timestamp without time zone"
};
var TIMESTAMP_FIELD = {
  ...FIELD_DEFAULTS,
  type: "timestamp",
  dbType: "timestamp with time zone"
};
var HASH_FIELD = {
  ...FIELD_DEFAULTS,
  type: "hash",
  dbType: "character varying",
  special: ["hash"]
};
var CSV_FIELD = {
  ...FIELD_DEFAULTS,
  type: "csv",
  dbType: "text",
  special: ["cast-csv"]
};
var BIG_INTEGER_FIELD = {
  ...FIELD_DEFAULTS,
  type: "bigInteger",
  dbType: "bigint"
};
var FLOAT_FIELD = {
  ...FIELD_DEFAULTS,
  type: "float",
  dbType: "real"
};
var DECIMAL_FIELD = {
  ...FIELD_DEFAULTS,
  type: "decimal",
  dbType: "numeric"
};
var STRING_FIELD = {
  ...FIELD_DEFAULTS,
  type: "string",
  dbType: "character varying"
};
var UUID_FIELD = {
  ...FIELD_DEFAULTS,
  type: "uuid",
  dbType: "uuid",
  special: ["uuid"]
};
var TEXT_FIELD = {
  ...FIELD_DEFAULTS,
  type: "text",
  dbType: "text"
};
var BOOLEAN_FIELD = {
  ...FIELD_DEFAULTS,
  type: "boolean",
  dbType: "boolean",
  special: ["cast-boolean"]
};
var RELATION_DEFAULTS = {
  meta: {
    sort_field: null,
    one_deselect_action: "nullify"
  },
  schema: {
    foreign_key_schema: "public",
    on_update: "NO ACTION",
    on_delete: "SET NULL"
  }
};

// src/field.ts
import { ok as assert2 } from "node:assert/strict";

// src/relation.ts
import { ok as assert } from "node:assert/strict";
import { merge } from "lodash-es";
var RelationBuilder = class {
  _schemaBuilder;
  _data;
  constructor(collection, field, schema) {
    this._data = {
      collection,
      field,
      _kind: "initial"
    };
    this._schemaBuilder = schema;
  }
  o2m(related_collection, related_field) {
    assert(this._data._kind === "initial", "Relation is already configured");
    merge(this._data, RELATION_DEFAULTS, {
      collection: related_collection,
      field: related_field,
      related_collection: this._data.collection,
      meta: {
        many_collection: related_collection,
        many_field: related_field,
        one_collection: this._data.collection,
        one_field: this._data.field,
        one_collection_field: null,
        one_allowed_collections: null,
        id: this._schemaBuilder?.next_relation_index() ?? 0,
        junction_field: null
      },
      schema: {
        constraint_name: `${this._data.collection}_${this._data.field}_foreign`,
        table: this._data.collection,
        column: this._data.field,
        foreign_key_table: related_collection
      },
      _kind: "finished",
      _type: "o2m"
    });
    return this;
  }
  m2o(related_collection, related_field) {
    assert(this._data._kind === "initial", "Relation is already configured");
    merge(this._data, RELATION_DEFAULTS, {
      collection: this._data.collection,
      field: this._data.field,
      related_collection,
      meta: {
        many_collection: this._data.collection,
        many_field: this._data.field,
        one_collection: related_collection,
        one_field: related_field ?? null,
        one_collection_field: null,
        one_allowed_collections: null,
        id: this._schemaBuilder?.next_relation_index() ?? 0,
        junction_field: null
      },
      schema: {
        constraint_name: `${this._data.collection}_${this._data.field}_foreign`,
        table: this._data.collection,
        column: this._data.field,
        foreign_key_table: related_collection
      },
      _kind: "finished",
      _type: "m2o"
    });
    return this;
  }
  a2o(related_collections) {
    assert(this._data._kind === "initial", "Relation is already configured");
    merge(this._data, RELATION_DEFAULTS, {
      collection: this._data.collection,
      field: this._data.field,
      related_collection: null,
      meta: {
        many_collection: this._data.collection,
        many_field: this._data.field,
        one_collection: null,
        one_field: null,
        one_collection_field: "collection",
        one_allowed_collections: related_collections,
        id: this._schemaBuilder?.next_relation_index() ?? 0,
        junction_field: null
      },
      schema: null,
      _kind: "finished",
      _type: "a2o"
    });
    return this;
  }
  options(options) {
    assert(this._data._kind === "finished", "Relation is not yet configured");
    merge(this._data, options);
    return this;
  }
  build(schema) {
    assert(this._data._kind === "finished", "Relation type is not configured");
    if (this._data._type === "m2o" || this._data._type === "o2m") {
      if (this._data.related_collection && this._data.related_collection in schema.collections === false) {
        const collection2 = new CollectionBuilder(this._data.related_collection);
        collection2.field("id").id();
        schema.collections[this._data.related_collection] = collection2.build(schema);
      }
    }
    if (this._data.collection && this._data.collection in schema.collections === false) {
      const collection2 = new CollectionBuilder(this._data.collection);
      collection2.field("id").id();
      schema.collections[this._data.collection] = collection2.build(schema);
    }
    const collection = schema.collections[this._data.collection];
    if (this._data.field && this._data.field in collection.fields === false) {
      const key_type = collection.fields[collection.primary].type;
      assert(
        key_type === "integer" || key_type === "string",
        `Cannot generate related field for primary key type ${key_type}`
      );
      const field = new FieldBuilder(this._data.field)[key_type]();
      collection.fields[this._data.field] = field.build(schema);
    }
    if (this._data._type === "a2o") {
      const collection_field = this._data.meta?.one_collection_field;
      if (collection_field && collection_field in collection.fields === false) {
        const field = new FieldBuilder(collection_field).string();
        collection.fields[collection_field] = field.build(schema);
      }
      for (const collection_name of this._data.meta?.one_allowed_collections ?? []) {
        if (collection_name in schema.collections) continue;
        const collection2 = new CollectionBuilder(collection_name);
        collection2.field("id").id();
        schema.collections[collection_name] = collection2.build(schema);
      }
    }
    const { _kind, _type, ...relation } = this._data;
    return relation;
  }
};

// src/field.ts
var FieldBuilder = class {
  _schema;
  _collection;
  _data;
  constructor(name, schema, collection) {
    this._data = {
      field: name,
      _kind: "initial"
    };
    this._schema = schema;
    this._collection = collection;
  }
  /** Shorthand for creating an integer field and marking it as the primary field */
  id() {
    this._data = {
      field: this._data.field,
      ...ID_FIELD,
      _kind: "finished"
    };
    if (this._collection) this.primary();
    return this;
  }
  options(options) {
    assert2(this._data._kind !== "initial", "Cannot configure field before specifing a type");
    Object.assign(this._data, options);
    return this;
  }
  /** Resets the field to it's initial state of only the name */
  overwrite() {
    this._data = {
      field: this._data.field,
      _kind: "initial"
    };
    return this;
  }
  /** Marks the field as the primary field of the collection */
  primary() {
    assert2(this._collection, "Can only set to primary on a collection");
    assert2(
      "primary" in this._collection._data === false,
      `The primary key is already set on the collection ${this._collection.get_name()}`
    );
    this._collection._data = {
      primary: this._data.field,
      ...this._collection._data
    };
    return this;
  }
  /** Marks the field as the sort_field of the collection */
  sort() {
    assert2(this._collection, "Can only set to sort on a collection");
    assert2(this._collection._data.sortField === null, "Can only set a sort field once");
    this._collection._data = {
      ...this._collection._data,
      sortField: this._data.field
    };
  }
  boolean() {
    assert2(this._data._kind === "initial", "Field type was already set");
    this._data = {
      field: this._data.field,
      ...BOOLEAN_FIELD,
      _kind: "finished"
    };
    return this;
  }
  bigInteger() {
    assert2(this._data._kind === "initial", "Field type was already set");
    this._data = {
      field: this._data.field,
      ...BIG_INTEGER_FIELD,
      _kind: "finished"
    };
    return this;
  }
  date() {
    assert2(this._data._kind === "initial", "Field type was already set");
    this._data = {
      field: this._data.field,
      ...DATE_FIELD,
      _kind: "finished"
    };
    return this;
  }
  dateTime() {
    assert2(this._data._kind === "initial", "Field type was already set");
    this._data = {
      field: this._data.field,
      ...DATE_TIME_FIELD,
      _kind: "finished"
    };
    return this;
  }
  decimal() {
    assert2(this._data._kind === "initial", "Field type was already set");
    this._data = {
      field: this._data.field,
      ...DECIMAL_FIELD,
      _kind: "finished"
    };
    return this;
  }
  float() {
    assert2(this._data._kind === "initial", "Field type was already set");
    this._data = {
      field: this._data.field,
      ...FLOAT_FIELD,
      _kind: "finished"
    };
    return this;
  }
  integer() {
    assert2(this._data._kind === "initial", "Field type was already set");
    this._data = {
      field: this._data.field,
      ...INTEGER_FIELD,
      _kind: "finished"
    };
    return this;
  }
  json() {
    assert2(this._data._kind === "initial", "Field type was already set");
    this._data = {
      field: this._data.field,
      ...JSON_FIELD,
      _kind: "finished"
    };
    return this;
  }
  string() {
    assert2(this._data._kind === "initial", "Field type was already set");
    this._data = {
      field: this._data.field,
      ...STRING_FIELD,
      _kind: "finished"
    };
    return this;
  }
  text() {
    assert2(this._data._kind === "initial", "Field type was already set");
    this._data = {
      field: this._data.field,
      ...TEXT_FIELD,
      _kind: "finished"
    };
    return this;
  }
  time() {
    assert2(this._data._kind === "initial", "Field type was already set");
    this._data = {
      field: this._data.field,
      ...TIME_FIELD,
      _kind: "finished"
    };
    return this;
  }
  timestamp() {
    assert2(this._data._kind === "initial", "Field type was already set");
    this._data = {
      field: this._data.field,
      ...TIMESTAMP_FIELD,
      _kind: "finished"
    };
    return this;
  }
  uuid() {
    assert2(this._data._kind === "initial", "Field type was already set");
    this._data = {
      field: this._data.field,
      ...UUID_FIELD,
      _kind: "finished"
    };
    return this;
  }
  hash() {
    assert2(this._data._kind === "initial", "Field type was already set");
    this._data = {
      field: this._data.field,
      ...HASH_FIELD,
      _kind: "finished"
    };
    return this;
  }
  csv() {
    assert2(this._data._kind === "initial", "Field type was already set");
    this._data = {
      field: this._data.field,
      ...CSV_FIELD,
      _kind: "finished"
    };
    return this;
  }
  m2a(related_collections, relation_callback) {
    assert2(this._data._kind === "initial", "Field type was already set");
    assert2(this._schema && this._collection, "Field needs to be part of a schema");
    this._data = {
      field: this._data.field,
      ...FIELD_DEFAULTS,
      type: "alias",
      dbType: null,
      special: ["m2a"],
      _kind: "finished"
    };
    const junction_name = `${this._collection.get_name()}_builder`;
    let o2m_relation = new RelationBuilder(this._collection.get_name(), this.get_name()).o2m(junction_name, `${this._collection.get_name()}_id`).options({
      meta: {
        junction_field: `item`
      }
    });
    let a2o_relation = new RelationBuilder(junction_name, "item").a2o(related_collections).options({
      meta: {
        junction_field: `${this._collection.get_name()}_id`
      }
    });
    if (relation_callback) {
      const new_relations = relation_callback({ o2m_relation, a2o_relation });
      if (new_relations) {
        o2m_relation = new_relations.o2m_relation;
        a2o_relation = new_relations.a2o_relation;
      }
    }
    this._schema._relations.push(o2m_relation);
    this._schema._relations.push(a2o_relation);
    return this;
  }
  m2m(related_collection, relation_callback) {
    assert2(this._data._kind === "initial", "Field type was already set");
    assert2(this._schema && this._collection, "Field needs to be part of a schema");
    this._data = {
      field: this._data.field,
      ...FIELD_DEFAULTS,
      type: "alias",
      dbType: null,
      special: ["m2m"],
      _kind: "finished"
    };
    const junction_name = `${this._collection.get_name()}_${related_collection}_junction`;
    let o2m_relation = new RelationBuilder(this._collection.get_name(), this.get_name()).o2m(junction_name, `${this._collection.get_name()}_id`).options({
      meta: {
        junction_field: `${related_collection}_id`
      }
    });
    let m2o_relation = new RelationBuilder(junction_name, `${related_collection}_id`).m2o(related_collection).options({
      meta: {
        junction_field: `${this._collection.get_name()}_id`
      }
    });
    if (relation_callback) {
      const new_relations = relation_callback({ o2m_relation, m2o_relation });
      if (new_relations) {
        o2m_relation = new_relations.o2m_relation;
        m2o_relation = new_relations.m2o_relation;
      }
    }
    this._schema._relations.push(o2m_relation);
    this._schema._relations.push(m2o_relation);
    return this;
  }
  translations(language_collection = "languages", relation_callback) {
    assert2(this._data._kind === "initial", "Field type was already set");
    assert2(this._schema && this._collection, "Field needs to be part of a schema");
    this._data = {
      field: this._data.field,
      ...FIELD_DEFAULTS,
      type: "alias",
      dbType: null,
      special: ["translations"],
      _kind: "finished"
    };
    this._schema.collection(language_collection, (c) => {
      c.field("code").string().primary();
      c.field("name").string();
      c.field("direction").string().options({ defaultValue: "ltr" });
    });
    const junction_name = `${this._collection.get_name()}_translations`;
    let o2m_relation = new RelationBuilder(this._collection.get_name(), this.get_name()).o2m(junction_name, `${this._collection.get_name()}_id`).options({
      meta: {
        junction_field: `${language_collection}_code`
      }
    });
    let m2o_relation = new RelationBuilder(junction_name, `${language_collection}_code`).m2o(language_collection).options({
      meta: {
        junction_field: `${this._collection.get_name()}_id`
      }
    });
    if (relation_callback) {
      const new_relations = relation_callback({ o2m_relation, m2o_relation });
      if (new_relations) {
        o2m_relation = new_relations.o2m_relation;
        m2o_relation = new_relations.m2o_relation;
      }
    }
    this._schema._relations.push(o2m_relation);
    this._schema._relations.push(m2o_relation);
    return this;
  }
  o2m(related_collection, related_field, relation_callback) {
    assert2(this._data._kind === "initial", "Field type was already set");
    assert2(this._schema && this._collection, "Field needs to be part of a schema");
    this._data = {
      field: this._data.field,
      ...FIELD_DEFAULTS,
      type: "alias",
      dbType: null,
      special: ["o2m"],
      _kind: "finished"
    };
    let relation = new RelationBuilder(this._collection.get_name(), this.get_name()).o2m(
      related_collection,
      related_field
    );
    if (relation_callback) {
      const new_relation = relation_callback(relation);
      if (new_relation) {
        relation = new_relation;
      }
    }
    this._schema._relations.push(relation);
    return this;
  }
  m2o(related_collection, related_field, relation_callback) {
    assert2(this._data._kind === "initial", "Field type was already set");
    assert2(this._schema && this._collection, "Field needs to be part of a schema");
    this._data = {
      field: this._data.field,
      ...FIELD_DEFAULTS,
      type: "integer",
      dbType: "integer",
      special: ["m2o"],
      _kind: "finished"
    };
    let relation = new RelationBuilder(this._collection.get_name(), this.get_name()).m2o(
      related_collection,
      related_field
    );
    if (relation_callback) {
      const new_relation = relation_callback(relation);
      if (new_relation) {
        relation = new_relation;
      }
    }
    this._schema._relations.push(relation);
    return this;
  }
  a2o(related_collections, relation_callback) {
    assert2(this._data._kind === "initial", "Field type was already set");
    assert2(this._schema && this._collection, "Field needs to be part of a schema");
    this._data = {
      field: this._data.field,
      ...FIELD_DEFAULTS,
      type: "integer",
      dbType: "integer",
      special: [],
      _kind: "finished"
    };
    let relation = new RelationBuilder(this._collection.get_name(), this.get_name()).a2o(related_collections);
    if (relation_callback) {
      const new_relation = relation_callback(relation);
      if (new_relation) {
        relation = new_relation;
      }
    }
    this._schema._relations.push(relation);
    return this;
  }
  get_name() {
    return this._data.field;
  }
  build(_schema) {
    assert2(this._data._kind === "finished", "The collection needs at least 1 field configured");
    const { _kind, ...field } = this._data;
    return field;
  }
};

// src/collection.ts
var CollectionBuilder = class {
  _schemaBuilder;
  _data;
  _fields = [];
  constructor(name, schema) {
    this._data = {
      collection: name,
      ...COLLECTION_DEFAULTS
    };
    this._schemaBuilder = schema;
  }
  field(name) {
    const existingField = this._fields.find((fieldBuilder) => fieldBuilder.get_name() === name);
    if (existingField) {
      return existingField;
    }
    const field = new FieldBuilder(name, this._schemaBuilder, this);
    this._fields.push(field);
    return field;
  }
  get_name() {
    return this._data.collection;
  }
  build(schema) {
    assert3("primary" in this._data, `The collection ${this.get_name()} needs a primary key`);
    const fields = {};
    for (const fieldBuilder of this._fields) {
      const field = fieldBuilder.build(schema);
      assert3(field.field in fields === false, `Field ${field.field} already exists`);
      fields[field.field] = field;
    }
    const collection = {
      ...this._data,
      fields
    };
    return collection;
  }
};

// src/builder.ts
var SchemaBuilder3 = class {
  _collections = [];
  _relations = [];
  _last_collection_configured = true;
  _relation_counter = 0;
  collection(name, callback) {
    const existing_index = this._collections.findIndex((collectionBuilder) => collectionBuilder.get_name() === name);
    if (existing_index !== -1) {
      callback(this._collections[existing_index]);
      this._last_collection_configured = false;
      return this;
    }
    const collection = new CollectionBuilder(name, this);
    callback(collection);
    this._collections.push(collection);
    this._last_collection_configured = false;
    return this;
  }
  options(options) {
    assert4(this._collections.length > 0, "You need at least 1 collection to configure it's options");
    assert4(this._last_collection_configured === false, "You can only configure a collection once");
    const lastCollection = this._collections.at(-1);
    Object.assign(lastCollection._data, options);
    this._last_collection_configured = true;
  }
  next_relation_index() {
    return this._relation_counter++;
  }
  build() {
    const schema = {
      collections: {},
      relations: []
    };
    for (const collectionBuilder of this._collections) {
      const collection = collectionBuilder.build(schema);
      assert4(
        collection.collection in schema.collections === false,
        `Collection ${collection.collection} already exists`
      );
      schema.collections[collection.collection] = collection;
    }
    for (const relationBuilder of this._relations) {
      const relation = relationBuilder.build(schema);
      schema.relations.push(relation);
    }
    return schema;
  }
};
export {
  CollectionBuilder,
  FieldBuilder,
  RelationBuilder,
  SchemaBuilder3 as SchemaBuilder
};
