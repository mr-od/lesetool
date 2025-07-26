<!-- <script setup lang="ts">
import { ref, watchEffect } from 'vue';
import { useApi } from '@directus/extensions-sdk';
import draggable from 'vuedraggable';

const props = defineProps<{
  sql_query?: string;
}>();

const api = useApi();
const rows = ref<any[]>([]);
const columns = ref<string[]>([]);
const error = ref<string | null>(null);
const loading = ref(false);

const currentPage = ref(1);
const pageSize = ref(10);

async function fetchPage() {
  if (!props.sql_query) {
    error.value = 'No SQL query provided.';
    return;
  }

  try {
    loading.value = true;
    const offset = (currentPage.value - 1) * pageSize.value;

    const res = await api.post('/endpoint-sql-view', {
      query: props.sql_query,
      limit: pageSize.value,
      offset: offset,
    });

    rows.value = res.data;
    columns.value = rows.value.length > 0 ? Object.keys(rows.value[0]) : [];
  } catch (err: any) {
    error.value = 'Failed to load SQL data.';
    console.error(err);
  } finally {
    loading.value = false;
  }
}

watchEffect(() => {
  fetchPage();
});
</script>

<template>
  <div class="panel-container">
    <div v-if="error" class="error-message">{{ error }}</div>
    <div v-else-if="loading">Loading...</div>
    <div v-else>
      <table v-if="rows.length > 0" class="data-table">
        <thead>
          <tr>
            <th v-for="col in columns" :key="col">{{ col }}</th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="(row, i) in rows" :key="i">
            <td v-for="col in columns" :key="col">{{ row[col] }}</td>
          </tr>
        </tbody>
      </table>
      <p v-else>No results found.</p>

      <div class="pagination">
        <button @click="currentPage--" :disabled="currentPage === 1">Previous</button>
        <span>Page {{ currentPage }}</span>
        <button @click="currentPage++" :disabled="rows.length < pageSize">Next</button>
      </div>
    </div>
  </div>
</template>

<style scoped>
.panel-container {
  padding: 1rem;
}
.data-table {
  width: 100%;
  border-collapse: collapse;
}
.data-table th,
.data-table td {
  border: 1px solid #ccc;
  padding: 0.5rem;
}
.pagination {
  margin-top: 1rem;
  display: flex;
  justify-content: center;
  gap: 1rem;
}
</style> -->

////////////v2///////////////////////////////////
<!-- <script setup lang="ts">
import { ref, watchEffect } from 'vue';
import { useApi } from '@directus/extensions-sdk';

const props = defineProps<{
  sql_query?: string;
  column_order?: string;
}>();

const api = useApi();
const rows = ref<any[]>([]);
const columns = ref<string[]>([]);
const error = ref<string | null>(null);
const loading = ref(false);

const currentPage = ref(1);
const pageSize = ref(10);

async function fetchPage() {
  if (!props.sql_query) {
    error.value = 'No SQL query provided.';
    return;
  }

  try {
    loading.value = true;
    const offset = (currentPage.value - 1) * pageSize.value;

    const res = await api.post('/endpoint-sql-view', {
      query: props.sql_query,
      limit: pageSize.value,
      offset,
    });

    const data = res.data;
    rows.value = data;

    const availableColumns = data.length > 0 ? Object.keys(data[0]) : [];

    if (props.column_order) {
      const preferred = props.column_order.split(',').map(col => col.trim());
      columns.value = preferred.filter(col => availableColumns.includes(col));
    } else {
      columns.value = availableColumns;
    }

  } catch (err: any) {
    error.value = 'Failed to load SQL data.';
    console.error(err);
  } finally {
    loading.value = false;
  }
}

watchEffect(() => {
  fetchPage();
});
</script>

<template>
  <div class="panel-container">
    <div v-if="error" class="error-message">{{ error }}</div>
    <div v-else-if="loading">Loading...</div>
    <div v-else>
      <table v-if="rows.length > 0" class="data-table">
        <thead>
          <tr>
            <th v-for="col in columns" :key="col">{{ col }}</th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="(row, i) in rows" :key="i">
            <td v-for="col in columns" :key="col">{{ row[col] }}</td>
          </tr>
        </tbody>
      </table>
      <p v-else>No results found.</p>

      <div class="pagination">
        <button @click="currentPage--" :disabled="currentPage === 1">Previous</button>
        <span>Page {{ currentPage }}</span>
        <button @click="currentPage++" :disabled="rows.length < pageSize">Next</button>
      </div>
    </div>
  </div>
</template>

<style scoped>
.panel-container {
  padding: 1rem;
}
.data-table {
  width: 100%;
  border-collapse: collapse;
}
.data-table th,
.data-table td {
  border: 1px solid #ccc;
  padding: 0.5rem;
}
.pagination {
  margin-top: 1rem;
  display: flex;
  justify-content: center;
  gap: 1rem;
}
</style> -->

//////////////////////V3///////////////////
<!-- <script setup lang="ts">
import { ref, watchEffect, computed } from 'vue';
import { useApi } from '@directus/extensions-sdk';

const props = defineProps<{
  sql_query?: string;
  column_order?: string;
}>();

const api = useApi();
const rows = ref<any[]>([]);
const columns = ref<string[]>([]);
const totalRows = ref(0);
const error = ref<string | null>(null);
const loading = ref(false);

const currentPage = ref(1);
const pageSize = ref(10);

const totalPages = computed(() => Math.ceil(totalRows.value / pageSize.value));
const isLastPage = computed(() => currentPage.value >= totalPages.value);

async function fetchPage() {
  if (!props.sql_query) {
    error.value = 'No SQL query provided.';
    return;
  }

  try {
    loading.value = true;
    const offset = (currentPage.value - 1) * pageSize.value;

    const res = await api.post('/endpoint-sql-view', {
      query: props.sql_query,
      limit: pageSize.value,
      offset,
    });

    rows.value = res.data.rows;
    totalRows.value = res.data.total;

    const availableColumns = rows.value.length > 0 ? Object.keys(rows.value[0]) : [];

    if (props.column_order) {
      const preferred = props.column_order.split(',').map(col => col.trim());
      columns.value = preferred.filter(col => availableColumns.includes(col));
    } else {
      columns.value = availableColumns;
    }
  } catch (err: any) {
    error.value = 'Failed to load SQL data.';
    console.error(err);
  } finally {
    loading.value = false;
  }
}

watchEffect(() => {
  fetchPage();
});
</script>

<template>
  <div class="panel-container">
    <div v-if="error" class="error-message">{{ error }}</div>
    <div v-else-if="loading">Loading...</div>
    <div v-else>
      <table v-if="rows.length > 0" class="data-table">
        <thead>
          <tr>
            <th v-for="col in columns" :key="col">{{ col }}</th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="(row, i) in rows" :key="i">
            <td v-for="col in columns" :key="col">{{ row[col] }}</td>
          </tr>
        </tbody>
      </table>
      <p v-else>No results found.</p>

      <div class="pagination">
        <button @click="currentPage--" :disabled="currentPage === 1">Previous</button>

        <span>Page {{ currentPage }} of {{ totalPages }}</span>

        <button @click="currentPage++" :disabled="isLastPage">Next</button>

        <select v-model.number="currentPage">
          <option v-for="n in totalPages" :key="n" :value="n">Go to page {{ n }}</option>
        </select>
      </div>
    </div>
  </div>
</template>

<style scoped>
.panel-container {
  padding: 1rem;
}
.data-table {
  width: 100%;
  border-collapse: collapse;
}
.data-table th,
.data-table td {
  border: 1px solid #ccc;
  padding: 0.5rem;
}
.pagination {
  margin-top: 1rem;
  display: flex;
  align-items: center;
  gap: 1rem;
  flex-wrap: wrap;
  justify-content: center;
}
</style> -->


//////v4/////////////////
<script setup lang="ts">
import { ref, watchEffect, computed, watch } from 'vue';
import { useApi } from '@directus/extensions-sdk';

const props = defineProps<{
  sql_query?: string;
  column_order?: string;
}>();

const api = useApi();
const rows = ref<any[]>([]);
const columns = ref<string[]>([]);
const totalRows = ref(0);
const error = ref<string | null>(null);
const loading = ref(false);

const currentPage = ref(1);
const pageSize = ref(10);

const totalPages = computed(() => Math.ceil(totalRows.value / pageSize.value));
const isLastPage = computed(() => currentPage.value >= totalPages.value);

async function fetchPage() {
  if (!props.sql_query) {
    error.value = 'No SQL query provided.';
    return;
  }

  try {
    loading.value = true;
    const offset = (currentPage.value - 1) * pageSize.value;

    const res = await api.post('/endpoint-sql-view', {
      query: props.sql_query,
      limit: pageSize.value,
      offset,
    });

    rows.value = res.data.rows;
    totalRows.value = res.data.total;

    const availableColumns = rows.value.length > 0 ? Object.keys(rows.value[0]) : [];

    if (props.column_order) {
      const preferred = props.column_order.split(',').map(col => col.trim());
      columns.value = preferred.filter(col => availableColumns.includes(col));
    } else {
      columns.value = availableColumns;
    }
  } catch (err: any) {
    error.value = 'Failed to load SQL data.';
    console.error(err);
  } finally {
    loading.value = false;
  }
}

watchEffect(() => {
  fetchPage();
});

watch(pageSize, () => {
  currentPage.value = 1;
  fetchPage();
});

watch(currentPage, () => {
  fetchPage();
});
</script>

<template>
  <div class="panel-container">
    <div v-if="error" class="error-message">{{ error }}</div>
    <div v-else-if="loading">Loading...</div>
    <div v-else>
      <table v-if="rows.length > 0" class="data-table">
        <thead>
          <tr>
            <th v-for="col in columns" :key="col">{{ col }}</th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="(row, i) in rows" :key="i">
            <td v-for="col in columns" :key="col">{{ row[col] }}</td>
          </tr>
        </tbody>
      </table>
      <p v-else>No results found.</p>

      <div class="pagination">
        <button @click="currentPage--" :disabled="currentPage === 1">Previous</button>

        <span>Page {{ currentPage }} of {{ totalPages }}</span>

        <button @click="currentPage++" :disabled="isLastPage">Next</button>

        <label>
          Rows per page:
          <select v-model.number="pageSize">
            <option :value="10">10</option>
            <option :value="25">25</option>
            <option :value="50">50</option>
            <option :value="100">100</option>
          </select>
        </label>

        <label>
          Go to page:
          <select v-model.number="currentPage">
            <option v-for="n in totalPages" :key="n" :value="n">{{ n }}</option>
          </select>
        </label>
      </div>
    </div>
  </div>
</template>

<style scoped>
.panel-container {
  padding: 1rem;
}
.data-table {
  width: 100%;
  border-collapse: collapse;
}
.data-table th,
.data-table td {
  border: 1px solid #ccc;
  padding: 0.5rem;
}
.pagination {
  margin-top: 1rem;
  display: flex;
  align-items: center;
  gap: 1rem;
  flex-wrap: wrap;
  justify-content: center;
}
.pagination label {
  display: flex;
  align-items: center;
  gap: 0.5rem;
}
</style>
