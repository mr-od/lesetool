<template>
  <div class="scenario-summary-panel" :class="{ 'has-header': showHeader }">
    <!-- Control Bar -->
    <div class="control-bar">
      <div class="control-group">
        <select
          v-model="selectedScenario"
          :disabled="loading"
          class="scenario-select"
        >
          <option :value="null" disabled>Select a scenario...</option>
          <option
            v-for="scenario in scenarios"
            :key="scenario.value"
            :value="scenario.value"
          >
            {{ scenario.text }}
          </option>
        </select>

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

      <div v-if="exportEnabled && results.length > 0" class="control-group">
        <v-button @click="exportToCSV" small secondary>
          <v-icon name="download" />
          Export CSV
        </v-button>
      </div>
    </div>

    <!-- Parameters Panel (Collapsible) -->
    <div v-if="showParameters && scenarioData" class="parameters-panel">
      <div class="panel-header" @click="parametersExpanded = !parametersExpanded">
        <v-icon :name="parametersExpanded ? 'expand_less' : 'expand_more'" />
        <span>Parameters</span>
        <v-chip v-if="!parametersExpanded" small>
          {{ selectedScenario }}
        </v-chip>
      </div>

      <div v-show="parametersExpanded" class="parameters-content">
        <div class="parameter-grid">
          <!-- Site Parameters -->
          <div class="parameter-section">
            <h4>Site Configuration</h4>
            <div class="parameter-item">
              <span class="param-label">Scenario Code:</span>
              <span class="param-value">{{ scenarioData.scenario_code }}</span>
            </div>
            <div class="parameter-item">
              <span class="param-label">Linked Site Code:</span>
              <span class="param-value">{{ linkedSiteCode }}</span>
            </div>
            <div class="parameter-item">
              <span class="param-label">Number of Houses:</span>
              <span class="param-value">{{ scenarioData.num_houses }}</span>
            </div>
            <div class="parameter-item">
              <span class="param-label">Yearly Bill:</span>
              <span class="param-value">${{ formatNumber(scenarioData.yearly_bill) }}</span>
            </div>
            <div class="parameter-item">
              <span class="param-label">Separate Meter:</span>
              <span class="param-value">{{ scenarioData.separate_meter ? 'Yes' : 'No' }}</span>
            </div>
          </div>

          <!-- Solar Parameters -->
          <div class="parameter-section">
            <h4>Solar Configuration</h4>
            <div class="parameter-item">
              <span class="param-label">Solar Code:</span>
              <span class="param-value">{{ scenarioData.solar_code }}</span>
            </div>
            <div class="parameter-item">
              <span class="param-label">Solar Scale:</span>
              <span class="param-value">{{ scenarioData.solar_scale }}</span>
            </div>
          </div>

          <!-- Battery Parameters -->
          <div class="parameter-section">
            <h4>Battery Configuration</h4>
            <div class="parameter-item">
              <span class="param-label">Charge Max:</span>
              <span class="param-value">{{ scenarioData.inverter_max_charge_kw }} kW</span>
            </div>
            <div class="parameter-item">
              <span class="param-label">Discharge Max:</span>
              <span class="param-value">{{ scenarioData.inverter_max_discharge_kw }} kW</span>
            </div>
            <div class="parameter-item">
              <span class="param-label">Usable Capacity:</span>
              <span class="param-value">{{ scenarioData.battery_usable_capacity_kwh }} kWh</span>
            </div>
            <div class="parameter-item">
              <span class="param-label">RTE:</span>
              <span class="param-value">{{ (Number(scenarioData.rte || 0) * 100).toFixed(1) }}%</span>
            </div>
          </div>

          <!-- Codes -->
          <div class="parameter-section">
            <h4>Reference Codes</h4>
            <div class="parameter-item">
              <span class="param-label">LCC Code:</span>
              <span class="param-value">{{ scenarioData.lcc_code }}</span>
            </div>
            <div class="parameter-item">
              <span class="param-label">LCR Code:</span>
              <span class="param-value">{{ scenarioData.lcr_code }}</span>
            </div>
            <div class="parameter-item">
              <span class="param-label">PCR Code:</span>
              <span class="param-value">{{ scenarioData.pcr_code }}</span>
            </div>
            <div class="parameter-item">
              <span class="param-label">PPC Code:</span>
              <span class="param-value">{{ scenarioData.ppc_code }}</span>
            </div>
          </div>
        </div>
      </div>
    </div>

    <!-- Loading State -->
    <div v-if="loading" class="loading-state">
      <v-progress-circular indeterminate />
      <p>Loading scenarios...</p>
    </div>

    <!-- Error State -->
    <v-notice v-else-if="error" type="danger">
      {{ error }}
    </v-notice>

    <!-- Results Table -->
    <div v-else-if="results.length > 0" class="results-section">
      <div class="results-header">
        <h3>Analysis Results: {{ selectedScenario }}</h3>
        <div class="results-info">
          <span>Generated: {{ lastRunTime }}</span>
        </div>
      </div>

      <div class="results-table-container">
        <table class="results-table">
          <thead>
            <tr>
              <th class="metric-column">Metric</th>
              <th v-for="year in yearColumns" :key="year" class="year-column">
                {{ year }}
              </th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="row in results" :key="row.summary_id" :class="getRowClass(row.summary_id)">
              <td class="metric-cell">
                <span class="metric-id">{{ row.summary_id }}.</span>
                {{ row.metric || 'Metric' }}
              </td>
              <td v-for="year in yearColumns" :key="year" class="value-cell">
                {{ formatValue(row[year] ?? 0, row.summary_id) }}
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>

    <!-- Empty State -->
    <div v-else class="empty-state">
      <v-icon name="analytics" large />
      <p>Select a scenario and click "Run Analysis" to see results</p>
    </div>
  </div>
</template>

<script setup lang="ts">
import { ref, computed, onMounted } from 'vue';
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
  id: number;
  scenario_code: string;

  // IMPORTANT: use actual DB column names/types you shared
  num_houses: number | null;           // integer (we'll pass as numeric)
  yearly_bill: number | null;          // real/numeric
  solar_code: string | null;
  solar_scale: string | number | null; // varchar → we coerce to numeric
  inverter_max_charge_kw: number | null;
  inverter_max_discharge_kw: number | null;
  battery_usable_capacity_kwh: number | null;
  lcc_code: string | null;
  lcr_code: string | null;
  pcr_code: string | null;
  spot_vs_ave_lower: number | null;
  spot_vs_ave_upper: number | null;
  rte: number | null;
  round_trip_pct: number | null;
  total: number | null;
  moving_ave_row_count: number | null;
  separate_meter: boolean | null;

  site: number | null; // FK to public.site(id)
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
const parametersExpanded = ref(false);

/** Years */
const yearColumns = [
  '2024','2025','2026','2027','2028','2029','2030',
  '2031','2032','2033','2034','2035','2036'
];

/** UI helpers */
function formatNumber(value: number | null | undefined): string {
  if (value == null) return '—';
  return Number(value).toLocaleString('en-US', { minimumFractionDigits: 0, maximumFractionDigits: 2 });
}
function formatValue(value: any, summaryId: number): string {
  if (value === null || value === undefined || value === 0) return '—';
  const num = Number(value);
  if (Number.isNaN(num)) return String(value);
  if (summaryId === 1) return num.toLocaleString('en-US', { maximumFractionDigits: 0 }) + ' kWh';
  const formatted = Math.abs(num).toLocaleString('en-US', { maximumFractionDigits: 0 });
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
function q(v: any) { // quote text
  if (v === null || v === undefined) return 'NULL';
  return `'${String(v).replace(/'/g, "''")}'`;
}
function n(v: any) { // numeric or NULL
  const num = toNum(v);
  return num === null ? 'NULL' : String(num);
}
function b(v: any) { // boolean
  return v ? 'true' : 'false';
}

/** Load scenarios for dropdown (no nested fields) */
async function loadScenarios() {
  loading.value = true;
  error.value = null;
  try {
    const { data } = await api.get(`/items/${props.collection}`, {
      params: {
        fields: ['scenario_code','scenario_preferred'],
        sort: 'scenario_code',
        limit: -1,
      },
    });
    const items = data?.data || [];
    scenarios.value = items.map((i: any) => ({
      text: `${i.scenario_code}${i.scenario_preferred ? ' ⭐' : ''}`,
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

/** Run analysis for the selected scenario */
async function runAnalysis() {
  if (!selectedScenario.value) return;
  running.value = true;
  error.value = null;
  results.value = [];

  try {
    // 1) Fetch the scenario row (include FK 'site' + all needed fields)
    const { data: sData } = await api.get(`/items/${props.collection}`, {
      params: {
        filter: { scenario_code: { _eq: selectedScenario.value } },
        limit: 1,
        fields: [
          'id','scenario_code','num_houses','yearly_bill','solar_code','solar_scale',
          'inverter_max_charge_kw','inverter_max_discharge_kw','battery_usable_capacity_kwh',
          'lcc_code','lcr_code','pcr_code',
          'spot_vs_ave_lower','spot_vs_ave_upper','rte','round_trip_pct','total',
          'moving_ave_row_count','separate_meter','ppc_code', // ppc not used by function but shown in params
          'site' // FK id
        ]
      }
    });
    const row: ScenarioRow | undefined = sData?.data?.[0];
    if (!row) throw new Error('Scenario not found');
    scenarioData.value = row;

    // 2) Resolve site_code by reading /items/site/<id>
    linkedSiteCode.value = null;
    if (row.site != null) {
      const { data: siteResp } = await api.get(`/items/site/${row.site}`, {
        params: { fields: ['site_code'] }
      });
      linkedSiteCode.value = siteResp?.data?.site_code ?? null;
    }
    if (!linkedSiteCode.value) {
      throw new Error('Linked site_code not found for this scenario');
    }

    // 3) Build the function call (named args; matches your signature exactly)
    const sql = `
      SELECT * FROM ${props.functionSchema}.${props.functionName}(
        _site_code := ${q(linkedSiteCode.value)},
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
        _separate_meter := ${b(!!row.separate_meter)}
      )
    `;

    // 4) Execute via endpoint (auto-appends LIMIT if missing)
    const { data: exec } = await api.post('/endpoint-sql-runner/run-sql', {
      query: sql,
      parameters: { limit: 1000 }
    });

    if (!exec?.success) {
      throw new Error(exec?.error || 'Query execution failed');
    }

    results.value = exec.data || [];
    lastRunTime.value = new Date().toLocaleString();
  } catch (e: any) {
    error.value = 'Analysis failed: ' + (e?.response?.data?.error || e.message || 'Unknown error');
  } finally {
    running.value = false;
  }
}

/** Export CSV of the results table */
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
  link.download = `scenario_${selectedScenario.value}_${Date.now()}.csv`;
  link.click();
}

/** Lifecycle */
onMounted(() => {
  loadScenarios();
});
</script>

<style scoped>
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
}
.control-group { display: flex; gap: var(--spacing-m); align-items: center; }
.scenario-select {
  min-width: 260px;
  padding: var(--spacing-s) var(--spacing-m);
  background: var(--background-input);
  border: var(--border-width) solid var(--border-normal);
  border-radius: var(--border-radius);
  color: var(--foreground-normal);
  font-size: var(--input-font-size);
  height: var(--input-height);
}
.scenario-select:disabled { opacity: 0.5; cursor: not-allowed; }

/* Parameters Panel */
.parameters-panel {
  background: var(--background-normal);
  border-radius: var(--border-radius);
  border: 1px solid var(--border-normal);
  overflow: hidden;
}
.panel-header {
  display: flex; align-items: center; gap: var(--spacing-s);
  padding: var(--spacing-m); cursor: pointer; user-select: none;
  background: var(--background-subdued);
}
.parameters-content { padding: var(--spacing-l); border-top: 1px solid var(--border-normal); }
.parameter-grid {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
  gap: var(--spacing-l);
}
.parameter-section { display: flex; flex-direction: column; gap: var(--spacing-s); }
.parameter-section h4 {
  margin: 0 0 var(--spacing-xs) 0; color: var(--foreground-subdued);
  font-size: 0.9em; text-transform: uppercase; letter-spacing: .5px;
}
.parameter-item { display: flex; justify-content: space-between; align-items: center; padding: var(--spacing-xs) 0; }
.param-label { color: var(--foreground-subdued); font-size: 0.9em; }
.param-value { font-weight: 500; font-family: var(--font-family-monospace); }

/* Results Section */
.results-section { flex: 1; display: flex; flex-direction: column; background: var(--background-normal); border-radius: var(--border-radius); overflow: hidden; }
.results-header {
  display: flex; justify-content: space-between; align-items: center;
  padding: var(--spacing-m); background: var(--background-subdued); border-bottom: 1px solid var(--border-normal);
}
.results-table-container { flex: 1; overflow: auto; }
.results-table { width: 100%; border-collapse: collapse; font-size: 0.9em; }
.results-table thead { position: sticky; top: 0; z-index: 1; }
.results-table th {
  background: var(--background-page); padding: var(--spacing-s) var(--spacing-m);
  text-align: left; font-weight: 600; border-bottom: 2px solid var(--border-normal);
}
.results-table th.year-column { text-align: right; min-width: 100px; }
.results-table td { padding: var(--spacing-s) var(--spacing-m); border-bottom: 1px solid var(--border-subdued); }
.metric-cell { display: flex; align-items: center; gap: var(--spacing-xs); }
.metric-id { color: var(--foreground-subdued); font-size: 0.85em; }
.value-cell { text-align: right; font-family: var(--font-family-monospace); white-space: nowrap; }

/* Row grouping colors */
.row-group-energy  { background: var(--primary-10); }
.row-group-cost    { background: var(--warning-10); }
.row-group-revenue { background: var(--success-10); }

.results-table tr:hover { background: var(--background-highlight) !important; }

/* States */
.loading-state, .empty-state {
  flex: 1; display: flex; flex-direction: column; align-items: center;
  justify-content: center; gap: var(--spacing-m); color: var(--foreground-subdued);
}
.empty-state p { margin: 0; font-size: 1.1em; }

/* Responsive */
@media (max-width: 1200px) {
  .parameter-grid { grid-template-columns: repeat(auto-fit, minmax(250px, 1fr)); }
}
@media (max-width: 768px) {
  .control-bar { flex-direction: column; align-items: stretch; }
  .control-group { flex-direction: column; width: 100%; }
  .parameter-grid { grid-template-columns: 1fr; }
}
</style>
