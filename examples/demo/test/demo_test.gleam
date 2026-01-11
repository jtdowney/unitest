//// Basic tests for the demo module.

import demo
import gleam/option.{None}
import unitest.{Options}

pub fn main() {
  // Skip "slow" tagged tests by default
  // Run them explicitly with: gleam test -- --tag slow
  unitest.run(Options(seed: None, ignored_tags: ["slow"]))
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
