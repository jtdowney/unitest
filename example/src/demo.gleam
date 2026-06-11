//// A simple demo module with functions to test.

pub fn add(a: Int, b: Int) -> Int {
  a + b
}

pub fn multiply(a: Int, b: Int) -> Int {
  a * b
}

pub fn divide(a: Int, b: Int) -> Result(Int, String) {
  case b {
    0 -> Error("division by zero")
    _ -> Ok(a / b)
  }
}

pub fn is_even(n: Int) -> Bool {
  n % 2 == 0
}

pub fn fibonacci(n: Int) -> Int {
  case n {
    0 -> 0
    1 -> 1
    _ -> fibonacci(n - 1) + fibonacci(n - 2)
  }
}

/// Calls a non-existent function to demo undefined function errors
@external(erlang, "nonexistent_module", "nonexistent_function")
@external(javascript, "./demo_ffi.mjs", "nonexistentFunction")
pub fn call_undefined() -> Nil

/// Raises a raw runtime error to demo crashed tests
@external(erlang, "demo_ffi", "crash")
@external(javascript, "./demo_ffi.mjs", "crash")
pub fn crash() -> Nil

/// Crashes after descending several call frames
pub fn deep_crash() -> Int {
  descend(5)
}

fn descend(depth: Int) -> Int {
  case depth {
    0 -> {
      crash()
      0
    }
    _ -> descend(depth - 1) + 1
  }
}
