//// Tests demonstrating unitest's tagging feature.
////
//// Run with:
////   gleam test                     # runs all (slow tests skipped by default)
////   gleam test -- --tag slow       # runs only slow tests
////   gleam test -- --tag integration # runs only integration tests

import demo
import unitest

pub fn fast_computation_test() {
  assert demo.add(1, 1) == 2
}

pub fn fibonacci_small_test() {
  assert demo.fibonacci(5) == 5
  assert demo.fibonacci(10) == 55
}

pub fn fibonacci_large_test() {
  use <- unitest.tag("slow")
  assert demo.fibonacci(20) == 6765
  assert demo.fibonacci(25) == 75_025
}

pub fn fibonacci_very_large_test() {
  use <- unitest.tags(["slow", "expensive"])
  assert demo.fibonacci(30) == 832_040
}

pub fn simulated_db_test() {
  use <- unitest.tag("integration")
  // Simulating a database test
  let result = demo.divide(100, 10)
  assert result == Ok(10)
}

pub fn simulated_api_test() {
  use <- unitest.tags(["integration", "slow"])
  // Simulating a slow API call test
  let result = demo.multiply(7, 6)
  assert result == 42
}

pub fn unit_test_example_test() {
  // This is a fast unit test with no tags
  assert demo.is_even(100) == True
}
