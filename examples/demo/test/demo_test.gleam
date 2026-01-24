//// Basic tests for the demo module.
////
//// To see failure UX demos, run:
////   gleam test -- --tag failure_demo

import demo
import gleam/list
import unitest.{Options}

pub fn main() {
  // Skip "slow" and "failure_demo" tagged tests by default
  // Run failure demos with: gleam test -- --tag failure_demo
  unitest.run(
    Options(..unitest.default_options(), ignored_tags: ["slow", "failure_demo"]),
  )
}

pub fn add_positive_numbers_test() {
  assert demo.add(2, 3) == 5
}

pub fn add_negative_numbers_test() {
  assert demo.add(-1, -1) == -2
}

pub fn add_zero_test() {
  assert demo.add(0, 5) == 5
}

pub fn multiply_test() {
  assert demo.multiply(3, 4) == 12
}

pub fn multiply_by_zero_test() {
  assert demo.multiply(5, 0) == 0
}

pub fn divide_success_test() {
  assert demo.divide(10, 2) == Ok(5)
}

pub fn divide_by_zero_test() {
  assert demo.divide(10, 0) == Error("division by zero")
}

pub fn is_even_true_test() {
  assert demo.is_even(4) == True
}

pub fn is_even_false_test() {
  assert demo.is_even(7) == False
}

// ============================================================================
// Failure UX Demos
// Run with: gleam test -- --tag failure_demo
// ============================================================================

/// Demo: Binary operator assertion failure (==, !=, <, >, etc.)
/// Shows left and right values with their types (literal vs expression)
pub fn failure_demo_assert_binary_operator_test() {
  use <- unitest.tag("failure_demo")
  let actual = demo.add(2, 2)
  assert actual == 5
}

/// Demo: Function call assertion failure
/// Shows the function arguments that were passed
pub fn failure_demo_assert_function_call_test() {
  use <- unitest.tag("failure_demo")
  let numbers = [1, 2, 3]
  assert list.contains(numbers, 42)
}

/// Demo: Simple expression assertion failure
/// Shows the evaluated value of the expression
pub fn failure_demo_assert_expression_test() {
  use <- unitest.tag("failure_demo")
  let result = demo.is_even(7)
  assert result
}

/// Demo: Let assert pattern match failure
/// Shows the actual value that didn't match the expected pattern
pub fn failure_demo_let_assert_test() {
  use <- unitest.tag("failure_demo")
  let result = demo.divide(10, 0)
  let assert Ok(value) = result
  assert value == 5
}

/// Demo: Explicit panic
/// Shows the panic message
pub fn failure_demo_panic_test() {
  use <- unitest.tag("failure_demo")
  panic as "This is an intentional panic to demo the error formatting"
}

/// Demo: Todo expression reached
/// Shows the todo message for unimplemented code
pub fn failure_demo_todo_test() {
  use <- unitest.tag("failure_demo")
  todo as "This feature is not yet implemented"
}

/// Demo: Undefined function call (Generic error)
/// Shows how runtime errors from missing functions are displayed
pub fn failure_demo_undefined_function_test() {
  use <- unitest.tag("failure_demo")
  demo.call_undefined()
}

/// Demo: Returning Error Result
/// Shows how error results are displayed
pub fn failure_demo_error_result_test() -> Result(Nil, String) {
  use <- unitest.tag("failure_demo")
  Error("This is an intentional error result to demo the error formatting")
}
