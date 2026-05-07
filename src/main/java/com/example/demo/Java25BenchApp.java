package com.example.demo;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.context.ApplicationListener;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.scheduling.annotation.EnableScheduling;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;
import org.springframework.boot.context.event.ApplicationReadyEvent;
import org.springframework.security.web.SecurityFilterChain;
import static org.springframework.security.config.Customizer.withDefaults;

import jakarta.persistence.*;
import java.math.BigDecimal;
import java.math.RoundingMode;
import java.util.Random;
import java.util.UUID;

@SpringBootApplication
@EnableScheduling
public class Java25BenchApp {

    public static void main(String[] args) {
        SpringApplication.run(Java25BenchApp.class, args);
    }

    @Bean
    public DataHolder dataHolder() {
        return new DataHolder();
    }

    @Bean
    public KeepAlive keepAlive(DataHolder dataHolder) {
        return new KeepAlive(dataHolder);
    }
}

@Configuration
class SecurityConfig {
    @Bean
    public SecurityFilterChain filterChain(org.springframework.security.config.annotation.web.builders.HttpSecurity http) throws Exception {
        http
            .authorizeHttpRequests(auth -> auth.anyRequest().permitAll())
            .csrf(csrf -> csrf.disable())
            .formLogin(withDefaults());
        return http.build();
    }
}

@Component
class DataHolder implements ApplicationListener<ApplicationReadyEvent> {
    private final java.util.List<RetentionBean> retainedBeans = new java.util.ArrayList<>();
    private volatile boolean initialized = false;

    public int getRetainedCount() {
        return retainedBeans.size();
    }

    public long getTotalMemory() {
        long total = 0;
        for (RetentionBean bean : retainedBeans) {
            total += bean.getSizeEstimate();
        }
        return total;
    }

    @Override
    public void onApplicationEvent(ApplicationReadyEvent event) {
        if (initialized) return;
        initialized = true;

        String beanCountStr = System.getProperty("app.test.bean-count", "2000000");
        int beanCount = Integer.parseInt(beanCountStr);

        long start = System.currentTimeMillis();

        Random random = new Random(42);

        for (int i = 0; i < beanCount; i++) {
            String uuid = UUID.randomUUID().toString();
            String stripped = uuid.replace("-", "");
            String chunk1 = stripped.substring(0, 8);
            String chunk2 = stripped.substring(8, 16);
            String chunk3 = stripped.substring(16, 24);
            String chunk4 = stripped.substring(24, 32);

            long seed = chunk1.hashCode() + (chunk2.hashCode() << 8);
            int s1 = chunk1.hashCode();
            int s2 = chunk2.hashCode();
            int s3 = chunk3.hashCode();
            int s4 = chunk4.hashCode();
            int s5 = stripped.hashCode();

            BigDecimal bd1 = new BigDecimal(seed);
            BigDecimal bd2 = new BigDecimal(Math.abs(s2));
            BigDecimal bd3 = new BigDecimal(Math.sqrt(Math.abs(s3)));
            BigDecimal bd4 = new BigDecimal(Math.pow(Math.abs(s4), 2));
            BigDecimal bd5 = new BigDecimal(Math.log(Math.abs(s5) + 1));

            long v1 = bd1.multiply(bd2).divide(bd3, RoundingMode.HALF_UP).longValue() + random.nextLong();
            long v2 = bd2.multiply(bd3).divide(bd4, RoundingMode.HALF_UP).longValue() + random.nextLong();
            long v3 = bd3.multiply(bd4).divide(bd5, RoundingMode.HALF_UP).longValue() + random.nextLong();
            long v4 = bd4.multiply(bd5).multiply(bd1).longValue() + random.nextLong();
            long v5 = bd5.add(bd1).subtract(bd2).longValue() + random.nextLong();
            long v6 = bd1.add(bd2).add(bd3).longValue() + random.nextLong();
            long v7 = bd2.subtract(bd3).abs().longValue() + random.nextLong();
            long v8 = bd3.multiply(new BigDecimal(Math.sin(i))).longValue() + random.nextLong();
            long v9 = bd4.multiply(new BigDecimal(Math.cos(i))).longValue() + random.nextLong();
            long v10 = bd5.add(new BigDecimal(i % 1000)).longValue() + random.nextLong();
            long v11 = new BigDecimal(Math.tan(i * 0.01)).multiply(bd1).longValue() + random.nextLong();
            long v12 = bd1.pow(2).divide(bd2.add(BigDecimal.ONE), RoundingMode.HALF_UP).longValue() + random.nextLong();
            long v13 = bd2.pow(2).multiply(bd3).longValue() + random.nextLong();
            long v14 = new BigDecimal(Math.sqrt(Math.abs(s4)), new java.math.MathContext(10)).multiply(bd4).longValue() + random.nextLong();
            long v15 = bd4.divide(bd5.add(BigDecimal.ONE), RoundingMode.HALF_UP).longValue() + random.nextLong();
            long v16 = v1 ^ (v2 >>> 1);
            long v17 = v2 ^ (v3 >>> 2);
            long v18 = v3 ^ (v4 >>> 3);
            long v19 = v4 ^ (v5 >>> 4);
            long v20 = (v1 + v2 + v3) * (v4 | 0xFF);
            long v21 = (v5 - v6 + v7) & 0xFFFFFFFFL;
            long v22 = (v8 * v9) ^ (v10 + v11);
            long v23 = (v12 / (v13 + 1)) + (v14 - v15);
            long v24 = (v16 + v17 + v18 + v19) ^ (v20 & 0xFFFF);
            long v25 = Math.abs(v1 * 31 + v2 * 37 + v3 * 41);
            long v26 = (long) (Math.random() * Long.MAX_VALUE);
            long v27 = (long) (Math.random() * Long.MAX_VALUE);
            long v28 = (long) (Math.random() * Long.MAX_VALUE);
            long v29 = (long) (Math.random() * Long.MAX_VALUE);
            long v30 = (long) (Math.random() * Long.MAX_VALUE);

            retainedBeans.add(new RetentionBean(
                v1, v2, v3, v4, v5, v6, v7, v8, v9, v10,
                v11, v12, v13, v14, v15, v16, v17, v18, v19, v20,
                v21, v22, v23, v24, v25, v26, v27, v28, v29, v30
            ));
        }

        long end = System.currentTimeMillis();
        System.out.println("DATA_GENERATION_TIME_MS=" + (end - start));
        System.out.println("DATA_GENERATION_COMPLETE");
    }
}

record RetentionBean(
    long v1, long v2, long v3, long v4, long v5,
    long v6, long v7, long v8, long v9, long v10,
    long v11, long v12, long v13, long v14, long v15,
    long v16, long v17, long v18, long v19, long v20,
    long v21, long v22, long v23, long v24, long v25,
    long v26, long v27, long v28, long v29, long v30
) {
    public long getSizeEstimate() { return 256; }
}

class KeepAlive {
    private final DataHolder dataHolder;

    KeepAlive(DataHolder dataHolder) {
        this.dataHolder = dataHolder;
    }

    @Scheduled(fixedDelay = Long.MAX_VALUE)
    public void stayAlive() {
    }
}

@Entity
class DummyEntity1 {
    @Id private Long id;
    private String field1;
    private Integer field2;
    private BigDecimal field3;
}

@Entity
class DummyEntity2 {
    @Id private Long id;
    private String field1;
    private Integer field2;
    private BigDecimal field3;
}

@Entity
class DummyEntity3 {
    @Id private Long id;
    private String field1;
    private Integer field2;
    private BigDecimal field3;
}

@Entity
class DummyEntity4 {
    @Id private Long id;
    private String field1;
    private Integer field2;
    private BigDecimal field3;
}

@Entity
class DummyEntity5 {
    @Id private Long id;
    private String field1;
    private Integer field2;
    private BigDecimal field3;
}

@Entity
class DummyEntity6 {
    @Id private Long id;
    private String field1;
    private Integer field2;
    private BigDecimal field3;
}

@Entity
class DummyEntity7 {
    @Id private Long id;
    private String field1;
    private Integer field2;
    private BigDecimal field3;
}

@Entity
class DummyEntity8 {
    @Id private Long id;
    private String field1;
    private Integer field2;
    private BigDecimal field3;
}

@Entity
class DummyEntity9 {
    @Id private Long id;
    private String field1;
    private Integer field2;
    private BigDecimal field3;
}

@Entity
class DummyEntity10 {
    @Id private Long id;
    private String field1;
    private Integer field2;
    private BigDecimal field3;
}