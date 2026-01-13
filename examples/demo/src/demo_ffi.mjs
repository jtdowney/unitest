// FFI file to demonstrate undefined function errors
export function nonexistentFunction() {
  // Call a function that doesn't exist to trigger a real TypeError
  const obj = {};
  obj.thisMethodDoesNotExist();
}
