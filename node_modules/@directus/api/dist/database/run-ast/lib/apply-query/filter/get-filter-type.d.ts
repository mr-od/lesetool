import type { FieldOverview } from '@directus/types';
export declare function getFilterType(fields: Record<string, FieldOverview>, key: string, collection?: string): {
    type: "string" | "boolean" | "json" | "binary" | "time" | "text" | "integer" | "float" | "alias" | "uuid" | "dateTime" | "timestamp" | "bigInteger" | "date" | "decimal" | "hash" | "csv" | "geometry" | "geometry.Point" | "geometry.LineString" | "geometry.Polygon" | "geometry.MultiPoint" | "geometry.MultiLineString" | "geometry.MultiPolygon" | "unknown";
    special?: never;
} | {
    type: "string" | "boolean" | "json" | "binary" | "time" | "text" | "integer" | "float" | "alias" | "uuid" | "dateTime" | "timestamp" | "bigInteger" | "date" | "decimal" | "hash" | "csv" | "geometry" | "geometry.Point" | "geometry.LineString" | "geometry.Polygon" | "geometry.MultiPoint" | "geometry.MultiLineString" | "geometry.MultiPolygon" | "unknown";
    special: string[];
};
