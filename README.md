# Java 25 Performance Benchmark Suite

## Project Overview

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
│       │   └── Java25BenchApp.java  # Spring Boot app + 10 @Entity classes
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

## Application Stack

The benchmark simulates a heavy enterprise Spring Boot service:

| Dependency | Purpose |
|------------|---------|
| spring-boot-starter-web | Jackson JSON, Tomcat |
| spring-boot-starter-data-jpa | Hibernate, Entity scanning |
| spring-boot-starter-security | Security filter chain proxy |
| spring-boot-starter-validation | Bean validation |
| h2 | Database driver |

**Heavy Components:**
- 10 @Entity classes (DummyEntity1-10) for Hibernate metadata initialization
- SecurityFilterChain bean for Spring Security filter proxy generation
- 256-byte RetentionBean records for memory footprint testing

## JVM Flags Tested

| Configuration | JVM Flags |
|---------------|-----------|
| Baseline | `-Xmx2g -Xms2g` |
| Compact Headers Only | `-XX:+UseCompactObjectHeaders` |
| AOT Cache Only | `-XX:AOTCache=app.aot` |
| AOT + Compact Headers | `-XX:+UseCompactObjectHeaders -XX:AOTCache=app.aot` |

## Benchmark Results

| Bean Count | Configuration | Boot Time (s) | Gen Time (s) | Heap (MB) | Heap Saved | Boot Speedup |
|---|---|---|---|---|---|---|
| 500,000 | Baseline | 2.989 | 3.280 | 145.35 | - | - |
| 500,000 | Compact Headers Only | 2.979 | 3.196 | 139.42 | 4.00% | - |
| 500,000 | AOT Cache Only | 2.129 | 3.095 | 144.50 | - | 28.77% |
| 500,000 | AOT + Compact Headers | 2.027 | 3.275 | 138.69 | 4.00% | 32.18% |
| 2,000,000 | Baseline | 2.916 | 11.267 | 520.25 | - | - |
| 2,000,000 | Compact Headers Only | 3.074 | 11.111 | 502.89 | 3.00% | - |
| 2,000,000 | AOT Cache Only | 2.159 | 11.307 | 519.52 | - | 25.96% |
| 2,000,000 | AOT + Compact Headers | 2.124 | 10.848 | 502.03 | 3.00% | 27.16% |

**Generated:** 2026-05-07 02:03:11

## Key Findings

- **AOT Cache** provides **26-32% boot time speedup** by caching JIT-compiled class metadata
- **Compact Object Headers** saves **3-4% heap memory** per configuration
- **Combined** (AOT + Compact Headers) provides both startup improvement and memory savings

## Methodology

1. Build once with Maven
2. Generate AOT cache (training run of ~15 seconds)
3. Measure 4 configurations per test tier:
   - Baseline
   - Compact Headers Only
   - AOT Cache Only
   - AOT + Compact Headers
4. Pin Java processes to P-cores (0-7) to eliminate scheduler noise
5. Parse `GC.class_histogram` for exact byte-level heap measurement
6. Separate boot time from data generation time via ApplicationReadyEvent

## Configuration

| Property | Default | Description |
|----------|---------|-------------|
| `app.test.bean-count` | 2000000 | Number of RetentionBean records |
| `app.test.string-size` | 1024 | CPU burn per iteration |

## License

MIT

---

## Original Prompt

> Please build a Java 25 performance benchmarking suite from scratch to measure Compact Object Headers (JEP 450) and AOT Cache (Project Leyden). Generate three files: pom.xml, Java25BenchApp.java, and run_benchmarks.sh.
>
> 1. Project Weight (pom.xml)
>
>     Framework: Spring Boot 3.4+.
>
>     Dependencies: Add the following to simulate a heavy enterprise classpath: spring-boot-starter-web, spring-boot-starter-data-jpa, spring-boot-starter-security, spring-boot-starter-validation, and com.h2database:h2 (runtime).
>
>     Compiler: Set java.version to 25.
>
> 2. Java Application Logic (Java25BenchApp.java)
>
>     Enterprise Bloat: Create 10 dummy @Entity classes (DummyEntity1 to DummyEntity10) with an @Id to force Hibernate metadata scanning. Add a @Configuration class that defines a SecurityFilterChain bean.
>
>     Bean Structure (256-byte Alignment): Create a record RetentionBean with exactly 30 long fields (long v1 through long v30). Math: 12-byte header + 240 bytes = 252 bytes (padded to 256). Compact headers reduce this to 8-byte header + 240 bytes = 248 bytes. This guarantees exactly 8 bytes saved per object.
>
>     Dual-Phase Lifecycle: Use ApplicationListener<ApplicationReadyEvent> for data generation so that Spring's official "Started" timer only reflects the framework boot. In the generation loop, simulate "Heavy Hydration" by performing UUID.randomUUID() and BigDecimal calculations.
>
>     Signaling: Wrap the generation loop in a timer and print: DATA_GENERATION_TIME_MS=XXXX. Print DATA_GENERATION_COMPLETE when finished. Store beans in a private final List to ensure they are retained.
>
> 3. The Execution Script (run_benchmarks.sh)
>
>     Safety (Cleanup Trap): Include a cleanup() function using pkill -15 -f "java.*java25-bench", sleep 1, and pkill -9. Bind it to trap cleanup EXIT INT TERM.
>
>     Stability (Hardware Pinning): Prefix ALL java commands with taskset -c 0-7 to force execution on P-cores.
>
>     Logging: The log() function must write to standard error (>&2) to avoid leaking into result variables.
>
>     Measurement Methodology: Startup Time from Spring log. Gen Time from DATA_GENERATION_TIME_MS. Memory using jcmd $PID GC.class_histogram, parse Total bytes and convert to MB with bc. Do NOT use Serial GC.
>
>     Wait for Signal: Use while loop to wait until DATA_GENERATION_COMPLETE appears.
>
> 4. Reporting
>
>     Terminal Output: Print clean ASCII tables for 500,000 and 2,000,000 beans.
>
>     Relative Math: Display percentage memory saved and percentage boot speedup vs. the baseline.
>
>     Markdown Export: Automatically generate java25_benchmark_report.md with unified table: | Bean Count | Configuration | Boot Time (s) | Gen Time (s) | Heap (MB) | Heap Saved % | Boot Speedup % |.