<template>
  <div class="p-4">
    <v-button @click="fetchData" color="primary" :loading="loading">
      Load Data
    </v-button>

    <div v-if="error" class="text-red-600 mt-2">{{ error }}</div>

    <div v-if="ready && data.length" class="overflow-auto mt-4">
      <table class="min-w-full border border-gray-300">
        <thead>
          <tr>
            <th v-for="(value, key) in data[0]" :key="key" class="px-3 py-2 border-b bg-gray-100 text-left">
              {{ key }}
            </th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="(row, i) in data" :key="i">
            <td v-for="(value, key) in row" :key="key" class="px-3 py-2 border-b">
              {{ value }}
            </td>
          </tr>
        </tbody>
      </table>
    </div>
  </div>
</template>

<script setup lang="ts">
import { ref } from 'vue';

const props = defineProps<{
  year_range?: string[];
  order_metrics?: string[];
  column_mode?: 'years' | 'metrics';
}>();

const data = ref<any[]>([]);
const loading = ref(false);
const error = ref('');
const ready = ref(false);

const fetchData = async () => {
  if (!props.year_range || !props.order_metrics) {
    error.value = 'Please select year range and metrics.';
    return;
  }

  loading.value = true;
  error.value = '';

  try {
    const response = await fetch('/endpoint-energy-summary', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        years: props.year_range,
        metrics: props.order_metrics,
        mode: props.column_mode ?? 'years',
      }),
    });

    const result = await response.json();
    if (!response.ok) throw new Error(result.error || 'Fetch failed');
    data.value = result.rows || result;
    ready.value = true;
  } catch (err: any) {
    error.value = err.message;
  } finally {
    loading.value = false;
  }
};
</script>

<style scoped>
table {
  border-collapse: collapse;
  width: 100%;
}
th,
td {
  border: 1px solid #e5e7eb;
  text-align: left;
  padding: 8px;
}
th {
  background-color: #f3f4f6;
  font-weight: 600;
}
</style>
