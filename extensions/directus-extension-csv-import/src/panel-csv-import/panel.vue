<template>
  <div class="csv-import-panel">
    <!-- Header -->
    <div class="panel-header">
      <h2>CSV Import</h2>
      <p v-if="!activeCollection" class="notice">Please select a target collection</p>
      <p v-else class="collection-info">Importing to: <strong>{{ activeCollection }}</strong></p>
    </div>

    <!-- Table Selection -->
    <div v-if="allowTableSelection" class="table-selection">
      <h3>Select Target Table</h3>
      <v-select
        :model-value="selectedCollection"
        @update:model-value="selectedCollection = $event"
        :items="availableCollections"
        item-text="name"
        item-value="collection"
        placeholder="Choose a collection..."
      />
    </div>

    <!-- File Upload Area -->
    <div v-if="activeCollection" class="upload-section">
      <div 
        class="upload-area"
        :class="{ 'drag-over': dragOver, 'has-file': selectedFile }"
        @dragover.prevent="dragOver = true"
        @dragleave="dragOver = false"
        @drop.prevent="handleFileDrop"
        @click="$refs.fileInput.click()"
      >
        <input
          ref="fileInput"
          type="file"
          accept=".csv"
          @change="handleFileSelect"
          style="display: none"
        />
        
        <div v-if="!selectedFile" class="upload-prompt">
          <v-icon name="upload_file" class="upload-icon" />
          <p>Drop CSV file here or click to select</p>
        </div>
        
        <div v-else class="file-info">
          <v-icon name="description" />
          <span>{{ selectedFile.name }}</span>
          <v-button small secondary @click.stop="clearFile">Remove</v-button>
        </div>
      </div>
    </div>

    <!-- Schema Loading -->
    <div v-if="loadingSchema" class="loading-section">
      <v-progress-circular indeterminate />
      <p>Loading collection schema...</p>
    </div>

    <!-- Column Mapping -->
    <div v-if="csvColumns.length > 0 && schema" class="mapping-section">
      <h3>Column Mapping</h3>
      <div class="mapping-grid">
        <div class="mapping-header">
          <span>CSV Column</span>
          <span>Maps to Database Field</span>
          <span>Preview</span>
        </div>
        
        <div v-for="csvCol in csvColumns" :key="csvCol" class="mapping-row">
          <div class="csv-column">
            <strong>{{ csvCol }}</strong>
          </div>
          
          <div class="db-column">
            <v-select
              :model-value="columnMapping[csvCol]"
              @update:model-value="updateMapping(csvCol, $event)"
              :items="databaseFieldOptions"
              item-text="name"
              item-value="value"
              placeholder="-- skip --"
            />
          </div>
          
          <div class="preview-data">
            <span class="preview-value">{{ getPreviewValue(csvCol) }}</span>
          </div>
        </div>
      </div>

      <!-- Additional Values for Required Fields -->
      <div v-if="missingRequiredFields.length > 0" class="additional-values">
        <h4>Required Fields</h4>
        <p class="notice">These fields are required but not in your CSV. Set default values:</p>
        
        <div v-for="field in missingRequiredFields" :key="field.field" class="required-field">
          <label>{{ field.field }}</label>
          
          <!-- Regular input -->
          <v-input
            v-if="!field.foreign_key"
            :model-value="additionalValues[field.field]"
            @update:model-value="additionalValues[field.field] = $event"
            :placeholder="`Enter ${field.field}`"
          />
          
          <!-- Foreign key dropdown -->
          <v-select
            v-else
            :model-value="additionalValues[field.field]"
            @update:model-value="additionalValues[field.field] = $event"
            :items="field.foreign_key.items"
            :item-text="getForeignKeyDisplayField(field.foreign_key.items[0])"
            item-value="id"
            :placeholder="`Select ${field.field}`"
          />
        </div>
      </div>
    </div>

    <!-- Preview Data -->
    <div v-if="showPreview && csvData.length > 0" class="preview-section">
      <h3>Data Preview</h3>
      <div class="preview-table">
        <table>
          <thead>
            <tr>
              <th v-for="field in mappedFields" :key="field">{{ field }}</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="(row, index) in previewData" :key="index">
              <td v-for="field in mappedFields" :key="field">
                {{ row[field] || 'NULL' }}
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>

    <!-- Import Actions -->
    <div v-if="csvColumns.length > 0 && canImport" class="actions-section">
      <div class="import-stats">
        <p><strong>{{ csvData.length }}</strong> rows ready to import</p>
        <p v-if="Object.keys(columnMapping).length > 0">
          <strong>{{ mappedFieldCount }}</strong> fields mapped
        </p>
      </div>
      
      <v-button
        :loading="importing"
        :disabled="!isValidMapping"
        @click="executeImport"
        kind="primary"
        large
      >
        {{ importing ? 'Importing...' : 'Import CSV Data' }}
      </v-button>
    </div>

    <!-- Results -->
    <div v-if="importResult" class="results-section">
      <v-notice :type="importResult.success ? 'success' : 'danger'">
        <div v-if="importResult.success">
          <h4>Import Successful!</h4>
          <p>{{ importResult.imported }} rows imported to {{ activeCollection }}</p>
        </div>
        <div v-else>
          <h4>Import Failed</h4>
          <p>{{ importResult.error }}</p>
        </div>
      </v-notice>
    </div>
  </div>
</template>

<script>
import { useApi } from '@directus/extensions-sdk';
import { ref, computed, watch } from 'vue';

export default {
  props: {
    showHeader: {
      type: Boolean,
      default: false,
    },
    collection: {
      type: String,
      default: '',
    },
    allowTableSelection: {
      type: Boolean,
      default: true,
    },
    showPreview: {
      type: Boolean,
      default: true,
    },
    maxPreviewRows: {
      type: Number,
      default: 10,
    },
  },
  setup(props) {
    const api = useApi();
    
    // Reactive state
    const selectedFile = ref(null);
    const csvData = ref([]);
    const csvColumns = ref([]);
    const schema = ref(null);
    const columnMapping = ref({});
    const additionalValues = ref({});
    const loadingSchema = ref(false);
    const importing = ref(false);
    const importResult = ref(null);
    const dragOver = ref(false);
    const selectedCollection = ref('');
    const availableCollections = ref([]);

    // Computed properties
    const activeCollection = computed(() => {
      return selectedCollection.value || props.collection;
    });

    const databaseFieldOptions = computed(() => {
      if (!schema.value) return [];
      
      return [
        { name: '-- skip --', value: '' },
        ...schema.value.fields.map(f => ({
          name: `${f.field} (${f.type})${f.required ? ' *' : ''}`,
          value: f.field
        }))
      ];
    });

    const mappedFields = computed(() => {
      return Object.values(columnMapping.value).filter(f => f && f !== '-- skip --');
    });

    const mappedFieldCount = computed(() => mappedFields.value.length);

    const missingRequiredFields = computed(() => {
      if (!schema.value) return [];
      
      const mapped = new Set(mappedFields.value);
      return schema.value.fields.filter(f => 
        f.required && !f.auto && !mapped.has(f.field)
      );
    });

    const previewData = computed(() => {
      if (!csvData.value || csvData.value.length === 0) return [];
      
      return csvData.value.slice(0, props.maxPreviewRows).map(row => {
        const mappedRow = { ...additionalValues.value };
        Object.entries(columnMapping.value).forEach(([csvCol, dbCol]) => {
          if (dbCol && dbCol !== '-- skip --') {
            mappedRow[dbCol] = row[csvCol];
          }
        });
        return mappedRow;
      });
    });

    const isValidMapping = computed(() => {
      return mappedFields.value.length > 0 && 
             missingRequiredFields.value.every(f => additionalValues.value[f.field]);
    });

    const canImport = computed(() => {
      return csvData.value.length > 0 && isValidMapping.value;
    });

    // Methods
    const loadAvailableCollections = async () => {
      try {
        const response = await api.get('/collections');
        availableCollections.value = response.data.data.map(c => ({
          collection: c.collection,
          name: c.name || c.collection
        }));
      } catch (error) {
        console.error('Failed to load collections:', error);
      }
    };

    const loadCollectionSchema = async () => {
      if (!activeCollection.value) return;
      
      loadingSchema.value = true;
      try {
        const response = await api.get(`/csv-import/schema/${activeCollection.value}`);
        schema.value = response.data;
      } catch (error) {
        console.error('Failed to load schema:', error);
      } finally {
        loadingSchema.value = false;
      }
    };

    const handleFileSelect = (event) => {
      const file = event.target.files[0];
      if (file && file.type === 'text/csv') {
        processFile(file);
      }
    };

    const handleFileDrop = (event) => {
      dragOver.value = false;
      const file = event.dataTransfer.files[0];
      if (file && file.type === 'text/csv') {
        processFile(file);
      }
    };

    const processFile = (file) => {
      selectedFile.value = file;
      importResult.value = null;
      
      const reader = new FileReader();
      reader.onload = (e) => {
        const csv = e.target.result;
        const lines = csv.split('\n');
        const headers = lines[0].split(',').map(h => h.trim().replace(/"/g, ''));
        
        csvColumns.value = headers;
        
        // Parse first few rows for preview
        const rows = [];
        for (let i = 1; i < Math.min(lines.length, props.maxPreviewRows + 1); i++) {
          if (lines[i].trim()) {
            const values = lines[i].split(',').map(v => v.trim().replace(/"/g, ''));
            const row = {};
            headers.forEach((header, index) => {
              row[header] = values[index] || '';
            });
            rows.push(row);
          }
        }
        csvData.value = rows;

        // Auto-suggest mappings based on field names
        if (schema.value) {
          autoSuggestMappings();
        }
      };
      reader.readAsText(file);
    };

    const autoSuggestMappings = () => {
      const mapping = {};
      csvColumns.value.forEach(csvCol => {
        const normalizedCsvCol = csvCol.toLowerCase().replace(/[^a-z0-9]/g, '_');
        const match = schema.value.fields.find(f => 
          f.field.toLowerCase() === normalizedCsvCol ||
          f.field.toLowerCase().includes(normalizedCsvCol) ||
          normalizedCsvCol.includes(f.field.toLowerCase())
        );
        if (match) {
          mapping[csvCol] = match.field;
        }
      });
      columnMapping.value = mapping;
    };

    const updateMapping = (csvCol, dbCol) => {
      columnMapping.value = {
        ...columnMapping.value,
        [csvCol]: dbCol
      };
    };

    const getPreviewValue = (csvCol) => {
      if (csvData.value.length === 0) return '';
      return csvData.value[0][csvCol] || '';
    };

    const getForeignKeyDisplayField = (item) => {
      if (!item) return 'id';
      // Try common display fields
      return item.name || item.title || item.label || item.id;
    };

    const clearFile = () => {
      selectedFile.value = null;
      csvData.value = [];
      csvColumns.value = [];
      columnMapping.value = {};
      additionalValues.value = {};
      importResult.value = null;
    };

    const executeImport = async () => {
      importing.value = true;
      importResult.value = null;

      try {
        const formData = new FormData();
        formData.append('csv', selectedFile.value);
        formData.append('mapping', JSON.stringify(columnMapping.value));
        formData.append('additionalValues', JSON.stringify(additionalValues.value));

        const response = await api.post(
          `/csv-import/import/${activeCollection.value}`,
          formData,
          {
            headers: {
              'Content-Type': 'multipart/form-data'
            }
          }
        );

        importResult.value = response.data;
        
        if (response.data.success) {
          // Clear form on success
          setTimeout(() => {
            clearFile();
          }, 3000);
        }

      } catch (error) {
        console.error('Import failed:', error);
        importResult.value = {
          success: false,
          error: error.response?.data?.error || error.message || 'Import failed'
        };
      } finally {
        importing.value = false;
      }
    };

    // Watch for collection changes
    watch(() => props.collection, (newCollection) => {
      if (newCollection && !selectedCollection.value) {
        clearFile();
        loadCollectionSchema();
      }
    }, { immediate: true });

    // Watch for selected collection changes
    watch(selectedCollection, (newCollection) => {
      if (newCollection) {
        clearFile();
        loadCollectionSchema();
      }
    });

    // Watch for activeCollection changes
    watch(activeCollection, (newCollection) => {
      if (newCollection) {
        loadCollectionSchema();
      }
    });

    // Load available collections on mount
    if (props.allowTableSelection) {
      loadAvailableCollections();
    }

    return {
      selectedFile,
      csvData,
      csvColumns,
      schema,
      columnMapping,
      additionalValues,
      loadingSchema,
      importing,
      importResult,
      dragOver,
      selectedCollection,
      availableCollections,
      activeCollection,
      databaseFieldOptions,
      mappedFields,
      mappedFieldCount,
      missingRequiredFields,
      previewData,
      isValidMapping,
      canImport,
      handleFileSelect,
      handleFileDrop,
      processFile,
      updateMapping,
      getPreviewValue,
      getForeignKeyDisplayField,
      clearFile,
      executeImport
    };
  }
};
</script>

<style scoped>
.csv-import-panel {
  padding: 20px;
  max-width: 100%;
}

.panel-header {
  margin-bottom: 24px;
}

.panel-header h2 {
  margin: 0 0 8px 0;
  color: var(--theme--primary);
}

.notice {
  color: var(--theme--warning);
  font-style: italic;
}

.collection-info {
  color: var(--theme--foreground-subdued);
}

.table-selection {
  margin-bottom: 24px;
  padding: 16px;
  background: var(--theme--background-accent);
  border-radius: 8px;
}

.table-selection h3 {
  margin: 0 0 12px 0;
  color: var(--theme--primary);
}

.upload-section {
  margin-bottom: 24px;
}

.upload-area {
  border: 2px dashed var(--theme--border-color);
  border-radius: 8px;
  padding: 32px;
  text-align: center;
  cursor: pointer;
  transition: all 0.2s ease;
  background: var(--theme--background-subdued);
}

.upload-area:hover,
.upload-area.drag-over {
  border-color: var(--theme--primary);
  background: var(--theme--background-accent);
}

.upload-area.has-file {
  background: var(--theme--background-accent);
  border-color: var(--theme--success);
}

.upload-prompt {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 12px;
}

.upload-icon {
  font-size: 48px;
  color: var(--theme--foreground-subdued);
}

.file-info {
  display: flex;
  align-items: center;
  gap: 12px;
  justify-content: center;
}

.loading-section {
  display: flex;
  align-items: center;
  gap: 12px;
  padding: 24px;
  text-align: center;
}

.mapping-section {
  margin-bottom: 24px;
}

.mapping-section h3 {
  margin-bottom: 16px;
  color: var(--theme--primary);
}

.mapping-grid {
  border: 1px solid var(--theme--border-color);
  border-radius: 8px;
  overflow: hidden;
}

.mapping-header {
  display: grid;
  grid-template-columns: 1fr 1fr 1fr;
  background: var(--theme--background-accent);
  padding: 12px;
  font-weight: bold;
  border-bottom: 1px solid var(--theme--border-color);
}

.mapping-row {
  display: grid;
  grid-template-columns: 1fr 1fr 1fr;
  padding: 12px;
  border-bottom: 1px solid var(--theme--border-color-subdued);
  align-items: center;
}

.mapping-row:last-child {
  border-bottom: none;
}

.csv-column {
  font-family: monospace;
}

.preview-value {
  font-family: monospace;
  color: var(--theme--foreground-subdued);
  font-size: 12px;
  max-width: 150px;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.additional-values {
  margin-top: 24px;
  padding: 16px;
  background: var(--theme--background-accent);
  border-radius: 8px;
}

.additional-values h4 {
  margin: 0 0 12px 0;
  color: var(--theme--warning);
}

.required-field {
  display: grid;
  grid-template-columns: 150px 1fr;
  gap: 12px;
  align-items: center;
  margin-bottom: 12px;
}

.required-field:last-child {
  margin-bottom: 0;
}

.required-field label {
  font-weight: bold;
  color: var(--theme--foreground);
}

.preview-section {
  margin-bottom: 24px;
}

.preview-section h3 {
  margin-bottom: 16px;
  color: var(--theme--primary);
}

.preview-table {
  border: 1px solid var(--theme--border-color);
  border-radius: 8px;
  overflow: auto;
  max-height: 400px;
}

.preview-table table {
  width: 100%;
  border-collapse: collapse;
}

.preview-table th {
  background: var(--theme--background-accent);
  padding: 8px 12px;
  text-align: left;
  border-bottom: 1px solid var(--theme--border-color);
  font-weight: bold;
  position: sticky;
  top: 0;
}

.preview-table td {
  padding: 8px 12px;
  border-bottom: 1px solid var(--theme--border-color-subdued);
  font-family: monospace;
  font-size: 12px;
  max-width: 200px;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.preview-table tr:last-child td {
  border-bottom: none;
}

.actions-section {
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding: 20px;
  background: var(--theme--background-accent);
  border-radius: 8px;
  margin-bottom: 24px;
}

.import-stats p {
  margin: 0 0 4px 0;
  color: var(--theme--foreground);
}

.results-section {
  margin-top: 24px;
}

.results-section h4 {
  margin: 0 0 8px 0;
}

.results-section p {
  margin: 0;
}
</style>