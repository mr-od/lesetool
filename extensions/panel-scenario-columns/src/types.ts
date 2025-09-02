// src/types.ts - Type definitions for the panel

export interface PanelProps {
  showHeader?: boolean;
  collection?: string;
  queryType?: QueryType;
  customQuery?: string;
  showResults?: boolean;
  resultLimit?: number;
  allowCreateTable?: boolean;
  tablePrefix?: string;
}

export type QueryType = 
  | 'count_non_null' 
  | 'count_distinct' 
  | 'sample_values' 
  | 'statistics' 
  | 'check_nulls' 
  | 'custom';

export interface ColumnInfo {
  field: string;
  type: string;
  nullable: boolean;
  primary_key: boolean;
  unique: boolean;
  default_value?: any;
  max_length?: number;
  meta?: any;
}

export interface QueryResult {
  column: string;
  query: string;
  timestamp?: string;
  type?: ResultType;
  data?: any;
  headers?: string[];
  label?: string;
  error?: string;
  message?: string;
}

export type ResultType = 'single' | 'table' | 'statistics' | 'error';

export interface StatisticsData {
  total_rows: number;
  non_null_count: number;
  distinct_count: number;
  null_count: number;
  min_value?: any;
  max_value?: any;
  null_percentage?: string;
  fill_rate?: string;
  uniqueness?: string;
}

export interface SqlExecutionRequest {
  query: string;
  parameters?: {
    limit?: number;
  };
}

export interface SqlExecutionResponse {
  success: boolean;
  data?: any[];
  rowCount?: number;
  query?: string;
  error?: string;
  message?: string;
}

export interface TableSchemaResponse {
  collection: string;
  fields: ColumnInfo[];
  primary_key?: string;
  comment?: string;
}

export interface CreateTableRequest {
  tableName: string;
  sourceQuery: string;
  tablePrefix?: string;
}

export interface CreateTableResponse {
  success: boolean;
  tableName?: string;
  rowCount?: number;
  message?: string;
  error?: string;
}