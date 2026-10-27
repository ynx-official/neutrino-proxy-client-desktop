import { describe, it, expect, vi } from "vitest";
import { mount, flushPromises } from "@vue/test-utils";
import SettingsView from "./SettingsView.vue";

describe("connection configuration", () => {
  it("shows field errors and never calls save for invalid input", async () => {
    const save = vi.fn();
    const wrapper = mount(SettingsView, {
      props: {
        model: {
          config: {
            server: "",
            port: 9002,
            ssl: true,
            certificatePath: "",
            udpPortRange: "10000-10500",
            reconnectSeconds: 10,
          },
          hasLicense: false,
          state: "idle",
        },
        actions: { save },
      },
    });
    await wrapper.get("form").trigger("submit");
    await flushPromises();
    expect(wrapper.text()).toContain("请填写服务器地址");
    expect(wrapper.text()).toContain("请填写 License");
    expect(save).not.toHaveBeenCalled();
  });
  it("keeps an existing stored license without submitting a mask as a credential", async () => {
    const save = vi.fn().mockResolvedValue(undefined);
    const wrapper = mount(SettingsView, {
      props: {
        model: {
          config: {
            server: "127.0.0.1",
            port: 9002,
            ssl: false,
            certificatePath: "",
            udpPortRange: "10000-10500",
            reconnectSeconds: 10,
          },
          hasLicense: true,
          state: "idle",
        },
        actions: { save },
      },
    });
    await wrapper.get("form").trigger("submit");
    await flushPromises();
    expect(save).toHaveBeenCalledWith(
      expect.objectContaining({
        config: expect.objectContaining({ server: "127.0.0.1" }),
        license: null,
        connect: true,
      }),
    );
  });
  it("loads the saved config when the backend responds after the page mounts", async () => {
    const wrapper = mount(SettingsView, {
      props: {
        model: {
          config: { server: "", port: 9002 },
          hasLicense: false,
          state: "idle",
        },
        actions: {},
      },
    });
    await wrapper.setProps({
      model: {
        config: { server: "saved.example.com", port: 1234 },
        hasLicense: true,
        state: "idle",
      },
    });
    expect(wrapper.get("#server").element.value).toBe("saved.example.com");
    expect(wrapper.get("#port").element.value).toBe("1234");
  });
});
