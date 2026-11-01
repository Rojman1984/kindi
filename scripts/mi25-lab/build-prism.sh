#!/usr/bin/env bash
# designlabsrvr: after the Kindi sweep finishes, clone + build PrismML-Eng/llama.cpp (Vulkan) in its own folder.
# Same CPU-portable flags as production (~/mi25/llama.cpp): GGML_NATIVE=OFF, BACKEND_DL, CPU_ALL_VARIANTS. -j4.
L=~/kindi/logs/build-prism.log
until grep -q '^# done' ~/kindi/logs/sweep.csv 2>/dev/null; do sleep 30; done
{
  echo "### start $(date)"
  D=~/mi25/llama.cpp-prism
  [ -d $D/.git ] || git clone https://github.com/PrismML-Eng/llama.cpp.git $D
  cd $D && git fetch -q --tags && echo "commit: $(git rev-parse HEAD) $(git describe --tags --always) ($(git log -1 --format=%cd --date=short))"
  # LLAMA_BUILD_TESTS=OFF: test-dfly-fusion does not link with GGML_BACKEND_DL (prism-b12128)
  cmake -B build -DCMAKE_BUILD_TYPE=Release -DGGML_VULKAN=ON -DGGML_NATIVE=OFF -DGGML_BACKEND_DL=ON \
        -DGGML_CPU_ALL_VARIANTS=ON -DBUILD_SHARED_LIBS=ON -DLLAMA_CURL=OFF -DLLAMA_BUILD_TESTS=OFF 2>&1 | tail -5
  cmake --build build --config Release -j4 2>&1 | grep -e error -e warning: -e 'Built target llama-' | tail -40
  echo "### build rc=${PIPESTATUS[0]}"
  ls build/bin | grep -e llama-bench -e llama-server -e llama-cli
  build/bin/llama-bench --list-devices 2>&1 | tail -8
  echo "### done $(date)"
} > $L 2>&1
