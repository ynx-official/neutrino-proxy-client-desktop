<script setup>
import logo from "../assets/project-logo.png";
</script>

<template>
  <img class="brand-mark" :src="logo" alt="" aria-hidden="true" draggable="false" />
</template>

<style scoped>
.brand-mark {
  display: block;
  flex: none;
  object-fit: contain;
}
</style>
