<!-- <template>
	<div class="text" :class="{ 'has-header': showHeader }">
		{{ text }}
	</div>
</template>

<script lang="ts">
import { defineComponent } from 'vue';

export default defineComponent({
	props: {
		showHeader: {
			type: Boolean,
			default: false,
		},
		text: {
			type: String,
			default: '',
		},
	},
});
</script>

<style scoped>
.text {
	padding: 12px;
}

.text.has-header {
	padding: 0 12px;
}
</style> -->
<!-- 
<template>
  <div class="panel-container">
    <v-input v-model="siteId" label="Site ID" type="number" />
    <v-input v-model="initialSoc" label="Initial SOC (kWh)" type="number" />
    <v-input v-model="chargeLimit" label="Charge Limit (kWh)" type="number" />

    <v-button @click="runSimulation" color="primary">
      Run Simulation
    </v-button>
  </div>
</template>

<script setup lang="ts">
import { ref } from 'vue';
import { useApi } from '@directus/extensions-sdk';

const siteId = ref<number | null>(null);
const initialSoc = ref<number | null>(null);
const chargeLimit = ref<number | null>(null);
const api = useApi();

async function runSimulation() {
  if (!siteId.value || !initialSoc.value || !chargeLimit.value) {
    alert('All fields are required');
    return;
  }

  try {
    const res = await api.post('/run-sql-endpoint', {
      site_id: siteId.value,
      initial_soc_kwh: initialSoc.value,
      charge_limit_kwh: chargeLimit.value,
    });
    alert('Simulation success!');
  } catch (err) {
    alert('Simulation failed');
    console.error(err);
  }
}
</script>

<style scoped>
.panel-container {
  padding: 20px;
  display: flex;
  flex-direction: column;
  gap: 10px;
  max-width: 400px;
  margin: 0 auto;
}
</style> -->

<template>
  <div class="panel-container">
    <v-input
      v-model="siteId"
      label="Site ID"
      type="number"
      class="input-field"
      placeholder="e.g. 1"
    />
    <v-input
      v-model="initialSoc"
      label="Initial SOC (kWh)"
      type="number"
      class="input-field"
      placeholder="e.g. 500"
    />
    <v-input
      v-model="chargeLimit"
      label="Charge Limit (kWh)"
      type="number"
      class="input-field"
      placeholder="e.g. 10"
    />

    <v-button @click="runFunction" color="primary">
      Run Battery Simulation
    </v-button>
  </div>
</template>

<script setup lang="ts">
import { ref } from 'vue';
import { useApi } from '@directus/extensions-sdk';

const siteId = ref<number | null>(null);
const initialSoc = ref<number | null>(null);
const chargeLimit = ref<number | null>(null);

const api = useApi();

async function runFunction() {
  if (siteId.value === null || initialSoc.value === null || chargeLimit.value === null) {
    alert('Please fill in all input fields.');
    return;
  }

  try {
    const response = await api.post('/endpoint-run-battery-sim', {
  site_id: siteId.value,
  initial_soc_kwh: initialSoc.value,
  charge_limit_kwh: chargeLimit.value,
});
    alert('Simulation completed: ' + JSON.stringify(response.data));
  } catch (err) {
    alert('Failed to run simulation');
    console.error(err);
  }
}
</script>

<style scoped>
.panel-container {
  padding: 20px;
  text-align: center;
  display: flex;
  flex-direction: column;
  gap: 10px;
  max-width: 400px;
  margin: 0 auto;
}
.input-field {
  width: 100%;
}
</style>
