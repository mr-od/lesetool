<template>
  <v-select
    v-model="internalValue"
    :items="items"
    item-title="label"
    item-value="value"
    :loading="loading"
    :disabled="loading"
    @update:modelValue="updateValue"
    outlined
    dense
  ></v-select>
</template>

<script setup>
import { ref, watch, onMounted } from 'vue';
import { useApi } from '@directus/extensions-sdk';

const props = defineProps({
  value: [String, Number],
  collection: String,
  valueField: String,
  labelField: String,
});

const emit = defineEmits(['update:value']);

const api = useApi();
const items = ref([]);
const loading = ref(false);
const internalValue = ref(props.value);

// Keep internal value in sync
watch(() => props.value, (newVal) => {
  internalValue.value = newVal;
});

function updateValue(val) {
  emit('update:value', val);
}

async function fetchItems() {
  if (!props.collection || !props.valueField || !props.labelField) return;

  loading.value = true;

  try {
    const res = await api.get(`/items/${props.collection}?limit=-1`);
    items.value = res.data.data.map((item) => ({
      value: item[props.valueField],
      label: item[props.labelField],
    }));
  } catch (err) {
    console.error('Failed to fetch items:', err);
  } finally {
    loading.value = false;
  }
}

onMounted(fetchItems);
watch(() => [props.collection, props.valueField, props.labelField], fetchItems);
</script>

<style scoped>
.v-select {
  width: 100%;
}
</style>
