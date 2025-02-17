#!/bin/bash
# Copyright (c) Meta Platforms, Inc. and affiliates.
# All rights reserved.
#
# This source code is licensed under the BSD-style license found in the
# LICENSE file in the root directory of this source tree.

# Test the end-to-end flow of using custom operator in a PyTorch model and use
# EXIR to capture and export a model file. Then use `executor_runner` demo C++
# binary to run the model.

set -e

# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/../../../.ci/scripts/utils.sh"

test_buck2_custom_op_1() {
  local model_name='custom_ops_1'
  echo "Exporting ${model_name}.pte"
  ${PYTHON_EXECUTABLE} -m "examples.portable.custom_ops.${model_name}"
  # should save file custom_ops_1.pte

  echo 'Running executor_runner'
  $BUCK2 run //examples/portable/executor_runner:executor_runner \
      --config=executorch.register_custom_op=1 -- --model_path="./${model_name}.pte"
  # should give correct result

  echo "Removing ${model_name}.pte"
  rm "./${model_name}.pte"
}

test_cmake_custom_op_1() {
  local model_name='custom_ops_1'
  echo "Exporting ${model_name}.pte"
  ${PYTHON_EXECUTABLE} -m "examples.portable.custom_ops.${model_name}"
  # should save file custom_ops_1.pte
  (rm -rf cmake-out \
    && mkdir cmake-out \
    && cd cmake-out \
    && retry cmake -DBUCK2=$BUCK2 \
        -DREGISTER_EXAMPLE_CUSTOM_OP=1 \
        -DPYTHON_EXECUTABLE="$PYTHON_EXECUTABLE" ..)

  echo 'Building executor_runner'
  cmake --build cmake-out -j9

  echo 'Running executor_runner'
  cmake-out/executor_runner --model_path="./${model_name}.pte"
}

test_buck2_custom_op_2() {
  local model_name='custom_ops_2'

  echo 'Building custom ops shared library'
  SO_LIB=$($BUCK2 build //examples/portable/custom_ops:custom_ops_aot_lib_2 --show-output | grep "buck-out" | cut -d" " -f2)

  echo "Exporting ${model_name}.pte"
  ${PYTHON_EXECUTABLE} -m "examples.portable.custom_ops.${model_name}" --so_library="$SO_LIB"
  # should save file custom_ops_2.pte

  $BUCK2 run //examples/portable/executor_runner:executor_runner \
      --config=executorch.register_custom_op=2 -- --model_path="./${model_name}.pte"
  # should give correct result
  echo "Removing ${model_name}.pte"
  rm "./${model_name}.pte"
}

get_shared_lib_ext() {
  UNAME=$(uname)
  if [[ $UNAME == "Darwin" ]];
  then
    EXT=".dylib"
  elif [[ $UNAME == "Linux" ]];
  then
    EXT=".so"
  else
    echo "Unsupported platform $UNAME"
    exit 1
  fi
  echo $EXT
}

test_cmake_custom_op_2() {
  local model_name='custom_ops_2'
  SITE_PACKAGES="$(${PYTHON_EXECUTABLE} -c 'from distutils.sysconfig import get_python_lib; print(get_python_lib())')"
  CMAKE_PREFIX_PATH="${SITE_PACKAGES}/torch"

  (rm -rf cmake-out \
    && mkdir cmake-out \
    && cd cmake-out \
    && retry cmake -DBUCK2=$BUCK2 \
      -DREGISTER_EXAMPLE_CUSTOM_OP=2 \
      -DCMAKE_PREFIX_PATH="$CMAKE_PREFIX_PATH" \
      -DPYTHON_EXECUTABLE="$PYTHON_EXECUTABLE" ..)

  echo 'Building executor_runner'
  cmake --build cmake-out -j4

  EXT=$(get_shared_lib_ext)
  echo "Exporting ${model_name}.pte"
  ${PYTHON_EXECUTABLE} -m "examples.portable.custom_ops.${model_name}" --so_library="cmake-out/examples/portable/custom_ops/libcustom_ops_aot_lib$EXT"
  # should save file custom_ops_2.pte

  echo 'Running executor_runner'
  cmake-out/executor_runner "--model_path=./${model_name}.pte"
}

if [[ -z $PYTHON_EXECUTABLE ]];
then
  PYTHON_EXECUTABLE=python3
fi

if [[ -z $BUCK2 ]];
then
  BUCK2=buck2
fi

if [[ $1 == "cmake" ]];
then
  test_cmake_custom_op_1
  test_cmake_custom_op_2
elif [[ $1 == "buck2" ]];
then
  test_buck2_custom_op_1
  test_buck2_custom_op_2
else
  test_cmake_custom_op_1
  test_cmake_custom_op_2
  test_buck2_custom_op_1
  test_buck2_custom_op_2
fi
