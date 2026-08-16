#!/usr/bin/env bash

# Exit immediately if a command exits with a non-zero status
set -euo pipefail

# 1. Models compatible with 8GB VRAM - good for coding tasks
MODELS=(
    "qwen2.5-coder:7b"
    "deepseek-r1:8b"
    "mixtral:8x7b"
    "mistral:7b"
    "llama3.1:8b"
    "phi4-mini"
    "gemma4:latest"
)

# 2. Check if Ollama is running
if ! curl -s http://localhost:11434/api/tags > /dev/null; then
    echo "❌ Error: Ollama service is not running."
    echo "Please start Ollama and try again."
    exit 1
fi

echo "🚀 Starting Ollama Model Setup & Benchmark..."

# 3. Pull models
for model in "${MODELS[@]}"; do
    echo "----------------------------------------"
    echo "📥 Pulling updates for: $model"
    ollama pull "$model"
done

# 4. Benchmark prompt
TEST_PROMPT="Write a short Python function to calculate Fibonacci numbers up to N."

echo "========================================"
echo "📊 Running Speed & Performance Benchmarks"
echo "========================================"

# 5. Execute benchmarks
for model in "${MODELS[@]}"; do
    echo -n "⏱️ Testing $model... "
    
    # Measure total execution time of the generation command
    START_TIME=$(date +%s.%N)
    RESPONSE=$(ollama run "$model" "$TEST_PROMPT" 2>&1)
    END_TIME=$(date +%s.%N)
    
    # Calculate elapsed time using standard arithmetic
    ELAPSED=$(echo "$END_TIME - $START_TIME" | bc)
    
    echo "Completed in ${ELAPSED}s"
done

echo "----------------------------------------"
echo "✅ All models downloaded and tested successfully!"
