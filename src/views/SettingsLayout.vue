<script setup>
import { useRoute } from "vue-router";
import Icon from "../components/AppIcon.vue";
defineProps({ model: Object, actions: Object });
const route = useRoute();
</script>
<template>
  <section class="settings-layout">
    <header class="page-header settings-header">
      <h1>设置</h1>
      <button v-if="route.path === '/settings'" class="button secondary" @click="actions.importConfig?.()">
        <Icon name="upload" :size="17" />导入配置
      </button>
    </header>
    <nav class="settings-tabs" aria-label="设置分类">
      <RouterLink to="/settings" exact-active-class="selected">连接配置</RouterLink>
      <RouterLink to="/settings/app" exact-active-class="selected">应用设置</RouterLink>
    </nav>
    <RouterView v-slot="{ Component }">
      <component :is="Component" :model="model" :actions="actions" />
    </RouterView>
  </section>
</template>
