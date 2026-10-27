import { createRouter, createWebHashHistory } from "vue-router";
import ConnectionView from "../views/ConnectionView.vue";
import SettingsView from "../views/SettingsView.vue";
import SettingsLayout from "../views/SettingsLayout.vue";
import ApplicationSettingsView from "../views/ApplicationSettingsView.vue";
import LogsView from "../views/LogsView.vue";
import NotFound from "../views/NotFound.vue";
export default createRouter({
  history: createWebHashHistory(),
  routes: [
    { path: "/", component: ConnectionView },
    { path: "/settings", component: SettingsLayout, children: [
      { path: "", component: SettingsView },
      { path: "app", component: ApplicationSettingsView },
    ] },
    { path: "/logs", component: LogsView },
    { path: "/:pathMatch(.*)*", component: NotFound },
  ],
});
