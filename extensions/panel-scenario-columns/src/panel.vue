<template>
  <div class="scenario-summary-panel" :class="{ 'has-header': showHeader }">
    <!-- Control Bar -->
    <div class="control-bar">
      <div class="control-group">
        <!-- Native SELECT (kept) -->
        <div class="select-wrapper">
          <label class="select-label">Scenario</label>
          <select
            v-model="selectedScenario"
            :disabled="loading"
            class="scenario-select"
          >
            <option :value="null" disabled>Select a scenario…</option>
            <option
              v-for="opt in scenarios"
              :key="opt.value"
              :value="opt.value"
            >
              {{ opt.text }}
            </option>
          </select>
        </div>

        <div class="picker-actions">
          <v-chip v-if="linkedSiteCode" small class="mr-s" icon="link">
            Site: {{ linkedSiteCode }}
          </v-chip>

          <v-button
            @click="runAnalysis"
            :loading="running"
            :disabled="!selectedScenario || loading"
            primary
          >
            <v-icon name="play_arrow" left />
            Run Analysis
          </v-button>
        </div>
      </div>

      <div class="control-group">
        <v-button v-if="exportEnabled && scenarioData" @click="exportScenario" small secondary>
          <v-icon name="file_download" /> Export Scenario
        </v-button>
        <v-button v-if="exportEnabled && results.length > 0" @click="exportToCSV" small secondary>
          <v-icon name="download" /> Export Results
        </v-button>
      </div>
    </div>

    <!-- Parameters Panel -->
    <div v-if="showParameters && scenarioData" class="parameters-panel">
      <div class="panel-header" @click="parametersExpanded = !parametersExpanded">
        <v-icon :name="parametersExpanded ? 'expand_less' : 'expand_more'" />
        <span>Parameters</span>
        <v-chip v-if="!parametersExpanded && selectedScenario" small>
          {{ selectedScenario }}
        </v-chip>
      </div>

      <div v-show="parametersExpanded" class="parameters-content">
        <div class="parameter-grid">
          <!-- Site Parameters -->
          <div class="parameter-section">
            <h4 class="section-title">Site Configuration</h4>
            <div class="parameter-item">
              <span class="param-label">Scenario Code</span>
              <span class="param-value">{{ scenarioData.scenario_code }}</span>
            </div>
            <div class="parameter-item">
              <span class="param-label">Consumption Code</span>
              <span class="param-value">{{ scenarioData.consumption_code }}</span>
            </div>
            <div class="parameter-item">
              <span class="param-label">Number of Houses</span>
              <span class="param-value">{{ scenarioData.num_houses }}</span>
            </div>
            <div class="parameter-item">
              <span class="param-label">Yearly Bill</span>
              <span class="param-value">${{ formatNumber(scenarioData.yearly_bill) }}</span>
            </div>
            <div class="parameter-item">
              <span class="param-label">Separate Meter</span>
              <span class="param-value">{{ scenarioData.separate_meter ? 'Yes' : 'No' }}</span>
            </div>
          </div>

          <!-- Solar Parameters -->
          <div class="parameter-section">
            <h4 class="section-title">Solar Configuration</h4>
            <div class="parameter-item">
              <span class="param-label">Solar Code</span>
              <span class="param-value">{{ scenarioData.solar_code }}</span>
            </div>
            <div class="parameter-item">
              <span class="param-label">Solar Scale</span>
              <span class="param-value">{{ scenarioData.solar_scale }}</span>
            </div>
          </div>

          <!-- Battery Parameters -->
          <div class="parameter-section">
            <h4 class="section-title">Battery Configuration</h4>
            <div class="parameter-item">
              <span class="param-label">Charge Max</span>
              <span class="param-value">{{ scenarioData.inverter_max_charge_kw }} kW</span>
            </div>
            <div class="parameter-item">
              <span class="param-label">Discharge Max</span>
              <span class="param-value">{{ scenarioData.inverter_max_discharge_kw }} kW</span>
            </div>
            <div class="parameter-item">
              <span class="param-label">Usable Capacity</span>
              <span class="param-value">{{ scenarioData.battery_usable_capacity_kwh }} kWh</span>
            </div>
            <div class="parameter-item">
              <span class="param-label">RTE</span>
              <span class="param-value">{{ (Number(scenarioData.rte || 0) * 100).toFixed(1) }}%</span>
            </div>
          </div>

          <!-- Codes -->
          <div class="parameter-section">
            <h4 class="section-title">Reference Codes</h4>
            <div class="parameter-item">
              <span class="param-label">LCC Code</span>
              <span class="param-value">{{ scenarioData.lcc_code }}</span>
            </div>
            <div class="parameter-item">
              <span class="param-label">LCR Code</span>
              <span class="param-value">{{ scenarioData.lcr_code }}</span>
            </div>
            <div class="parameter-item">
              <span class="param-label">PCR Code</span>
              <span class="param-value">{{ scenarioData.pcr_code }}</span>
            </div>
            <div class="parameter-item">
              <span class="param-label">PPC Code</span>
              <span class="param-value">{{ scenarioData.ppc_code }}</span>
            </div>
          </div>
        </div>

        <!-- Optional: collapsible SQL preview -->
        <details class="sql-block" v-if="lastSql">
          <summary>View SQL</summary>
          <pre><code>{{ lastSql }}</code></pre>
          <v-button small secondary @click="copy(lastSql)">Copy</v-button>
        </details>
      </div>
    </div>

    <!-- Loading / Error / Results -->
    <div v-if="loading" class="loading-state">
      <v-progress-circular indeterminate />
      <p>Loading scenarios...</p>
    </div>

    <v-notice v-else-if="error" type="danger">
      {{ error }}
    </v-notice>

    <div v-else-if="results.length > 0" class="results-section">
      <div class="results-header">
        <h3>Analysis Results</h3>
        <div class="results-info">
          <span v-if="lastRunTime">Generated: {{ lastRunTime }}</span>
          <v-chip v-if="lastRunMs !== null" small class="ml-s">{{ lastRunMs }} ms</v-chip>
        </div>
      </div>

      <div class="results-table-container">
        <table class="results-table">
          <caption v-if="selectedScenario" class="table-caption">
            Scenario: {{ selectedScenario }} <span v-if="linkedSiteCode">• Site: {{ linkedSiteCode }}</span>
          </caption>
          <thead>
            <tr>
              <th class="metric-column">Metric</th>
              <th v-for="year in yearColumns" :key="year" class="year-column">{{ year }}</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="row in results" :key="row.summary_id" :class="getRowClass(row.summary_id)">
              <td class="metric-cell">
                <span class="metric-id">{{ row.summary_id }}.</span>
                {{ row.metric || 'Metric' }}
              </td>
              <td
                v-for="year in yearColumns"
                :key="year"
                class="value-cell"
                :class="{ pos: Number(row[year]) > 0, neg: Number(row[year]) < 0 }"
              >
                {{ formatValue(row[year] ?? 0, row.summary_id) }}
              </td>
            </tr>

          </tbody>
        </table>
      </div>
    </div>

    <div v-else class="empty-state">
      <v-icon name="analytics" large />
      <p>Select a scenario and click "Run Analysis" to see results</p>
    </div>
  </div>
</template>

<script setup lang="ts">
import { ref, computed, watch, onMounted } from 'vue';
import { useApi } from '@directus/extensions-sdk';

/** Props */
interface Props {
  showHeader?: boolean;
  collection?: string;       // scenario table
  functionSchema?: string;   // usually 'public'
  functionName?: string;     // f_summary_year
  showParameters?: boolean;
  autoFormat?: boolean;
  exportEnabled?: boolean;
}
const props = withDefaults(defineProps<Props>(), {
  showHeader: false,
  collection: 'scenario',
  functionSchema: 'public',
  functionName: 'f_summary_year',
  showParameters: true,
  autoFormat: true,
  exportEnabled: true,
});

/** Types */
interface ScenarioRow {
  // Primary fields
  id: number;
  site_code: string | null;
  scenario_code: string;
  spot_code: string | null;
  consumption_code: string | null;
  consumption_scale: string | null;
  solar_code: string | null;
  solar_scale: string | number | null;
  battery_code: string | null;
  scenario_preferred: boolean | null;
  
  // Capacity and performance fields
  solar_capacity_kw: number | null;
  solar_production_yr_kwh: number | null;
  inverter_max_charge_kw: number | null;
  inverter_max_discharge_kw: number | null;
  battery_initial_capacity_kwh: number | null;
  battery_usable_capacity_kwh: number | null;
  connection_import_capacity_kw: number | null;
  connection_export_capacity_kw: number | null;
  
  // Timestamps
  created_at: string | null;
  updated_at: string | null;
  
  // Additional fields that may exist in Directus
  num_houses?: number | null;
  yearly_bill?: number | null;
  lcc_code?: string | null;
  lcr_code?: string | null;
  pcr_code?: string | null;
  ppc_code?: string | null;
  spot_vs_ave_lower?: number | null;
  spot_vs_ave_upper?: number | null;
  rte?: number | null;
  round_trip_pct?: number | null;
  total?: number | null;
  moving_ave_row_count?: number | null;
  separate_meter?: boolean | null;
  
  // Any other fields
  [key: string]: any;
}
interface ResultRow {
  summary_id: number;
  metric: string;
  site_code: string;
  [year: string]: number | string;
}

/** Services */
const api = useApi();

/** State */
const loading = ref(false);
const running = ref(false);
const error = ref<string | null>(null);
const scenarios = ref<Array<{ text: string; value: string }>>([]);
const selectedScenario = ref<string | null>(null);
const scenarioData = ref<ScenarioRow | null>(null);
const linkedSiteCode = ref<string | null>(null);
const results = ref<ResultRow[]>([]);
const lastRunTime = ref<string>('');
const lastRunMs = ref<number | null>(null);
const lastSql = ref<string>('');
const parametersExpanded = ref(true);

/** Years */
const yearColumns = [
  '2024','2025','2026','2027','2028','2029','2030',
  '2031','2032','2033','2034','2035','2036'
];


/** UI helpers */
function formatNumber(value: number | null | undefined): string {
  if (value == null) return '—';
  return Number(value).toLocaleString(navigator.language || 'en-US', {
    minimumFractionDigits: 0, maximumFractionDigits: 2,
  });
}
function formatValue(value: any, summaryId: number): string {
  if (value === null || value === undefined || Number(value) === 0) return '—';
  const num = Number(value);
  if (Number.isNaN(num)) return String(value);
  if (summaryId === 1) return num.toLocaleString(navigator.language || 'en-US', { maximumFractionDigits: 0 }) + ' kWh';
  const formatted = Math.abs(num).toLocaleString(navigator.language || 'en-US', { maximumFractionDigits: 0 });
  return num < 0 ? `$(${formatted})` : `$${formatted}`;
}
function getRowClass(summaryId: number): string {
  if (summaryId <= 2) return 'row-group-energy';
  if (summaryId <= 5) return 'row-group-cost';
  if (summaryId <= 9) return 'row-group-revenue';
  return '';
}

/** Literal helpers for SQL */
function toNum(x: any): number | null {
  if (x === null || x === undefined || x === '') return null;
  const n = typeof x === 'number' ? x : parseFloat(String(x));
  return Number.isFinite(n) ? n : null;
}
function q(v: any) { if (v == null) return 'NULL'; return `'${String(v).replace(/'/g, "''")}'`; }
function n(v: any) { const num = toNum(v); return num == null ? 'NULL' : String(num); }
function b(v: any) { return v ? 'true' : 'false'; }

/** Load scenarios (simple list for native select) */
async function loadScenarios() {
  loading.value = true;
  error.value = null;
  try {
    const { data } = await api.get(`/items/${props.collection}`, {
      params: { fields: ['scenario_code','scenario_preferred'], sort: 'scenario_code', limit: -1 }
    });
    const items = data?.data || [];
    scenarios.value = items.map((i: any) => ({
      text: i.scenario_code,
      value: i.scenario_code,
    }));
    const preferred = items.find((i: any) => i.scenario_preferred);
    if (preferred) selectedScenario.value = preferred.scenario_code;
  } catch (err: any) {
    error.value = 'Failed to load scenarios: ' + (err.message || 'Unknown error');
  } finally {
    loading.value = false;
  }
}

/** Run analysis */
async function runAnalysis() {
  if (!selectedScenario.value) return;
  running.value = true;
  error.value = null;
  results.value = [];
  lastRunMs.value = null;
  lastSql.value = '';

  try {
    const t0 = performance.now();

    // 1) Fetch scenario row with FK
    const { data: sData } = await api.get(`/items/${props.collection}`, {
      params: {
        filter: { scenario_code: { _eq: selectedScenario.value } },
        limit: 1,
        fields: ['*'] // Fetch all fields from scenario table
      }
    });
    const row: ScenarioRow | undefined = sData?.data?.[0];
    if (!row) throw new Error('Scenario not found');
    scenarioData.value = row;

    // 2) Use consumption_code directly from scenario
    if (!row.consumption_code) throw new Error('consumption_code not found in scenario');
    linkedSiteCode.value = row.consumption_code; // For display purposes

    // 3) Build SQL (named args)
    const sql = `
      SELECT * FROM ${props.functionSchema}.${props.functionName}(
        _consumption_code := ${q(row.consumption_code)},
        _num_houses := ${n(row.num_houses)},
        _solar_scale := ${n(row.solar_scale)},
        _yearly_bill := ${n(row.yearly_bill)},
        _solar_code := ${q(row.solar_code)},
        _lcc_code := ${q(row.lcc_code)},
        _lcr_code := ${q(row.lcr_code)},
        _pcr_code := ${q(row.pcr_code)},
        _spot_vs_ave_lower := ${n(row.spot_vs_ave_lower)},
        _spot_vs_ave_upper := ${n(row.spot_vs_ave_upper)},
        _charge_max := ${n(row.inverter_max_charge_kw)},
        _discharge_max := ${n(row.inverter_max_discharge_kw)},
        _rte := ${n(row.rte)},
        _capacity := ${n(row.battery_usable_capacity_kwh)},
        _round_trip_pct := ${n(row.round_trip_pct)},
        _total := ${n(row.total)},
        _moving_ave_row_count := ${n(row.moving_ave_row_count)},
        _separate_meter := ${b(!!row.separate_meter)},
        _ppc_code := ${q(row.ppc_code)}
      )
    `;
    lastSql.value = sql.trim();

    // 4) Execute (your working endpoint)
    const { data: exec } = await api.post('/endpoint-sql-runner/run-sql', {
      query: sql,
      parameters: { limit: 1000 }
    });
    if (!exec?.success) throw new Error(exec?.error || 'Query execution failed');

    results.value = exec.data || [];
    lastRunTime.value = new Date().toLocaleString();
    lastRunMs.value = Math.round(performance.now() - t0);
  } catch (e: any) {
    error.value = 'Analysis failed: ' + (e?.response?.data?.error || e.message || 'Unknown error');
  } finally {
    running.value = false;
  }
}

/** Export Scenario Parameters */
function exportScenario() {
  if (!scenarioData.value) return;
  const row = scenarioData.value;
  
  // Helper function to format values for CSV
  const formatValue = (value: any): string => {
    if (value === null || value === undefined) return '';
    if (typeof value === 'boolean') return value.toString();
    if (typeof value === 'object') return JSON.stringify(value);
    return String(value);
  };
  
  // Section 1: ALL Scenario Data (dynamically from all fields)
  const scenarioRows = ['Section,Parameter,Value'];
  
  // Add all fields from the scenario row
  Object.keys(row).forEach(key => {
    const value = formatValue(row[key]);
    const displayKey = key.replace(/_/g, ' ').replace(/\b\w/g, l => l.toUpperCase());
    scenarioRows.push(`All Scenario Data,${displayKey},${value}`);
  });
  
  // Add empty row separator
  scenarioRows.push('');
  
  // Section 2: Function Parameters Used (only the ones passed to f_summary_year)
  const functionParams = [
    { key: 'consumption_code', param: '_consumption_code' },
    { key: 'num_houses', param: '_num_houses' },
    { key: 'solar_scale', param: '_solar_scale' },
    { key: 'yearly_bill', param: '_yearly_bill' },
    { key: 'solar_code', param: '_solar_code' },
    { key: 'lcc_code', param: '_lcc_code' },
    { key: 'lcr_code', param: '_lcr_code' },
    { key: 'pcr_code', param: '_pcr_code' },
    { key: 'spot_vs_ave_lower', param: '_spot_vs_ave_lower' },
    { key: 'spot_vs_ave_upper', param: '_spot_vs_ave_upper' },
    { key: 'inverter_max_charge_kw', param: '_charge_max' },
    { key: 'inverter_max_discharge_kw', param: '_discharge_max' },
    { key: 'rte', param: '_rte' },
    { key: 'battery_usable_capacity_kwh', param: '_capacity' },
    { key: 'round_trip_pct', param: '_round_trip_pct' },
    { key: 'total', param: '_total' },
    { key: 'moving_ave_row_count', param: '_moving_ave_row_count' },
    { key: 'separate_meter', param: '_separate_meter', transform: (v: any) => !!v },
    { key: 'ppc_code', param: '_ppc_code' }
  ];
  
  functionParams.forEach(({ key, param, transform }) => {
    let value = row[key];
    if (transform) value = transform(value);
    scenarioRows.push(`Function Parameters,${param},${formatValue(value)}`);
  });
  
  const csv = scenarioRows.join('\n');
  const blob = new Blob([csv], { type: 'text/csv;charset=utf-8;' });
  const link = document.createElement('a');
  link.href = URL.createObjectURL(blob);
  link.download = `scenario_${selectedScenario.value}_complete_${Date.now()}.csv`;
  link.click();
}

/** Export Results CSV */
function exportToCSV() {
  if (results.value.length === 0) return;
  const headers = ['Metric', ...yearColumns];
  const rows = results.value.map((r) => [
    `"${r.summary_id}. ${r.metric}"`,
    ...yearColumns.map((y) => r[y] ?? 0)
  ]);
  const csv = [headers.join(','), ...rows.map((r) => r.join(','))].join('\n');
  const blob = new Blob([csv], { type: 'text/csv;charset=utf-8;' });
  const link = document.createElement('a');
  link.href = URL.createObjectURL(blob);
  link.download = `scenario_${selectedScenario.value}_results_${Date.now()}.csv`;
  link.click();
}

/** Clipboard */
async function copy(txt: string) {
  try { await navigator.clipboard.writeText(txt); } catch {}
}

/** Load scenario data when selection changes */
async function loadScenarioData() {
  if (!selectedScenario.value) {
    scenarioData.value = null;
    linkedSiteCode.value = null;
    return;
  }
  
  try {
    const { data: sData } = await api.get(`/items/${props.collection}`, {
      params: {
        filter: { scenario_code: { _eq: selectedScenario.value } },
        limit: 1,
        fields: ['*'] // Fetch all fields from scenario table
      }
    });
    const row: ScenarioRow | undefined = sData?.data?.[0];
    if (!row) return;
    scenarioData.value = row;

    // Use consumption_code directly
    linkedSiteCode.value = row.consumption_code;
  } catch (err) {
    console.warn('Failed to load scenario data:', err);
  }
}

/** Watch for scenario changes */
watch(selectedScenario, loadScenarioData);

/** Lifecycle */
onMounted(() => { loadScenarios(); });
</script>

<style scoped>
/* Layout */
.scenario-summary-panel {
  height: 100%;
  display: flex;
  flex-direction: column;
  padding: var(--content-padding);
  gap: var(--spacing-m);
}
.scenario-summary-panel.has-header { padding-top: 0; }

/* Control Bar */
.control-bar {
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding: var(--spacing-m);
  background: var(--background-normal);
  border-radius: var(--border-radius);
  border: 1px solid var(--border-normal);
  box-shadow: 0 1px 0 rgba(0,0,0,0.02);
}
.control-group { display: flex; gap: var(--spacing-m); align-items: center; flex-wrap: wrap; }

/* Native select styling */
.select-wrapper { display: flex; flex-direction: column; gap: 6px; }
.select-label { font-size: 0.85rem; color: var(--foreground-subdued); }
.scenario-select {
  min-width: 320px;
  padding: var(--spacing-s) var(--spacing-m);
  background: var(--background-input);
  border: var(--border-width) solid var(--border-normal);
  border-radius: var(--border-radius);
  color: var(--foreground-normal);
  height: var(--input-height);
  transition: border-color var(--fast) var(--transition), background var(--fast) var(--transition);
  appearance: none;
  background-image:
    linear-gradient(45deg, transparent 50%, var(--foreground-subdued) 50%),
    linear-gradient(135deg, var(--foreground-subdued) 50%, transparent 50%),
    linear-gradient(to right, transparent, transparent);
  background-position:
    calc(100% - 18px) calc(50% - 4px),
    calc(100% - 12px) calc(50% - 4px),
    calc(100% - 2.6em) 0;
  background-size: 6px 6px, 6px 6px, 1px 100%;
  background-repeat: no-repeat;
}
.scenario-select:hover:not(:disabled) { border-color: var(--border-normal-alt); background: var(--background-input-alt); }
.scenario-select:focus { outline: none; border-color: var(--primary); }
.scenario-select:disabled { opacity: 0.6; cursor: not-allowed; }

.picker-actions { display: flex; align-items: center; gap: var(--spacing-s); margin-left: var(--spacing-2xl); }

/* Parameters Panel */
.parameters-panel {
  background: var(--background-normal);
  border-radius: calc(var(--border-radius) + 2px);
  border: 1px solid var(--border-normal);
  overflow: hidden;
  box-shadow: 0 1px 0 rgba(0,0,0,0.02);
}
.panel-header {
  display: flex;
  align-items: center;
  gap: var(--spacing-s);
  padding: var(--spacing-m) var(--spacing-l);
  cursor: pointer;
  user-select: none;
  background: var(--background-subdued);
}
.panel-header:hover { background: var(--background-normal-alt); }
.parameters-content { padding: var(--spacing-l); border-top: 1px solid var(--border-normal); }

/* Parameter Grid */
.parameter-grid {
  display: grid;
  grid-template-columns: repeat(12, 1fr);
  gap: var(--spacing-2xl);
  position: relative;
}
.parameter-grid::after {
  content: '';
  position: absolute;
  left: 50%;
  top: 5%;
  bottom: 5%;
  width: 2px;
  background: linear-gradient(to bottom, 
    transparent 0%,
    var(--border-normal) 20%,
    var(--border-normal) 80%,
    transparent 100%
  );
  transform: translateX(-50%);
  z-index: 1;
}
.parameter-section {
  grid-column: span 6;
  display: flex;
  flex-direction: column;
  gap: var(--spacing-m);
  padding: var(--spacing-l);
  background: var(--background-page);
  border: 2px solid var(--border-normal);
  border-radius: calc(var(--border-radius) + 2px);
  box-shadow: 0 2px 4px rgba(0,0,0,0.06);
  position: relative;
}

/* Section-specific styling */
.site-section { border-color: var(--primary-25); }
.solar-section { border-color: var(--warning-25); }
.battery-section { border-color: var(--success-25); }
.codes-section { border-color: var(--secondary-25); }

.section-header {
  display: flex;
  align-items: center;
  gap: var(--spacing-s);
  margin-bottom: var(--spacing-xs);
}
.section-icon {
  color: var(--primary);
  font-size: 1.2em;
}
.section-title {
  margin: 0;
  color: var(--foreground-normal);
  font-size: 0.95rem;
  font-weight: 700;
  text-transform: uppercase;
  letter-spacing: 0.05em;
}
.section-divider {
  height: 2px;
  background: linear-gradient(90deg, var(--primary-50), var(--primary-10));
  border-radius: 1px;
  margin-bottom: var(--spacing-s);
}
.parameter-item {
  display: grid;
  grid-template-columns: 1fr auto;
  gap: var(--spacing-m);
  align-items: center;
  padding: var(--spacing-s) 0;
  border-bottom: 1px solid var(--border-subdued);
}
.parameter-item:last-child {
  border-bottom: none;
}
.param-label { 
  color: var(--foreground-subdued); 
  font-size: 0.9em; 
  font-weight: 500;
}
.param-value { 
  font-weight: 600; 
  font-family: var(--font-family-monospace); 
  color: var(--foreground-normal);
  background: var(--background-normal);
  padding: var(--spacing-xs) var(--spacing-s);
  border-radius: var(--border-radius);
  border: 1px solid var(--border-subdued);
}

/* Results Section */
.results-section {
  flex: 1;
  display: flex;
  flex-direction: column;
  background: var(--background-normal);
  border-radius: calc(var(--border-radius) + 2px);
  border: 1px solid var(--border-normal);
  overflow: hidden;
  box-shadow: 0 1px 0 rgba(0,0,0,0.02);
}
.results-header {
  display: flex; justify-content: space-between; align-items: center;
  padding: var(--spacing-m) var(--spacing-l);
  background: var(--background-subdued);
  border-bottom: 1px solid var(--border-normal);
}
.results-header h3 { margin: 0; font-size: 1.05rem; font-weight: 700; }
.results-info { color: var(--foreground-subdued); font-size: 0.9em; }

/* Table */
.results-table-container { flex: 1; overflow: auto; padding: var(--spacing-m); }
.results-table {
  width: 100%;
  border-collapse: separate;
  border-spacing: 0;
  font-size: 0.92em;
  background: var(--background-page);
  border: 1px solid var(--border-normal);
  border-radius: var(--border-radius);
  overflow: hidden;
  box-shadow: 0 1px 0 rgba(0,0,0,0.02);
}
.table-caption {
  caption-side: top;
  text-align: left;
  padding: var(--spacing-s) var(--spacing-m);
  color: var(--foreground-subdued);
  font-size: 0.9em;
}
.results-table thead { position: sticky; top: 0; z-index: 2; }
.results-table th {
  background: var(--background-normal);
  padding: 10px 12px;
  text-align: left;
  font-weight: 700;
  border-bottom: 1px solid var(--border-normal);
  white-space: nowrap;
}
.results-table th.metric-column {
  position: sticky; left: 0; z-index: 3; box-shadow: 1px 0 0 var(--border-normal);
}
.results-table th.year-column { text-align: right; min-width: 110px; }
.results-table td {
  padding: 10px 12px;
  border-bottom: 1px solid var(--border-subdued);
  background: var(--background-page);
}
.results-table tbody tr:nth-child(odd) td { background: var(--background-subdued); }
.results-table tbody tr:hover td { background: var(--background-highlight); }

/* Sticky first column cells */
.results-table td:first-child {
  position: sticky; left: 0; z-index: 1; background: inherit; box-shadow: 1px 0 0 var(--border-normal);
}

/* Metric & values */
.metric-cell { display: flex; align-items: center; gap: var(--spacing-s); max-width: 420px; }
.metric-id { color: var(--foreground-subdued); font-size: 0.85em; min-width: 2ch; }
.value-cell { text-align: right; font-family: var(--font-family-monospace); white-space: nowrap; }

/* Conditional coloring */
.value-cell.pos { color: var(--success); }
.value-cell.neg { color: var(--danger); }

/* Grouping backgrounds + totals */
.row-group-energy  td { background: color-mix(in srgb, var(--primary-10) 80%, transparent); }
.row-group-cost    td { background: color-mix(in srgb, var(--warning-10) 75%, transparent); }
.row-group-revenue td { background: color-mix(in srgb, var(--success-10) 80%, transparent); }

/* Empty / Loading states */
.loading-state, .empty-state {
  flex: 1; display: flex; flex-direction: column; align-items: center;
  justify-content: center; gap: var(--spacing-m); color: var(--foreground-subdued);
}
.empty-state p { margin: 0; font-size: 1.05rem; }

/* SQL block (optional) */
.sql-block {
  margin-top: var(--spacing-s);
  padding: var(--spacing-s);
  border: 1px dashed var(--border-subdued);
  border-radius: var(--border-radius);
  background: var(--background-subdued);
}
.sql-block summary { cursor: pointer; color: var(--foreground-subdued); }
.sql-block pre { margin: var(--spacing-s) 0 0; max-height: 220px; overflow: auto; }

/* Responsive */
@media (max-width: 1200px) {
  .parameter-grid { gap: var(--spacing-l) var(--spacing-xl); }
  .parameter-section { grid-column: span 12; }
}
@media (max-width: 768px) {
  .control-bar { flex-direction: column; align-items: stretch; gap: var(--spacing-m); }
  .control-group { flex-direction: column; align-items: stretch; }
  .scenario-select { min-width: 100%; }
  .results-table-container { padding: var(--spacing-s); }
}
</style>
