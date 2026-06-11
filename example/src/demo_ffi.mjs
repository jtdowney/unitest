// FFI helpers to demonstrate failures.

// Call a function that doesn't exist to trigger a real TypeError
export function nonexistentFunction() {
  const obj = {};
  obj.thisMethodDoesNotExist();
}

// Throw a runtime error to demonstrate a crashed test
export function crash() {
  throw new Error("simulated crash");
}
