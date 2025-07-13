<template>
  <div class="panel-container">
    <v-button @click="openLink" color="primary">
      {{ props.label || 'Open Link' }}
    </v-button>
  </div>
</template>

<script setup lang="ts">
const props = defineProps<{
  url?: string;
  label?: string;
}>();

function openLink() {
  if (props.url) {
    window.open(props.url, '_blank');
  } else {
    alert('No URL defined.');
  }
}
</script>

<style scoped>
.panel-container {
  padding: 20px;
  text-align: center;
}
</style>
