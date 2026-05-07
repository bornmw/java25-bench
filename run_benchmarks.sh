#!/bin/bash

set -e

APP_JAR="target/java25-bench-1.0.0.jar"
LOG_DIR="/tmp/java25_bench_logs"
REPORT_FILE="java25_benchmark_report.md"

rm -rf "$LOG_DIR"
mkdir -p "$LOG_DIR"

log() { echo -e "[$(date '+%H:%M:%S')] $1" >&2; }

if ! command -v bc &>/dev/null; then
    log "Installing bc..."
    apt-get update -qq && apt-get install -y -qq bc >/dev/null 2>&1 || yum install -y bc >/dev/null 2>&1 || apk add bc >/dev/null 2>&1 || true
fi

cleanup() {
    log "Cleaning up..."
    pkill -15 -f "java.*java25-bench" 2>/dev/null || true
    sleep 1
    pkill -9 -f "java.*java25-bench" 2>/dev/null || true
}
trap cleanup EXIT

extract_startup_time() {
    local log_file="$1"
    local line=$(grep "Started Java25BenchApp" "$log_file" 2>/dev/null | head -1)
    if [ -n "$line" ]; then
        echo "$line" | sed 's/.*Started Java25BenchApp in \([0-9.]*\).*/\1/'
    fi
}

extract_heap_used_mb() {
    local heap_output="$1"
    # Extract the bytes column from the 'Total' line at the bottom of the histogram
    local total_bytes=$(echo "$heap_output" | grep -i "^Total" | awk '{print $3}')
    if [ -z "$total_bytes" ] || [ "$total_bytes" -eq 0 ]; then
        echo "N/A"
        return 1
    fi
    # Convert bytes to MB
    echo "scale=2; $total_bytes / (1024 * 1024)" | bc 2>/dev/null || echo "N/A"
}

extract_generation_time() {
    local log_file="$1"
    grep "DATA_GENERATION_TIME_MS=" "$log_file" | cut -d'=' -f2 | awk '{printf "%.3f", $1/1000}' 2>/dev/null || echo "N/A"
}

safe_div() {
    local num="$1"
    local denom="$2"
    if [ -z "$num" ] || [ -z "$denom" ] || [ "$denom" = "0" ] || [ "$denom" = "N/A" ] || [ "$num" = "N/A" ]; then
        echo "0"
        return
    fi
    local result=$(echo "scale=4; ($num - $denom) / $num * 100" | bc 2>/dev/null || echo "0")
    if [ -z "$result" ] || [ "$result" = "-" ]; then
        echo "0"
    else
        printf "%.2f" "$result"
    fi
}

safe_diff() {
    local a="$1"
    local b="$2"
    if [ -z "$a" ] || [ -z "$b" ] || [ "$a" = "N/A" ] || [ "$b" = "N/A" ]; then
        echo "0.00"
    else
        echo "scale=2; $a - $b" | bc 2>/dev/null || echo "0.00"
    fi
}

format_diff() {
    local diff="$1"
    if [[ $(echo "$diff >= 0" | bc 2>/dev/null) == "1" ]]; then
        printf "+%.2f" "$diff"
    else
        printf "%.2f" "$diff"
    fi
}

run_test() {
    local config_name="$1"
    local jvm_opts="$2"
    local bean_count="$3"
    local description="$4"

    local log_file="$LOG_DIR/${config_name}_${bean_count}.log"
    local pid_file="/tmp/java25_pid_${config_name}_${bean_count}.tmp"

    log "Starting: $description (beans=$bean_count)"
    rm -f "$pid_file"

    (
        taskset -c 0-7 java $jvm_opts -Djdk.attach.allowAttachSelf=true -Dapp.test.bean-count="$bean_count" -jar "$APP_JAR" > "$log_file" 2>&1 &
        echo $! > "$pid_file"
        wait
    ) &
    local test_pid=$!

    local timeout=180
    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        if grep -q "DATA_GENERATION_COMPLETE" "$log_file" 2>/dev/null; then
            break
        fi
        if ! kill -0 $test_pid 2>/dev/null; then
            rm -f "$pid_file"
            echo "N/A,N/A"
            return
        fi
        sleep 0.5
        elapsed=$((elapsed + 1))
    done

    if [ ! -f "$pid_file" ]; then
        kill $test_pid 2>/dev/null || true
        echo "N/A,N/A"
        return
    fi

    local JAVA_PID=$(cat "$pid_file")
    rm -f "$pid_file"

    if ! kill -0 $JAVA_PID 2>/dev/null; then
        echo "N/A,N/A"
        return
    fi

    sleep 1
    # class_histogram inherently triggers a live-object GC and avoids fragmentation math
    local heap_info
    heap_info=$(jcmd $JAVA_PID GC.class_histogram 2>&1) || heap_info=""

    local startup_time
    startup_time=$(extract_startup_time "$log_file")
    local gen_time
    gen_time=$(extract_generation_time "$log_file")
    local heap_mb
    heap_mb=$(extract_heap_used_mb "$heap_info")

    log "Result: startup=${startup_time}s gen=${gen_time}s heap=${heap_mb}MB"

    kill -15 $JAVA_PID 2>/dev/null || true
    wait $test_pid 2>/dev/null || true
    sleep 1

    echo "${startup_time:-N/A},${gen_time:-N/A},${heap_mb:-N/A}"
}

print_table() {
    local bean_count=$1
    shift
    local results=("$@")

    local baseline_time="" baseline_gen="" baseline_heap=""
    local headers_time="" headers_gen="" headers_heap=""
    local aot_time="" aot_gen="" aot_heap=""
    local both_time="" both_gen="" both_heap=""

    local idx=0
    for result in "${results[@]}"; do
        local time=$(echo "$result" | cut -d',' -f1)
        local gen=$(echo "$result" | cut -d',' -f2)
        local heap=$(echo "$result" | cut -d',' -f3)
        case $idx in
            0) baseline_time="$time"; baseline_gen="$gen"; baseline_heap="$heap" ;;
            1) headers_time="$time"; headers_gen="$gen"; headers_heap="$heap" ;;
            2) aot_time="$time"; aot_gen="$gen"; aot_heap="$heap" ;;
            3) both_time="$time"; both_gen="$gen"; both_heap="$heap" ;;
        esac
        idx=$((idx + 1))
    done

    printf "\n"
    printf "═══════════════════════════════════════════════════════════════════\n"
    printf "  RESULTS FOR %'d BEANS\n" "$bean_count"
    printf "═══════════════════════════════════════════════════════════════════\n"
    printf "%-28s %8s %8s %10s\n" "Configuration" "Boot(s)" "Gen(s)" "Heap(MB)"
    printf "───────────────────────────────────────────────────────────────────\n"

    printf "%-28s %8s %8s %10s\n" "Baseline" "${baseline_time:-N/A}" "${baseline_gen:-N/A}" "${baseline_heap:-N/A}"

    append_to_markdown "$bean_count" "Baseline" "${baseline_time:-N/A}" "${baseline_gen:-N/A}" "${baseline_heap:-N/A}" "N/A" "N/A"

    if [ "$baseline_heap" != "N/A" ] && [ "$headers_heap" != "N/A" ] && [ -n "$baseline_heap" ]; then
        local heap_pct
        heap_pct=$(echo "scale=2; ($baseline_heap - $headers_heap) / $baseline_heap * 100" | bc 2>/dev/null || echo "0.00")
        printf "%-28s %8s %8s %10s  (%.2f%% saved)\n" "Compact Headers Only" "${headers_time:-N/A}" "${headers_gen:-N/A}" "${headers_heap:-N/A}" "$heap_pct"
        append_to_markdown "$bean_count" "Compact Headers Only" "${headers_time:-N/A}" "${headers_gen:-N/A}" "${headers_heap:-N/A}" "$heap_pct" "N/A"
    else
        printf "%-28s %8s %8s %10s\n" "Compact Headers Only" "${headers_time:-N/A}" "${headers_gen:-N/A}" "${headers_heap:-N/A}"
        append_to_markdown "$bean_count" "Compact Headers Only" "${headers_time:-N/A}" "${headers_gen:-N/A}" "${headers_heap:-N/A}" "N/A" "N/A"
    fi

    if [ "$baseline_time" != "N/A" ] && [ "$aot_time" != "N/A" ] && [ -n "$baseline_time" ] && [ -n "$aot_time" ]; then
        local speedup
        speedup=$(safe_div "$baseline_time" "$aot_time")
        printf "%-28s %8s %8s %10s  (speedup: %s%%)\n" "AOT Cache Only" "${aot_time:-N/A}" "${aot_gen:-N/A}" "${aot_heap:-N/A}" "$speedup"
        append_to_markdown "$bean_count" "AOT Cache Only" "${aot_time:-N/A}" "${aot_gen:-N/A}" "${aot_heap:-N/A}" "N/A" "$speedup"
    else
        printf "%-28s %8s %8s %10s\n" "AOT Cache Only" "${aot_time:-N/A}" "${aot_gen:-N/A}" "${aot_heap:-N/A}"
        append_to_markdown "$bean_count" "AOT Cache Only" "${aot_time:-N/A}" "${aot_gen:-N/A}" "${aot_heap:-N/A}" "N/A" "N/A"
    fi

    if [ "$baseline_time" != "N/A" ] && [ "$both_time" != "N/A" ] && [ "$baseline_heap" != "N/A" ] && [ "$both_heap" != "N/A" ]; then
        local speedup2
        speedup2=$(safe_div "$baseline_time" "$both_time")
        local heap_pct2
        heap_pct2=$(echo "scale=2; ($baseline_heap - $both_heap) / $baseline_heap * 100" | bc 2>/dev/null || echo "0.00")
        printf "%-28s %8s %8s %10s  (%.2f%% saved, %s%% speedup)\n" "AOT + Compact Headers" "${both_time:-N/A}" "${both_gen:-N/A}" "${both_heap:-N/A}" "$heap_pct2" "$speedup2"
        append_to_markdown "$bean_count" "AOT + Compact Headers" "${both_time:-N/A}" "${both_gen:-N/A}" "${both_heap:-N/A}" "$heap_pct2" "$speedup2"
    else
        printf "%-28s %8s %8s %10s\n" "AOT + Compact Headers" "${both_time:-N/A}" "${both_gen:-N/A}" "${both_heap:-N/A}"
        append_to_markdown "$bean_count" "AOT + Compact Headers" "${both_time:-N/A}" "${both_gen:-N/A}" "${both_heap:-N/A}" "N/A" "N/A"
    fi
printf "═══════════════════════════════════════════════════════════════════\n"
}

init_markdown_report() {
    cat > "$REPORT_FILE" << 'EOF'
# Java 25 Performance Benchmark Report
Compact Object Headers (JEP 450) + AOT Cache (Project Leyden)

**Generated:** TIMESTAMP_PLACEHOLDER

| Bean Count | Configuration | Boot Time (s) | Gen Time (s) | Heap (MB) | Heap Saved | Boot Speedup |
|---|---|---|---|---|---|---|
EOF
    sed -i "s/TIMESTAMP_PLACEHOLDER/$(date '+%Y-%m-%d %H:%M:%S')/" "$REPORT_FILE"
}

append_to_markdown() {
    local bean_count=$1
    local config=$2
    local boot=$3
    local gen=$4
    local heap=$5
    local heap_saved=$6
    local speedup=$7

    local saved_fmt=""
    local speedup_fmt=""

    if [ "$heap_saved" = "N/A" ] || [ "$heap_saved" = "-" ]; then
        saved_fmt="-"
    else
        saved_fmt="${heap_saved}%"
    fi

    if [ "$speedup" = "N/A" ] || [ "$speedup" = "-" ]; then
        speedup_fmt="-"
    else
        speedup_fmt="${speedup}%"
    fi

    printf "| %'d | %s | %s | %s | %s | %s | %s |\n" \
        "$bean_count" "$config" "$boot" "$gen" "$heap" "$saved_fmt" "$speedup_fmt" >> "$REPORT_FILE"
}

generate_aot_cache() {
    local opts="$1"
    local output="$2"
    local bean_count="$3"
    local log_file="$LOG_DIR/aot_train_${bean_count}.log"
    local pid_file="/tmp/java25_aot_pid_${bean_count}.tmp"

    log "Generating AOT cache: $output"
    rm -f "$pid_file"

    (
        taskset -c 0-7 java -Djdk.attach.allowAttachSelf=true $opts -XX:AOTCacheOutput="$output" -Dapp.test.bean-count="$bean_count" -jar "$APP_JAR" > "$log_file" 2>&1 &
        echo $! > "$pid_file"
        wait
    ) &
    local train_pid=$!

    local timeout=180
    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        if grep -q "DATA_GENERATION_COMPLETE" "$log_file" 2>/dev/null; then
            break
        fi
        if ! kill -0 $train_pid 2>/dev/null; then
            rm -f "$pid_file"
            return 1
        fi
        sleep 0.5
        elapsed=$((elapsed + 1))
    done

    if [ ! -f "$pid_file" ]; then
        return 1
    fi

    local JAVA_AOT_PID=$(cat "$pid_file")
    rm -f "$pid_file"

    if ! kill -0 $JAVA_AOT_PID 2>/dev/null; then
        return 1
    fi

    sleep 2
    kill -15 $JAVA_AOT_PID 2>/dev/null || true
    wait $train_pid 2>/dev/null || true
    sleep 1

    if [ -f "$output" ]; then
        log "AOT cache created: $(ls -lh "$output" 2>/dev/null | awk '{print $5}')"
        return 0
    else
        return 1
    fi
}

main() {
    log "=== Java 25 Performance Benchmark Suite ==="
    log "Compact Object Headers (JEP 450) + AOT Cache (Project Leyden)"
    echo ""

    if [ ! -f "./mvnw" ]; then
        log "Creating Maven wrapper..."
        mvn wrapper:wrapper -q 2>/dev/null || {
            log "ERROR: Failed to create Maven wrapper"
            exit 1
        }
    fi

    chmod +x ./mvnw

    log "Building application..."
    ./mvnw clean package -DskipTests -q

    if [ ! -f "$APP_JAR" ]; then
        log "ERROR: Build failed - JAR not found"
        exit 1
    fi

    log "Build successful: $(ls -lh "$APP_JAR" | awk '{print $5}')"
    echo ""

    init_markdown_report

    for bean_count in 500000 2000000; do
        log "=============================================="
        log "Testing with ${bean_count} beans"
        log "=============================================="

        generate_aot_cache "-XX:+UseCompactObjectHeaders -XX:AOTCacheOutput=app_both_${bean_count}.aot" "app_both_${bean_count}.aot" "$bean_count" || true
        generate_aot_cache "" "app_baseline_${bean_count}.aot" "$bean_count" || true

        log "Running Baseline..."
        baseline=$(run_test "baseline" "-Xmx2g -Xms2g" "$bean_count" "Baseline")

        log "Running Compact Headers Only..."
        headers=$(run_test "compact_headers" "-Xmx2g -Xms2g -XX:+UseCompactObjectHeaders" "$bean_count" "Compact Object Headers")

        log "Running AOT Cache Only..."
        aot=""
        if [ -f "app_baseline_${bean_count}.aot" ]; then
            aot=$(run_test "aot_cache" "-Xmx2g -Xms2g -XX:AOTCache=app_baseline_${bean_count}.aot" "$bean_count" "AOT Cache")
        else
            log "SKIP: AOT cache not available"
            aot="N/A,N/A"
        fi

        log "Running AOT + Compact Headers..."
        both=""
        if [ -f "app_both_${bean_count}.aot" ]; then
            both=$(run_test "aot_compact" "-Xmx2g -Xms2g -XX:+UseCompactObjectHeaders -XX:AOTCache=app_both_${bean_count}.aot" "$bean_count" "AOT + Compact Headers")
        else
            log "SKIP: Combined AOT cache not available"
            both="N/A,N/A"
        fi

        print_table "$bean_count" "$baseline" "$headers" "$aot" "$both"

        rm -f "app_baseline_${bean_count}.aot" "app_both_${bean_count}.aot" 2>/dev/null || true
    done

    log "Benchmark complete."
    log "Markdown report generated: $REPORT_FILE"
}

main "$@"