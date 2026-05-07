# Java 25 Performance Benchmark Suite

Benchmark suite for measuring Java 25 performance features:
- **Compact Object Headers (JEP 450)**: Reduces per-object memory overhead
- **AOT Cache (Project Leyden)**: Pre-compiled code caching for faster startup

Was built by MiniMax M2.5 with prompting by Gemini Pro. Final version of prompt is in the bottom.

## Project Structure

```
java25-bench/
├── pom.xml                          # Maven build with Spring Boot 3.4.5
├── run_benchmarks.sh                # Automated benchmark orchestration
├── src/
│   └── main/
│       ├── java/com/example/demo/
│       │   ├── Java25BenchApp.java   # Spring Boot app with data generation
│       │   └── RetentionBean.java    # Record with 30 longs (256 bytes each)
│       └── resources/
│           └── application.properties
├── java25_benchmark_report.md        # Generated benchmark results
└── .gitignore
```

## Quick Start

```bash
chmod +x run_benchmarks.sh
./run_benchmarks.sh
```

## Requirements

- Java 25
- Maven 3.8+
- `bc` package (for bash math)

## JVM Flags Tested

| Configuration | JVM Flags |
|---------------|-----------|
| Baseline | `-Xmx2g -Xms2g` |
| Compact Headers Only | `-XX:+UseCompactObjectHeaders` |
| AOT Cache Only | `-XX:AOTCache=app.aot` |
| AOT + Compact Headers | `-XX:+UseCompactObjectHeaders -XX:AOTCache=app.aot` |

## Benchmark Results

<!-- AUTO-GENERATED: Do not edit manually -->
<!-- Results from java25_benchmark_report.md -->

# Java 25 Performance Benchmark Report
Compact Object Headers (JEP 450) + AOT Cache (Project Leyden)

**Generated:** 2026-05-07 01:14:42

| Bean Count | Configuration | Boot Time (s) | Gen Time (s) | Heap (MB) | Heap Saved | Boot Speedup |
|---|---|---|---|---|---|---|
| 500,000 | Baseline | 0.596 | 2.761 | 130.51 | - | - |
| 500,000 | Compact Headers Only | 0.603 | 2.669 | 126.16 | 3.00% | - |
| 500,000 | AOT Cache Only | 0.439 | 2.666 | 130.16 | - | 26.34% |
| 500,000 | AOT + Compact Headers | 0.423 | 2.553 | 125.92 | 3.00% | 29.02% |
| 2,000,000 | Baseline | 0.606 | 9.606 | 505.40 | - | - |
| 2,000,000 | Compact Headers Only | 0.616 | 9.488 | 489.44 | 3.00% | - |
| 2,000,000 | AOT Cache Only | 0.481 | 9.635 | 505.07 | - | 20.62% |
| 2,000,000 | AOT + Compact Headers | 0.373 | 9.509 | 489.21 | 3.00% | 38.44% |

<!-- END AUTO-GENERATED -->

## Architecture

### DataHolder Component
- Implements `ApplicationListener<ApplicationReadyEvent>` to separate framework boot time from data generation
- Generates 256-byte `RetentionBean` records with heavy BigDecimal/UUID math (simulates Hibernate/Jackson hydration)
- Objects are permanently retained in memory via class-level `List<RetentionBean>`

### Benchmark Methodology
1. Build once with Maven
2. Generate AOT cache (training run)
3. Measure 4 configurations:
   - Baseline
   - Compact Headers Only
   - AOT Cache Only
   - AOT + Compact Headers
4. Parse `GC.class_histogram` for exact byte-level heap measurement
5. Pin Java processes to P-cores (0-7) to eliminate scheduler noise

## Configuration

| Property | Default | Description |
|----------|---------|-------------|
| `app.test.bean-count` | 2000000 | Number of beans to generate |
| `app.test.string-size` | 1024 | Size of transient string per bean (CPU burn) |

## Prompt

Please build a Java 25 performance benchmarking suite from scratch to measure Compact Object Headers (JEP 450) and AOT Cache (Project Leyden). Generate three files: pom.xml, Java25BenchApp.java, and run_benchmarks.sh.
1. Java Application Logic (Java25BenchApp.java)

    Framework: Spring Boot 3.4+.

    The Bean Structure (256-byte Alignment Fix): To bypass the JVM's 8-byte alignment padding and show true memory savings, create a record RetentionBean with exactly 30 long fields (long v1 through long v30).

        Math: 12-byte header + 240 bytes of fields = 252 bytes (JVM pads to 256). Compact headers reduce this to 8-byte header + 240 bytes = 248 bytes (perfectly aligned, no padding). This guarantees exactly 8 bytes saved per object.

    Dual-Phase Lifecycle (Do NOT use @PostConstruct for generation): * The framework must boot as normal so we can measure clean startup time.

        Data Generation: Implement ApplicationListener<ApplicationReadyEvent>. Inside onApplicationEvent, generate the requested number of beans.

        Complication: Simulate a "heavy hydration" phase (like Hibernate/Jackson overhead) by performing UUID.randomUUID() generation and BigDecimal math to derive the 30 long values inside the loop.

    Signaling & Retention: * Wrap the generation loop in a timer and print: DATA_GENERATION_TIME_MS=XXXX.

        Print DATA_GENERATION_COMPLETE to standard out when finished.

        Store beans in a private final List within a @Component to ensure they are permanently retained on the heap.

2. The Execution Script (run_benchmarks.sh)

    Process Cleanup (CRITICAL): Because Java processes run in the background, you must include a robust cleanup() function at the top of the script that kills all stray JVMs to prevent locking up CPU cores. Use pkill -15 -f "java.*java25-bench", sleep 1, and pkill -9. Bind this to trap cleanup EXIT INT TERM.

    Hardware Pinning: Prefix ALL java commands (both training and execution runs) with taskset -c 0-7 to force execution on P-cores and eliminate OS scheduling noise.

    Logging: The log() function must write to standard error (>&2) to prevent log strings from leaking into the bash variables capturing the test results.

    Measurement Methodology (Wait for Signal):

        Start the Java process in the background. Use a while loop to wait until DATA_GENERATION_COMPLETE appears in the log file before taking measurements.

        Boot Time: Parse the official Spring Started ... in X seconds log line.

        Generation Time: Parse the DATA_GENERATION_TIME_MS log line and convert to seconds.

        Memory (No Serial GC): The benchmark must use the default G1GC. Do NOT use GC.heap_info as it suffers from G1 region fragmentation. Instead, run jcmd $PID GC.class_histogram, parse the Total bytes from the bottom line, and convert to MB using bc (scale=2).

    Testing Loop: Test two tiers: 500,000 and 2,000,000 beans. For each tier, run:

        Baseline: Standard JVM (-Xmx2g -Xms2g).

        Compact Headers: Add -XX:+UseCompactObjectHeaders.

        AOT Only: Training run (-XX:AOTCacheOutput), then Measurement run (-XX:AOTCache).

        AOT + Compact Headers: Combined flags and combined AOT cache.

3. Reporting & Formatting Logic

    Terminal Output: Print clean ASCII tables.

    Relative Math: Calculate and display "Memory Saved %" (vs baseline) and "Boot Speedup %" (vs baseline). Format the output like: (3.00% saved, 28.17% speedup). Ensure the bash math logic gracefully handles missing percentages for the baseline row.

    Markdown Export: Automatically generate a file named java25_benchmark_report.md. Initialize it with a title and table headers. Create a function to append a formatted Markdown table row (| Bean Count | Configuration | Boot Time (s) | Gen Time (s) | Heap (MB) | Heap Saved % | Boot Speedup % |) after each test run completes, so the user has a ready-to-publish artifact.

## License

MIT
