import { validateRegistration } from "../src/validation.js";

const valid = {
  email: "user@example.com",
  password: "Str0ng!Pass",
  fullName: "Test User",
  role: "patient",
};

describe("validateRegistration", () => {
  it("accepts a valid registration", () => {
    expect(validateRegistration(valid)).toEqual([]);
  });

  it("rejects invalid email", () => {
    expect(validateRegistration({ ...valid, email: "bad" })).not.toEqual([]);
  });

  it.each(["Sh0rt!a", "nouppercase1!", "NOLOWERCASE1!", "NoDigits!!", "NoSpecial11"])(
    "rejects weak password %s",
    (password) => {
      expect(validateRegistration({ ...valid, password }).length).toBeGreaterThan(0);
    }
  );

  it("rejects invalid role", () => {
    expect(validateRegistration({ ...valid, role: "superuser" })).not.toEqual([]);
  });

  it("rejects invalid language", () => {
    expect(validateRegistration({ ...valid, preferredLanguage: "fr" })).not.toEqual([]);
  });

  it("accepts arabic language preference", () => {
    expect(validateRegistration({ ...valid, preferredLanguage: "ar" })).toEqual([]);
  });
});
