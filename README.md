# Java 25 Performance Benchmark Suite

Benchmark suite for measuring Java 25 performance features:
- **Compact Object Headers (JEP 450)**: Reduces per-object memory overhead
- **AOT Cache (Project Leyden)**: Pre-compiled code caching for faster startup

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

## License

MIT