import { describe, expect, it, vi } from "vitest";
import { flushPromises, mount } from "@vue/test-utils";
import ApplicationSettingsView from "./ApplicationSettingsView.vue";

const render = (actions) => mount(ApplicationSettingsView, {
  props: { actions }, global: { stubs: { RouterLink: { template: "<a><slot /></a>" } } },
});
describe("application preferences", () => {
  it("waits for the OS and persistence before displaying an enabled switch", async () => {
    let finishRead, finishSave;
    const actions = {
      getAppSettings: vi.fn(() => new Promise(resolve => { finishRead = resolve; })),
      saveAppSettings: vi.fn(() => new Promise(resolve => { finishSave = resolve; })),
    };
    const wrapper = render(actions);
    const toggle = wrapper.get('[aria-label="开机自启"]');
    expect(toggle.element.disabled).toBe(true);
    finishRead({ autoStart: false, autoConnect: true });
    await flushPromises();
    await toggle.trigger("click");
    expect(actions.saveAppSettings).toHaveBeenCalledWith({ autoStart: true });
    expect(toggle.attributes("aria-checked")).toBe("false");
    expect(toggle.element.disabled).toBe(true);
    finishSave({ autoStart: true, autoConnect: true });
    await flushPromises();
    expect(toggle.attributes("aria-checked")).toBe("true");
    expect(wrapper.text()).toContain("已自动保存");
  });
  it("does not claim success on a write failure and re-reads the authoritative state", async () => {
    const actions = {
      getAppSettings: vi.fn().mockResolvedValue({ autoStart: true, autoConnect: false }),
      saveAppSettings: vi.fn().mockRejectedValue(new Error("系统拒绝操作")),
    };
    const wrapper = render(actions);
    await flushPromises();
    await wrapper.get('[aria-label="开机自启"]').trigger("click");
    await flushPromises();
    expect(wrapper.get('[aria-label="开机自启"]').attributes("aria-checked")).toBe("true");
    expect(wrapper.get('[role="alert"]').text()).toContain("系统拒绝操作");
    expect(wrapper.text()).not.toContain("已自动保存");
    expect(actions.getAppSettings).toHaveBeenCalledTimes(2);
  });
  it("keeps controls unavailable after a read failure and supports retry", async () => {
    const actions = {
      getAppSettings: vi.fn().mockRejectedValueOnce(new Error("读取失败"))
        .mockResolvedValue({ autoStart: false, autoConnect: true }),
    };
    const wrapper = render(actions);
    await flushPromises();
    expect(wrapper.get('[aria-label="启动后自动连接"]').element.disabled).toBe(true);
    await wrapper.get('[role="alert"] button').trigger("click");
    await flushPromises();
    expect(wrapper.find('[role="alert"]').exists()).toBe(false);
    expect(wrapper.get('[aria-label="启动后自动连接"]').attributes("aria-checked")).toBe("true");
  });
});
