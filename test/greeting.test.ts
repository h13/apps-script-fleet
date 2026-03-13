import { getGreeting } from "../src/greeting.js";

describe("getGreeting", () => {
  it("should return greeting message", () => {
    expect(getGreeting()).toBe("Hello from Google Apps Script!");
  });
});
